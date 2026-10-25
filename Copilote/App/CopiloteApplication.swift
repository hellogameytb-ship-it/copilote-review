import AppKit

/// Only events/actions dispatched to this app's protected windows are filtered.
/// A Globe action handled by macOS before delivery to the app is outside this boundary.
@objc(CopiloteApplication)
final class CopiloteApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if CharacterPaletteGuard.consume(event, window: event.window ?? keyWindow) { return }
        super.sendEvent(event)
    }
    override func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        if action == #selector(NSApplication.orderFrontCharacterPalette(_:)), keyWindow is ProtectedPanel {
            CharacterPaletteGuard.recordAction(); return true
        }
        return super.sendAction(action, to: target, from: sender)
    }
    override func orderFrontCharacterPalette(_ sender: Any?) {
        guard !(keyWindow is ProtectedPanel) else { CharacterPaletteGuard.recordAction(); return }
        super.orderFrontCharacterPalette(sender)
    }
}

@MainActor
enum CharacterPaletteGuard {
    static private(set) var diagnosticBlockedEvents = 0
    static private(set) var diagnosticBlockedActions = 0
    static func shouldSuppress(_ event: NSEvent, window: NSWindow?) -> Bool {
        guard window is ProtectedPanel, [.keyDown, .keyUp, .flagsChanged].contains(event.type) else { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 49 && flags == [.command, .control] { return true }
        return event.keyCode == 63 && flags.isEmpty
    }
    static func consume(_ event: NSEvent, window: NSWindow?) -> Bool {
        guard shouldSuppress(event, window: window) else { return false }
        if DiagnosticRecette.isRequested { diagnosticBlockedEvents += 1 }
        return true
    }
    static func recordAction() { if DiagnosticRecette.isRequested { diagnosticBlockedActions += 1 } }
}
