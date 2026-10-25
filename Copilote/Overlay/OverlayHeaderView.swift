import AppKit

/// Header strip of the overlay: phase, status line, capture counter. It is also the drag handle.
final class OverlayHeaderView: NSView {
    enum Tone {
        case idle, working, streaming, failed

        var color: NSColor {
            switch self {
            case .idle: return NSColor.white.withAlphaComponent(0.3)
            case .working: return .systemYellow
            case .streaming: return .systemGreen
            case .failed: return .systemRed
            }
        }
    }

    private let dot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let counterLabel = NSTextField(labelWithString: "")
    private let clickThroughIcon = NSImageView()
    private let listeningBadge = NSTextField(labelWithString: "● Session")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 7), dot.heightAnchor.constraint(equalToConstant: 7)])

        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        counterLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        counterLabel.textColor = .secondaryLabelColor
        counterLabel.alignment = .right

        clickThroughIcon.image = NSImage(systemSymbolName: "cursorarrow.slash", accessibilityDescription: "Click through")
        clickThroughIcon.contentTintColor = .secondaryLabelColor
        clickThroughIcon.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        clickThroughIcon.isHidden = true

        // Steady, never pulsing: present without pulling the eye.
        listeningBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        listeningBadge.textColor = NSColor.systemRed.withAlphaComponent(0.85)
        listeningBadge.isHidden = true
        listeningBadge.setAccessibilityLabel("Session active")

        let stack = NSStackView(views: [dot, statusLabel, NSView(), listeningBadge, clickThroughIcon, counterLabel])
        stack.orientation = .horizontal
        stack.spacing = 7
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setTone(.idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        (window as? OverlayPanel)?.performWorkspaceDrag(with: event)
    }

    func setStatus(_ text: String, tone: Tone) {
        statusLabel.stringValue = text
        setTone(tone)
    }

    func setCounter(_ text: String) {
        counterLabel.stringValue = text
    }

    func setListening(_ isListening: Bool) {
        listeningBadge.isHidden = !isListening
    }

    func setClickThrough(_ enabled: Bool) {
        clickThroughIcon.isHidden = !enabled
    }

    private func setTone(_ tone: Tone) {
        dot.layer?.backgroundColor = tone.color.cgColor
    }
}
