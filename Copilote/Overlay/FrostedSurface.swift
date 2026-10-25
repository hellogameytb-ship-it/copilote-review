import AppKit

/// Separate background layers keep text and controls fully opaque in every appearance mode.
final class FrostedSurface: NSView {
    var density: Double = 0.82 { didSet { updateVeil() } }
    var backgroundMode: OverlayBackgroundMode = .system { didSet { updateVeil() } }
    var blendingMode: NSVisualEffectView.BlendingMode {
        get { blur.blendingMode }
        set { blur.blendingMode = newValue }
    }
    private let blur = NSVisualEffectView()
    private let veil = NSView()
    private var accessibilityObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.frame = bounds; blur.autoresizingMask = [.width, .height]
        addSubview(blur)
        veil.wantsLayer = true
        veil.frame = bounds; veil.autoresizingMask = [.width, .height]
        addSubview(veil)
        updateVeil()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.updateVeil() } }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func updateVeil(reduceTransparency: Bool? = nil) {
        let reduce = reduceTransparency ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let normalized = (min(max(density, 0.7), 1) - 0.7) / 0.3
        let alpha: Double
        switch backgroundMode {
        case .system:
            blur.isHidden = reduce
            alpha = reduce ? 1 : 0.15 + normalized * 0.30
        case .translucent:
            // An explicit app override: a translucent backing remains translucent even when
            // macOS replaces all native materials with opaque accessibility surfaces.
            blur.isHidden = true
            alpha = 0.62 + normalized * 0.26
        case .opaque:
            blur.isHidden = true
            alpha = 1
        }
        veil.layer?.backgroundColor = NSColor(srgbRed: 0.065, green: 0.065, blue: 0.085, alpha: alpha).cgColor
    }
    var veilAlpha: CGFloat { veil.layer?.backgroundColor?.alpha ?? 0 }

    deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }
}
