import SwiftUI

/// Non-interactive bounds marker for own-window input diagnostics; never an extra control.
struct InlineControlBounds: NSViewRepresentable {
    let id: String
    var action: (() -> Void)? = nil
    func makeNSView(context:Context) -> NSView {
        let view = InlineControlMarker(); updateNSView(view,context:context); return view
    }
    func updateNSView(_ view:NSView, context:Context) {
        view.identifier = NSUserInterfaceItemIdentifier(id)
        (view as? InlineControlMarker)?.action = action
    }
}

/// A headless test can exercise the exact action bound by the view without desktop input.
/// This does not simulate a physical click or prove visible native hit testing.
final class InlineControlMarker: NSView {
    fileprivate var action: (() -> Void)?
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    func invokeHeadlessAction() -> Bool {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("-CopiloteRecette"),process.arguments.contains("-RecetteAnchorOnly"),
              process.environment["COPILOTE_HEADLESS_GEOMETRY"] == "1",
              window?.isVisible == false, let action else { return false }
        action(); return true
    }
}
