import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    private let window: NSWindow

    init(rootView: MainView, autosave: Bool = true) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Copilote"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        // Finder may activate a regular app before delivering reopen. A settings window that
        // belongs to one old Space can then pull the desktop away before show() runs.
        // Like the overlay, keep this window available on the current Space while it is open.
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        window.level = .floating
        window.contentView = NSHostingView(rootView: rootView)
        if autosave {
            window.setFrameAutosaveName("CopiloteMainWindow")
            if !window.setFrameUsingName("CopiloteMainWindow") { window.center() }
        } else { window.center() }
    }

    func show() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        // Activation can be refused when another app is frontmost: still put the window up.
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }
}
