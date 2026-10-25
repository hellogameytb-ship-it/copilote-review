import AppKit
import ScreenCaptureKit

/// Own-window visual fixture: generated backdrops, native material, and the real web renderer.
/// Never captures the desktop or changes a production window's sharing flag.
@MainActor
enum DiagnosticGlass {
    static func run(folder: URL, record: (String, Bool) -> Void) async {
        guard ScreenCapturer.hasPermission else { record("controlled glass previews need existing screen permission", false); return }
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
        let window = NSPanel(contentRect: CGRect(x: screen.minX + 30, y: screen.maxY - 440, width: 430, height: 400), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        window.level = .floating; window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let backdrop = Backdrop(frame: CGRect(x: 0, y: 0, width: 430, height: 400))
        window.contentView = backdrop
        let surface = FrostedSurface()
        surface.backgroundMode = .translucent
        // The controlled backdrop is within this fixture window; production uses behindWindow.
        surface.blendingMode = .withinWindow
        surface.frame = CGRect(x: 20, y: 20, width: 390, height: 360)
        surface.appearance = NSAppearance(named: .darkAqua)
        backdrop.addSubview(surface)
        let label = NSTextField(labelWithString: "Translucent background · Opaque text")
        label.frame = CGRect(x: 16, y: 318, width: 360, height: 24)
        label.font = .systemFont(ofSize: 14, weight: .semibold); label.textColor = .white
        surface.addSubview(label)
        let web = ResponseWebView()
        web.frame = CGRect(x: 10, y: 10, width: 370, height: 298)
        surface.addSubview(web)
        window.orderFrontRegardless()
        web.render(payloadJSON: ###"{"answerId":1,"segments":[{"kind":"markdown","text":"## Ready to say\nI built Orion with Swift and SQLite. The offline workflow keeps the app usable without a connection.\n\n## Key points\n- Clear, opaque text over a translucent background\n- Background density stays independent of text\n- No measured speedup is claimed"}]}"###)
        defer { window.orderOut(nil) }
        for (name, style, density) in [("light", 0, 0.7), ("dark", 1, 0.82), ("busy", 2, 0.7)] {
            backdrop.style = style; backdrop.needsDisplay = true; surface.density = density
            try? await Task.sleep(for: .milliseconds(550))
            do {
                let shareable = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let own = shareable.windows.first(where: { Int($0.windowID) == window.windowNumber && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }) else { record("glass \(name) own window available", false); continue }
                let filter = SCContentFilter(desktopIndependentWindow: own)
                let configuration = SCStreamConfiguration()
                configuration.width = 860; configuration.height = 800; configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                try png?.write(to: folder.appendingPathComponent("glass-\(name).png"))
                record("glass \(name) captured only generated fixture window", png != nil && label.alphaValue == 1 && web.alphaValue == 1)
            } catch { record("glass \(name) preview failed: \(error.localizedDescription)", false) }
        }
    }
    private final class Backdrop: NSView {
        var style = 0
        override func draw(_ dirtyRect: NSRect) {
            (style == 1 ? NSColor.black : NSColor.white).setFill(); bounds.fill()
            if style == 2 {
                for row in 0..<10 { for column in 0..<11 {
                    NSColor(calibratedHue: CGFloat((row + column) % 8) / 8, saturation: 0.8, brightness: 0.95, alpha: 1).setFill()
                    NSRect(x: column * 43, y: row * 40, width: 43, height: 40).fill()
                } }
            }
        }
    }
}
