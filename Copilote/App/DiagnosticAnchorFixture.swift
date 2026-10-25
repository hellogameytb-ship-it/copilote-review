import AppKit
import CopiloteKit

/// Real controller/native-frame measurements without ordering any window or taking desktop keys.
/// Native interactive focus, physical dragging and multiple real Spaces require a later safe run.
@MainActor
enum DiagnosticAnchorFixture {
    static var isRequested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-CopiloteRecette") && args.contains("-RecetteAnchorOnly")
    }

    static func run(folder: URL, overlay: OverlayController, settings: SettingsStore,
                    assist: AssistController, session: SessionController, menu: PillMenuController,
                    mainWindow: MainWindowController, record: (String, Bool) -> Void) async {
        guard isRequested, let screen = NSScreen.main,
              let pill = NSApp.windows.first(where: { $0.windowNumber == overlay.windowNumbers[0] }),
              let panel = NSApp.windows.first(where: { $0.windowNumber == overlay.windowNumbers[1] }) else { return }
        let area = screen.visibleFrame
        var samples: [[String: Any]] = []
        var spaceChanges = 0
        var ownActivations = 0
        let token = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in spaceChanges += 1 }
        let activationToken = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { note in
            if (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == ProcessInfo.processInfo.processIdentifier { ownActivations += 1 }
        }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(token); NSWorkspace.shared.notificationCenter.removeObserver(activationToken) }
        func pause(_ ms: Int = 30) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func measure(_ name: String, anchor: NSRect, panelBefore: NSRect, requirePanelStable: Bool = true) {
            let current = pill.frame, body = panel.frame
            let delta = max(abs(current.minX-anchor.minX), abs(current.minY-anchor.minY))
            let bodyDelta = max(abs(body.minX-panelBefore.minX), abs(body.minY-panelBefore.minY))
            let passed = delta < 0.01 && (!requirePanelStable || bodyDelta < 0.01) && panel.parent === pill
            samples.append(["name":name,"anchorBefore":NSStringFromRect(anchor),"anchorAfter":NSStringFromRect(current),
                            "panelBefore":NSStringFromRect(panelBefore),"panelAfter":NSStringFromRect(body),
                            "anchorDelta":delta,"panelOriginDelta":bodyDelta,"panelStabilityRequired":requirePanelStable,
                            "passed":passed,"nativeChildAttached":panel.parent === pill,"spaceChanges":spaceChanges,"applicationActive":NSApp.isActive])
            record(name, passed)
        }
        let origins = [
            CGPoint(x:area.midX-300, y:area.maxY-60),
            CGPoint(x:area.minX, y:area.maxY-60),
            CGPoint(x:area.maxX-600, y:area.maxY-60),
            CGPoint(x:area.midX-300, y:area.midY),
            CGPoint(x:area.minX, y:area.minY),
            CGPoint(x:area.maxX-600, y:area.minY)
        ]
        let focusFixture = OverlayPanel(size:NSSize(width:200,height:100),resizable:false)
        focusFixture.allowsKey = true
        let otherEditor = NSTextView(frame:NSRect(x:0,y:0,width:200,height:100))
        focusFixture.contentView = otherEditor
        defer { focusFixture.orderOut(nil) }
        for stealth in [true, false] {
            settings.requestStealth(stealth, from: .settings); if let request = settings.pendingStealthOff { settings.confirmStealthOff(request.id) }
            WindowPrivacy.authorizeFromUserGesture(); overlay.present()
            record("policy \(stealth) remains unshown", NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow } && NSApp.activationPolicy() == .accessory)
            for (index, origin) in origins.enumerated() {
                for folded in [false, true] {
                    WindowPrivacy.authorizeFromUserGesture(); overlay.reveal()
                    if folded { overlay.pillClicked() }
                    // The WindowServer moves the parent AFTER performDrag has returned.
                    // Use actual NSWindow frames/native child coupling, not a mocked placement result.
                    (pill as? OverlayPanel)?.onWorkspaceDragBegan?()
                    overlay.landDraggedWorkspace()
                    await pause()
                    pill.setFrameOrigin(origin)
                    let anchor = pill.frame, before = panel.frame
                    let tag = "stealth=\(stealth) position=\(index) folded=\(folded)"
                    overlay.startTyping()
                    measure("\(tag) Ask immediate", anchor:anchor, panelBefore:before, requirePanelStable:!folded)
                    await pause(260)
                    measure("\(tag) Ask async focus requests", anchor:anchor, panelBefore:before, requirePanelStable:!folded)
                    let expanded = panel.frame
                    // A local responder transition does not require this process to take desktop keys.
                    let localEditor = NSTextView(frame:NSRect(x:0,y:0,width:80,height:20))
                    panel.contentView?.addSubview(localEditor)
                    record("\(tag) local native responder accepted",panel.makeFirstResponder(localEditor) && panel.firstResponder === localEditor)
                    measure("\(tag) local native responder",anchor:anchor,panelBefore:expanded)
                    _ = panel.makeFirstResponder(nil); localEditor.removeFromSuperview()
                    for cycle in 0..<3 {
                        assist.askText = String(repeating:"Fictional long question — ", count:80)
                        panel.contentView?.layoutSubtreeIfNeeded()
                        await pause()
                        measure("\(tag) long text \(cycle)", anchor:anchor, panelBefore:expanded)
                        _ = focusFixture.makeFirstResponder(otherEditor)
                        NotificationCenter.default.post(name:NSWindow.didResignKeyNotification,object:panel)
                        overlay.endTyping()
                        measure("\(tag) cancel and fixture responder \(cycle)",anchor:anchor,panelBefore:expanded)
                        let historyCount = session.history.count
                        overlay.startTyping(); assist.askText = "Fictional anchor check"; assist.submitAsk()
                        for _ in 0..<100 { await pause(10); if !session.isAnswering && session.history.count > historyCount { break } }
                        record("\(tag) asynchronous submission completed \(cycle)", !session.isAnswering && session.history.count > historyCount)
                        await pause(80)
                        measure("\(tag) submit and async answer \(cycle)",anchor:anchor,panelBefore:expanded)
                        let topic = Topic(id:"anchor-\(index)-\(cycle)",title:"Fictional topic",excerpt:[],createdAt:Date(),updatedAt:Date())
                        assist.answer(topic); await pause(100)
                        overlay.showAutomatic()
                        measure("\(tag) topic and automatic callback \(cycle)",anchor:anchor,panelBefore:expanded)
                    }
                    menu.toggle(PillMenuContent.menu(for:PillState()),anchor:overlay.pillFrame) { _ in }
                    await pause(); menu.close(restoringKeyboard:true)
                    measure("\(tag) menu open close",anchor:anchor,panelBefore:expanded)
                    mainWindow.show(); await pause(); mainWindow.close()
                    measure("\(tag) settings open close",anchor:anchor,panelBefore:expanded)
                    overlay.hide(); await pause(); WindowPrivacy.authorizeFromUserGesture(); overlay.present(); overlay.reveal()
                    measure("\(tag) hide reveal",anchor:anchor,panelBefore:expanded)
                    record("\(tag) no desktop windows or keys",!NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow })
                    overlay.flushPlacement()
                    let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
                    record("\(tag) persisted native anchor", settings.placement.pillFrame(size:anchor.size,on:ScreenArea(id:id,visibleFrame:area)) == anchor)
                }
            }
        }
        overlay.hide()
        record("fixture never activated", ownActivations == 0 && !NSApp.isActive)
        let result:[String:Any] = ["samples":samples,"trace":overlay.diagnosticGeometry,"spaceChangesObserved":spaceChanges,"windowsOrdered":false,
            "ownApplicationActivations":ownActivations,"spaceEventAttribution":"Global observations only; concurrent user Space activity is not attributed to the fixture",
            "desktopKeyboardTaken":false,"desktopEvents":false,"captures":false,"audio":false,
            "nativeWindowFrames":true,"productionControllers":true,"screen":NSStringFromRect(area),
            "limitations":"Headless: real NSWindow frame/child operations, local responder and async controller callbacks. No visible key-window transition, physical drag, full-screen Space or real display switch. Stealth sharing values exercised; activation stays accessory in fixture only."]
        try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("anchors.json"))
    }
}
