import AppKit
import CopiloteKit

/// Exercises the same controller action as the registered shortcut, without registering hotkeys.
@MainActor
enum DiagnosticPanelShortcut {
    static func run(folder: URL, overlay: OverlayController, settings: SettingsStore,
                    listening: ListeningController, assist: AssistController, session: SessionController,
                    record: (String, Bool) -> Void) async {
        guard DiagnosticAnchorFixture.isRequested, let screen = NSScreen.main,
              let pill = NSApp.windows.first(where: { $0.windowNumber == overlay.windowNumbers[0] }),
              let panel = NSApp.windows.first(where: { $0.windowNumber == overlay.windowNumbers[1] }) as? OverlayPanel else { return }
        var rows: [[String: Any]] = []
        var answerRequests = 0
        let oldAnswerAction = overlay.onAnswerLatestTopic
        overlay.onAnswerLatestTopic = { answerRequests += 1 }
        defer { overlay.onAnswerLatestTopic = oldAnswerAction }
        func pause() async { try? await Task.sleep(for: .milliseconds(35)) }
        func geometry(_ name: String, _ anchor: NSRect, _ body: NSRect) {
            let delta = max(abs(pill.frame.minX-anchor.minX), abs(pill.frame.minY-anchor.minY),
                            abs(panel.frame.minX-body.minX), abs(panel.frame.minY-body.minY))
            rows.append(["name": name, "anchorBefore": NSStringFromRect(anchor), "anchorAfter": NSStringFromRect(pill.frame),
                         "panelBefore": NSStringFromRect(body), "panelAfter": NSStringFromRect(panel.frame), "maxOriginDelta": delta])
            record(name + " keeps native origins", delta < 0.01)
        }
        func marker(in view: NSView) -> InlineControlMarker? {
            if view.identifier?.rawValue == "PillFold" { return view as? InlineControlMarker }
            return view.subviews.lazy.compactMap { marker(in: $0) }.first
        }
        record("panel shortcut has the requested settings label", ShortcutCatalog.all.contains { $0.name == .togglePanel && $0.label == "Expand/collapse panel" })
        record("panel shortcut is registered only while visible", ShortcutCatalog.visibleOnly.contains(.togglePanel) && !ShortcutCatalog.panelOnly.contains(.togglePanel) && !ShortcutCatalog.topicsOnly.contains(.togglePanel))
        record("catalog and defaults have exactly the same unique names", Set(ShortcutCatalog.all.map { $0.name.rawValue }) == Set(ShortcutDefaults.all.map(\.name)) && Set(ShortcutCatalog.all.map { $0.name.rawValue }).count == ShortcutCatalog.all.count)
        let area = screen.visibleFrame
        let origins = [CGPoint(x:area.minX,y:area.maxY-60), CGPoint(x:area.midX-300,y:area.midY), CGPoint(x:area.maxX-600,y:area.minY)]
        for stealth in [true, false] {
            settings.requestStealth(stealth, from: .settings)
            if let request = settings.pendingStealthOff { settings.confirmStealthOff(request.id) }
            for mode in ["idle", "listening", "paused"] {
                if mode != "idle" { listening.beginRecetteConversation() }
                if mode == "paused" { listening.pauseOrResume() }
                for (index, origin) in origins.enumerated() {
                    WindowPrivacy.authorizeFromUserGesture(); overlay.present(); overlay.reveal()
                    pill.setFrameOrigin(origin)
                    // Reconcile an initial placement before measuring repeated transitions.
                    overlay.pillClicked(); overlay.pillClicked(); await pause()
                    let anchor = pill.frame, body = panel.frame
                    let historyCount = session.history.count
                    let state = listening.state, paused = listening.isPaused
                    let tag = "panel shortcut stealth=\(stealth) session=\(mode) position=\(index)"
                    for cycle in 0..<3 {
                        assist.askText = "Fictional unsent draft \(cycle)"
                        let draft = assist.askText
                        if cycle == 1 { overlay.startTyping() }
                        overlay.pillClicked(); await pause()
                        record("\(tag) fold \(cycle)", overlay.model.machine.presentation == .pill && !overlay.model.isTyping && panel.parent == nil)
                        geometry("\(tag) fold \(cycle)",anchor,body)
                        // Compare the shortcut action with the action bound to the real arrow.
                        pill.contentView?.layoutSubtreeIfNeeded()
                        let invoked = pill.contentView.flatMap { marker(in:$0) }?.invokeHeadlessAction() == true
                        record("\(tag) arrow action \(cycle)",invoked)
                        await pause()
                        record("\(tag) unfold without taking keyboard \(cycle)",overlay.model.machine.presentation == .panel && !overlay.model.isTyping && !panel.allowsKey && panel.parent === pill)
                        geometry("\(tag) unfold \(cycle)",anchor,body)
                        record("\(tag) draft and session unchanged \(cycle)",assist.askText == draft && session.history.count == historyCount && !session.isAnswering && answerRequests == 0 && listening.state == state && listening.isPaused == paused && settings.stealth == stealth)
                    }
                    for folded in [false, true] {
                        if folded { overlay.pillClicked() }
                        overlay.hide()
                        let machine = overlay.model.machine
                        overlay.pillClicked(); overlay.pillClicked()
                        record("\(tag) hidden no-op folded=\(folded)",overlay.model.machine == machine && !WindowPrivacy.presentationAuthorized)
                        geometry("\(tag) hidden folded=\(folded)",anchor,body)
                        WindowPrivacy.authorizeFromUserGesture(); overlay.present(); overlay.reveal()
                    }
                }
                await listening.stop()
            }
        }
        record("panel shortcut fixture never shows or takes desktop windows", !NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow })
        overlay.hide()
        let result: [String: Any] = ["geometry": rows, "answerRequests": answerRequests, "globalShortcutEventsSent": false,
            "globalShortcutsRegistered": false, "desktopKeyboardTaken": false, "audio": false,
            "limitation": "Controller and real arrow-bound action exercised headlessly; OS hotkey delivery and visible focus transitions are not exercised."]
        try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("panel-shortcut.json"))
    }
}
