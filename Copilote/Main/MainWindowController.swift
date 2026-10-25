import AppKit
import CopiloteKit
import SwiftUI

/// Settings are another non-activating protected panel, never a normal application window.
@MainActor
final class MainWindowController {
    private let window: OverlayPanel
    var windowNumber: Int { window.windowNumber }

    init(rootView: MainView, autosave: Bool = true) {
        window = OverlayPanel(size: NSSize(width: 1000, height: 700))
        window.title = "Copilote Settings"
        window.allowsKey = true
        window.minSize = NSSize(width: 1000, height: 640)
        let panel = window
        let content = VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Close") { panel.orderOut(nil) }.buttonStyle(.plain)
            }.padding(14)
            Divider()
            rootView
        }
        window.contentView = OverlayController.surface(hosting: FirstMouseHostingView(rootView: content), cornerRadius: 14)
        if autosave {
            window.setFrameAutosaveName("CopiloteMainWindow")
            if !window.setFrameUsingName("CopiloteMainWindow") { window.center() }
        } else { window.center() }
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            window.setFrame(StickyNote.fitted(window.frame, screens: [screen.visibleFrame]), display: false)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() { window.orderOut(nil) }
}
