import AppKit
import CopiloteKit
import KeyboardShortcuts

/// Own-window native movement samples, not screen FPS or a physical mouse benchmark.
@MainActor
enum DiagnosticWorkspace {
    static func run(folder: URL, overlay: OverlayController, settings: SettingsStore) async {
        guard ProcessInfo.processInfo.arguments.contains("-RecetteWorkspace") else { return }
        let suite = "org.example.copilote.recette.workspace-notes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let notes = StickyNotesController(settings: SettingsStore(defaults: defaults, loadCredentials: false))
        defer { notes.closeAll(); defaults.removePersistentDomain(forName: suite) }
        var checks: [[String: Any]] = []
        func record(_ name: String, _ passed: Bool) { checks.append(["name": name, "passed": passed]) }
        func pause(_ ms: Int = 100) async { try? await Task.sleep(for: .milliseconds(ms)) }
        let numbers = overlay.windowNumbers
        guard let pill = NSApp.windows.first(where: { $0.windowNumber == numbers[0] }),
              let panel = NSApp.windows.first(where: { $0.windowNumber == numbers[1] }) else { return }
        record("launch opens expanded workspace without keyboard focus", overlay.model.isUnfolded && panel.isVisible && !panel.isKeyWindow)
        record("native child window attached to pill", panel.parent === pill)
        record("child titlebar cannot drag independently", !panel.isMovable && pill.isMovable)
        let startPill = pill.frame, startPanel = panel.frame
        let writes = overlay.placementWrites
        var durations: [Double] = [], maxError = 0.0
        // Move the actual parent window through a smooth closed trajectory. Child motion is
        // performed by AppKit, not by the diagnostic or a didMove follower.
        for step in 1...120 {
            let angle = Double(step) * 2 * .pi / 120
            let delta = CGPoint(x: sin(angle) * 100, y: (cos(angle) - 1) * 30)
            let before = ProcessInfo.processInfo.systemUptime
            pill.setFrameOrigin(CGPoint(x: startPill.minX + delta.x, y: startPill.minY + delta.y))
            durations.append((ProcessInfo.processInfo.systemUptime - before) * 1000)
            maxError = max(maxError, abs((panel.frame.minX - pill.frame.minX) - (startPanel.minX - startPill.minX)), abs((panel.frame.minY - pill.frame.minY) - (startPanel.minY - startPill.minY)))
            await pause(8)
        }
        record("120 native parent moves preserve child offset within one point", maxError <= 1)
        record("trajectory performs no preference writes", overlay.placementWrites == writes)
        overlay.landDraggedWorkspace()
        await pause(350)
        record("landing keeps entire workspace on screen", pill.screen?.visibleFrame.contains(pill.frame) == true && panel.screen?.visibleFrame.contains(panel.frame) == true)
        let mover = OverlayMovementShortcuts(overlay: overlay, register: false)
        defer { mover.stop() }
        mover.refresh(); record("movement enabled outside own text editors", mover.enabled)
        for direction in [OverlayPlacement.Direction.left, .right, .down, .up] {
            for _ in 0..<30 { mover.moveIfAllowed(direction) }
            record("repeated movement stays bounded \(direction)", pill.screen?.visibleFrame.contains(pill.frame) == true && panel.screen?.visibleFrame.contains(panel.frame) == true)
        }
        record("repeated movement leaves child attached", panel.parent === pill)
        overlay.startTyping(); await pause(250)
        mover.refresh()
        let beforeEditing = pill.frame
        record("Ask releases movement registration", !mover.enabled && OverlayMovementShortcuts.bindings.allSatisfy { !KeyboardShortcuts.isEnabled(for: $0.0) })
        if let editor = panel.firstResponder as? NSTextView {
            editor.insertText("alpha beta", replacementRange: NSRange(location: NSNotFound, length: 0))
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}", isARepeat: false, keyCode: 123) { panel.sendEvent(event) }
            record("native Command Left in Ask moves caret to start", editor.selectedRange().location == 0)
            mover.moveIfAllowed(.left)
            record("Ask retains focus and workspace stays still", panel.firstResponder === editor && pill.frame == beforeEditing)
        } else { record("Ask editor exists", false) }
        overlay.endTyping(); await pause()
        notes.add()
        let note = notes.notes.last!
        notes.setText("unchanged personal note", for: note.id)
        func editor(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.isEditable { return text }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        if let noteWindow = notes.windowForDiagnostic(note.id), let content = noteWindow.contentView, let text = editor(in: content) {
            let originalFrame = noteWindow.frame
            noteWindow.makeKey(); noteWindow.makeFirstResponder(text); await pause()
            mover.refresh(); let before = pill.frame
            mover.moveIfAllowed(.right)
            record("note editor releases movement and preserves focus", !mover.enabled && pill.frame == before && noteWindow.firstResponder === text)
            text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: noteWindow.windowNumber, context: nil, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}", isARepeat: false, keyCode: 123) { noteWindow.sendEvent(event) }
            record("native Command Left in post-it moves caret to start", text.selectedRange().location == 0)
            record("post-it text and position unchanged", notes.notes.last?.text == "unchanged personal note" && noteWindow.frame == originalFrame)
            noteWindow.orderOut(nil)
            await pause()
            record("movement registration resumes after note editor closes", mover.enabled)
        } else { record("note editor exists", false) }
        notes.delete(note.id)
        mover.refresh(); overlay.hide(); mover.refresh()
        record("hidden workspace releases movement shortcuts", !mover.enabled)
        AppDelegate.reopen(overlay: overlay); await pause(); mover.refresh()
        record("reopen expands and restores native attachment", panel.isVisible && overlay.model.isUnfolded && panel.parent === pill)
        DiagnosticSnapshot.write(to: folder.appendingPathComponent("workspace"), spaceChanges: 0)
        let sorted = durations.sorted()
        let report: [String: Any] = ["checks": checks, "nativeWindowSamples": durations.count,
            "setFrameOriginMillisecondsMedian": sorted[sorted.count / 2], "setFrameOriginMillisecondsMax": sorted.last ?? 0,
            "maximumChildOffsetErrorPoints": maxError, "physicalMouseDragMeasured": false, "displayFPSMeasured": false,
            "desktopEvents": false, "audioCapture": false, "scope": "Actual AppKit parent/child window movement and own-window keyboard dispatch; synthetic trajectory"]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: folder.appendingPathComponent("workspace.json")) }
    }
}
