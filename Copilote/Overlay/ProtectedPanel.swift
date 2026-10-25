import AppKit

/// Every production app-owned surface, including file browsing, uses this gate.
/// Reading sharingType confirms only local policy, never what a receiver captures.
class ProtectedPanel: NSPanel {
    override func sendEvent(_ event: NSEvent) {
        if CharacterPaletteGuard.consume(event, window: self) { return }
        super.sendEvent(event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if CharacterPaletteGuard.consume(event, window: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
    @objc func orderFrontCharacterPalette(_ sender: Any?) { CharacterPaletteGuard.recordAction() }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        guard place == .out || WindowPrivacy.canPresent(self) else { return }
        super.order(place, relativeTo: otherWin)
    }
    override func orderFront(_ sender: Any?) {
        guard WindowPrivacy.canPresent(self) else { return }
        super.orderFront(sender)
    }
    override func orderFrontRegardless() {
        guard WindowPrivacy.canPresent(self) else { return }
        super.orderFrontRegardless()
    }
    override func makeKeyAndOrderFront(_ sender: Any?) {
        guard WindowPrivacy.canPresent(self) else { return }
        super.makeKeyAndOrderFront(sender)
    }
    override func makeKey() {
        guard isVisible, WindowPrivacy.canPresent(self) else { return }
        super.makeKey()
    }
    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        guard WindowPrivacy.canPresent(self), WindowPrivacy.canPresent(childWin) else { return }
        super.addChildWindow(childWin, ordered: place)
    }
}
