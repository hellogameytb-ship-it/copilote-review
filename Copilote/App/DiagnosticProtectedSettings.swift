import AppKit
import KeyboardShortcuts

@MainActor
enum DiagnosticProtectedSettings {
    static func run(folder: URL, record: (String, Bool) -> Void) async {
        guard let panel = NSApp.windows.first(where: { $0.title == "Copilote Settings" }) as? OverlayPanel,
              let content = panel.contentView else { record("protected settings panel found", false); return }
        func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
        let views = allViews(content)
        if let editor = views.compactMap({ $0 as? NSTextView }).first(where: { $0.isEditable }) {
            panel.makeKey(); _ = panel.makeFirstResponder(editor)
            editor.insertText("Fixture instructions only", replacementRange: NSRange(location: NSNotFound, length: 0))
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
            record("settings editor accepts native Command A without a main menu", panel.performKeyEquivalent(with: event) && editor.selectedRange().length == editor.string.utf16.count)
            record("settings editing preserves accessory policy and protected window", NSApp.activationPolicy() == .accessory && panel.sharingType == .none && panel.isKeyWindow)
        } else { record("native settings editor available", false) }

        // A real recorder control, using a throwaway binding only. No user shortcut is changed.
        let name = KeyboardShortcuts.Name("CopiloteRecipe-\(UUID().uuidString)")
        let button = ShortcutCaptureButton(); button.name = name
        content.addSubview(button); button.frame = NSRect(x: 8, y: 8, width: 180, height: 28)
        var message = ""
        button.onChange = { message = $0 }
        button.begin()
        let before = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: "m", charactersIgnoringModifiers: "m", isARepeat: false, keyCode: code)!
        }
        button.keyDown(with: key(46, []))
        record("invalid shortcut reports inline without a system alert", !message.isEmpty && button.recording && before == Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber)))
        let candidate = (0..<50).map { key(UInt16($0), [.command, .control, .option, .shift]) }.first {
            guard let shortcut = KeyboardShortcuts.Shortcut(event: $0) else { return false }
            return !shortcut.isTakenBySystem && !ShortcutCatalog.all.contains { KeyboardShortcuts.getShortcut(for: $0.name) == shortcut }
        }
        if let candidate {
            button.keyDown(with: candidate)
            record("protected recorder saves a custom shortcut", !button.recording && KeyboardShortcuts.getShortcut(for: name) == KeyboardShortcuts.Shortcut(event: candidate))
        } else { record("available test shortcut found", false) }
        button.finish(); button.removeFromSuperview()
        KeyboardShortcuts.setShortcut(nil, for: name)
        UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_" + name.rawValue)
        _ = panel.makeFirstResponder(nil)
        record("all visible app surfaces request sharing exclusion", NSApp.windows.filter(\.isVisible).allSatisfy { $0.sharingType == .none })
        record("no macOS app menu is installed", NSApp.mainMenu == nil)
    }
}
