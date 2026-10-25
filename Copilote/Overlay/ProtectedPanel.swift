import AppKit

/// Every production app-owned surface, including file browsing, uses this gate.
/// Reading sharingType confirms only local policy, never what a receiver captures.
class ProtectedPanel: NSPanel {
    override func sendEvent(_ event: NSEvent) {
        if StealthConfirmationController.consumeEscape(event, in: self) { return }
        if CharacterPaletteGuard.consume(event, window: self) { return }
        super.sendEvent(event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if StealthConfirmationController.consumeEscape(event, in: self) { return true }
        if CharacterPaletteGuard.consume(event, window: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
    @objc func orderFrontCharacterPalette(_ sender: Any?) { CharacterPaletteGuard.recordAction() }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        if place == .out { StealthConfirmationController.invalidate(for:self) }
        if DiagnosticAnchorFixture.isRequested && place != .out { return }
        guard place == .out || WindowPrivacy.canPresent(self) else { return }
        super.order(place, relativeTo: otherWin)
    }
    override func orderFront(_ sender: Any?) {
        if DiagnosticAnchorFixture.isRequested { return }
        guard WindowPrivacy.canPresent(self) else { return }
        super.orderFront(sender)
    }
    override func orderOut(_ sender: Any?) {
        StealthConfirmationController.invalidate(for:self)
        super.orderOut(sender)
    }
    override func orderFrontRegardless() {
        if DiagnosticAnchorFixture.isRequested { return }
        guard WindowPrivacy.canPresent(self) else { return }
        super.orderFrontRegardless()
    }
    override func makeKeyAndOrderFront(_ sender: Any?) {
        if DiagnosticAnchorFixture.isRequested { return }
        guard WindowPrivacy.canPresent(self) else { return }
        super.makeKeyAndOrderFront(sender)
    }
    override func makeKey() {
        if DiagnosticAnchorFixture.isRequested { return }
        guard isVisible, WindowPrivacy.canPresent(self) else { return }
        super.makeKey()
    }
    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        if DiagnosticAnchorFixture.isRequested { alphaValue = 0; childWin.alphaValue = 0; childWin.ignoresMouseEvents = true }
        guard WindowPrivacy.canPresent(self), WindowPrivacy.canPresent(childWin) else { return }
        super.addChildWindow(childWin, ordered: place)
    }
}
