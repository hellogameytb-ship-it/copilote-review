import AppKit
import CopiloteKit
import KeyboardShortcuts

/// ⌘⇧A: freezes the screen, lets the user drag a rectangle, returns the cropped pixels.
/// The selection panel never becomes key, so the frontmost app keeps its focus;
/// Escape is caught as a temporary global shortcut instead.
@MainActor
final class RegionSelector {
    private var panel: SelectionPanel?
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var escapeTask: Task<Void, Never>?

    var isSelecting: Bool { panel != nil }

    func select(from image: CGImage, on screen: NSScreen) async -> CGImage? {
        finish(with: nil)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let view = SelectionView(image: image) { [weak self] pixelRect in
                self?.finish(with: pixelRect.flatMap { image.cropping(to: $0) })
            }
            let panel = SelectionPanel(screen: screen, contentView: view)
            self.panel = panel
            panel.orderFrontRegardless()
            NSCursor.crosshair.push()
            escapeTask = Task { [weak self] in
                for await event in KeyboardShortcuts.events(for: .init(.escape)) where event == .keyDown {
                    self?.finish(with: nil)
                }
            }
        }
    }

    private func finish(with image: CGImage?) {
        escapeTask?.cancel()
        escapeTask = nil
        if panel != nil { NSCursor.pop() }
        panel?.orderOut(nil)
        panel = nil
        continuation?.resume(returning: image)
        continuation = nil
    }
}

private final class SelectionPanel: NSPanel {
    init(screen: NSScreen, contentView: NSView) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .none
        isOpaque = true
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        self.contentView = contentView
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SelectionView: NSView {
    private let image: CGImage
    /// Called with the selection in image pixels, or nil when cancelled.
    private let onFinish: (CGRect?) -> Void
    private var start: NSPoint?
    private var current: NSPoint?

    init(image: CGImage, onFinish: @escaping (CGRect?) -> Void) {
        self.image = image
        self.onFinish = onFinish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .cursorUpdate, .inVisibleRect], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        // A click without a drag cancels, like the system screenshot tool.
        guard let rect = selection, rect.width >= 6, rect.height >= 6 else { return onFinish(nil) }
        onFinish(CaptureGeometry.pixelRect(for: rect, viewSize: bounds.size, imageWidth: image.width))
    }

    override func rightMouseDown(with event: NSEvent) { onFinish(nil) }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(image, in: bounds)
        NSColor.black.withAlphaComponent(0.38).setFill()
        guard let rect = selection else {
            bounds.fill()
            return
        }
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: rect).reversed)
        dim.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        let scale = CaptureGeometry.scale(viewWidth: bounds.width, imageWidth: image.width)
        let label = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attributes)
        let origin = NSPoint(x: rect.minX, y: max(rect.minY - size.height - 8, 4))
        let badge = NSRect(origin: origin, size: NSSize(width: size.width + 10, height: size.height + 4))
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: badge.minX + 5, y: badge.minY + 2), withAttributes: attributes)
    }
}
