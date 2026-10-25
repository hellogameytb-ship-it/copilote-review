import AppKit
import ScreenCaptureKit
import SwiftUI

/// Own-window visual fixture: generated backdrops, native material, and the real web renderer.
/// Never captures the desktop or changes a production window's sharing flag.
@MainActor
enum DiagnosticGlass {
    static func run(folder: URL, record: (String, Bool) -> Void) async {
        let captureRequested = ProcessInfo.processInfo.arguments.contains("-RecetteProtectedCapture")
        guard !captureRequested || ScreenCapturer.hasPermission else { record("controlled glass previews need existing screen permission", false); return }
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
        let window = NSPanel(contentRect: CGRect(x: screen.minX + 30, y: screen.maxY - 550, width: 720, height: 520), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        window.sharingType = .none
        window.level = .floating; window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let backdrop = Backdrop(frame: CGRect(x: 0, y: 0, width: 720, height: 520))
        window.contentView = backdrop
        let surface = FrostedSurface()
        surface.backgroundMode = .translucent
        // The controlled backdrop is within this fixture window; production uses behindWindow.
        surface.blendingMode = .withinWindow
        surface.frame = CGRect(x: 30, y: 20, width: 660, height: 420)
        surface.appearance = NSAppearance(named: .darkAqua)
        backdrop.addSubview(surface)
        let label = NSTextField(labelWithString: "Translucent background · Opaque text")
        label.frame = CGRect(x: 16, y: 378, width: 620, height: 24)
        label.font = .systemFont(ofSize: 14, weight: .semibold); label.textColor = .white
        surface.addSubview(label)
        let web = ResponseWebView()
        web.frame = CGRect(x: 10, y: 10, width: 640, height: 358)
        surface.addSubview(web)
        let capsule = FrostedSurface(); capsule.isCapsule = true; capsule.backgroundMode = .translucent
        capsule.layer?.cornerRadius = PillPanel.size.height / 2
        capsule.frame = CGRect(x: (720 - PillPanel.size.width) / 2, y: 460, width: PillPanel.size.width, height: PillPanel.size.height)
        let controls = FirstMouseHostingView(rootView: PillView(state: PillState(isUnfolded: true)))
        controls.frame = capsule.bounds; controls.autoresizingMask = [.width, .height]
        capsule.addSubview(controls); backdrop.addSubview(capsule)
        window.orderFrontRegardless()
        web.render(payloadJSON: ###"{"answerId":1,"segments":[{"kind":"markdown","text":"## Ready to say\nI built Orion with Swift and SQLite. The offline workflow keeps the app usable without a connection.\n\n## Key points\n- Clear, opaque text over a translucent background\n- Background density stays independent of text\n- No measured speedup is claimed"}]}"###)
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(700))
        let rendererReady = try? await web.evaluateJavaScript("typeof window.copilote") as? String
        record("public WebKit renderer loads bundled scripts", rendererReady == "object")
        var observations: [[String: Any]] = []
        for (name, style, density) in [("light", 0, 0.68), ("dark", 1, 0.68), ("busy", 2, 0.68)] {
            controls.rootView = PillView(state: PillState(isListening: style != 0, isPaused: style == 2, elapsed: style == 0 ? nil : 73, isUnfolded: true, isStealth: style != 1, autoAnswer: style != 1))
            backdrop.style = style; backdrop.needsDisplay = true; surface.density = density
            try? await Task.sleep(for: .milliseconds(550))
            if let bitmap = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) {
                backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
                let png = bitmap.representation(using: .png, properties: [:])
                try? png?.write(to: folder.appendingPathComponent("glass-\(name).png"))
                record("glass \(name) internal rendering of protected fixture", png != nil && label.alphaValue == 1 && web.alphaValue == 1)
            } else { record("glass \(name) internal rendering available", false) }
            if !captureRequested { continue }
            do {
                let shareable = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let own = shareable.windows.first(where: { Int($0.windowID) == window.windowNumber && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }) else { record("glass \(name) own window available", false); continue }
                let filter = SCContentFilter(desktopIndependentWindow: own)
                let configuration = SCStreamConfiguration()
                configuration.width = 860; configuration.height = 800; configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                let bitmap = NSBitmapImageRep(cgImage: image)
                let visible = stride(from: 0, to: bitmap.pixelsHigh, by: 20).contains { y in
                    stride(from: 0, to: bitmap.pixelsWide, by: 20).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
                }
                observations.append(["background": name, "sharingNone": window.sharingType == .none, "capturedPixelsVisible": visible,
                    "scope": "ScreenCaptureKit desktopIndependentWindow targeting own generated fixture only; not a receiver test"])
                if name == "busy", let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: folder.appendingPathComponent("protected-sck-fixture.png")) }
            } catch { record("glass \(name) preview failed: \(error.localizedDescription)", false) }
        }
        surface.backgroundMode = .translucent
        surface.density = 0.45; surface.updateVeil(reduceTransparency: true)
        let low = surface.veilAlpha
        surface.density = 1; surface.updateVeil(reduceTransparency: true)
        record("app density remains adjustable with Reduce Transparency on", low < surface.veilAlpha && surface.veilAlpha == 1 && web.alphaValue == 1 && controls.alphaValue == 1)
        web.render(payloadJSON: ###"{"answerId":2,"copy":"renderer fixture","segments":[{"kind":"markdown","text":"Math $x^2$\n\n```swift\nlet value = 42\n```\n<script>forbidden()</script>"},{"kind":"mermaid","source":"graph LR; A-->B","complete":true}]}"###)
        try? await Task.sleep(for: .milliseconds(1800))
        let contentOK = try? await web.evaluateJavaScript("!!document.querySelector('.katex') && !!document.querySelector('.hljs .hljs-keyword') && !!document.querySelector('.diagram svg') && !document.querySelector('#answer script')") as? Bool
        record("public renderer math code diagram and escaped HTML", contentOK == true)
        var copied: String?
        web.onCopy = { copied = $0 }
        _ = try? await web.evaluateJavaScript("document.querySelector('.code .copy').click()")
        try? await Task.sleep(for: .milliseconds(100))
        record("public renderer native copy bridge", copied?.contains("let value = 42") == true)
        web.pageZoom = 1.2
        try? await Task.sleep(for: .milliseconds(100))
        let zoom = try? await web.evaluateJavaScript("document.documentElement.style.zoom") as? String
        record("public renderer text zoom", zoom == "1.2")
        web.recover()
        try? await Task.sleep(for: .milliseconds(1500))
        let recovered = try? await web.evaluateJavaScript("!!document.querySelector('.katex') && document.documentElement.style.zoom === '1.2'") as? Bool
        record("public renderer restores answer and zoom after reload", recovered == true)
        record("renderer navigation restricts to bundled document", ResponseWebView.allows(ResponseWebView.bundledPage) && !ResponseWebView.allows(URL(string: "https://example.com")) && !ResponseWebView.allows(URL(fileURLWithPath: "/etc/hosts")))
        if let data = try? JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: folder.appendingPathComponent("protected-capture-observations.json")) }
    }
    private final class Backdrop: NSView {
        var style = 0
        override func draw(_ dirtyRect: NSRect) {
            (style == 1 ? NSColor.black : NSColor.white).setFill(); bounds.fill()
            if style == 2 {
                for row in 0..<14 { for column in 0..<18 {
                    NSColor(calibratedHue: CGFloat((row + column) % 8) / 8, saturation: 0.8, brightness: 0.95, alpha: 1).setFill()
                    NSRect(x: column * 43, y: row * 40, width: 43, height: 40).fill()
                } }
            }
        }
    }
}
