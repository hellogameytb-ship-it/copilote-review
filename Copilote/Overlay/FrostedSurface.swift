import AppKit

/// Separate background layers keep text and controls fully opaque in every appearance mode.
final class FrostedSurface: NSView {
    var density: Double = 0.68 { didSet { updateVeil() } }
    var isCapsule = false { didSet { updateVeil() } }
    var backgroundMode: OverlayBackgroundMode = .system { didSet { updateVeil() } }
    var blendingMode: NSVisualEffectView.BlendingMode {
        get { blur.blendingMode }
        set { blur.blendingMode = newValue }
    }
    private let blur = NSVisualEffectView()
    private let veil = NSView()
    private let sheen = CAGradientLayer()
    private var accessibilityObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.frame = bounds; blur.autoresizingMask = [.width, .height]
        addSubview(blur)
        veil.wantsLayer = true
        veil.frame = bounds; veil.autoresizingMask = [.width, .height]
        addSubview(veil)
        sheen.colors = [NSColor.white.withAlphaComponent(0.025).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        sheen.startPoint = CGPoint(x: 0.3, y: 1); sheen.endPoint = CGPoint(x: 0.7, y: 0)
        veil.layer?.addSublayer(sheen)
        updateVeil()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.updateVeil() } }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func updateVeil(reduceTransparency: Bool? = nil) {
        let reduce = reduceTransparency ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let clamped = min(max(density, 0.45), 1)
        let normalized = (clamped - 0.45) / 0.55
        let alpha: Double
        switch backgroundMode {
        case .system:
            blur.isHidden = reduce
            alpha = reduce ? 1 : 0.15 + normalized * 0.30
        case .translucent:
            blur.isHidden = reduce
            // When macOS disables native blur, use the familiar dark surface instead of a
            // white/grey imitation of glass. Only the backing changes; foreground stays opaque.
            alpha = reduce ? (isCapsule ? 0.72 + normalized * 0.28 : 0.65 + normalized * 0.35)
                : (isCapsule ? 0.06 + normalized * 0.12 : 0.10 + normalized * 0.30)
        case .opaque:
            blur.isHidden = true
            alpha = 1
        }
        let lightGlass = isCapsule && !reduce && backgroundMode != .opaque
        if isCapsule { appearance = NSAppearance(named: lightGlass ? .aqua : .darkAqua) }
        let tint: CGFloat = lightGlass ? 0.96 : 0.065
        veil.layer?.backgroundColor = NSColor(srgbRed: tint, green: tint, blue: tint + (isCapsule ? 0 : 0.015), alpha: alpha).cgColor
    }
    override func layout() { super.layout(); sheen.frame = bounds }
    var veilAlpha: CGFloat { veil.layer?.backgroundColor?.alpha ?? 0 }

    deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }
}
