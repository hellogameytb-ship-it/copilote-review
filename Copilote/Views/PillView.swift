import CopiloteKit
import SwiftUI

/// What the pill shows. Data only: the app and copilote-render both fill it.
struct PillState: Equatable {
    var isListening = false
    var isPaused = false
    /// Since listening started.
    var elapsed: TimeInterval?
    var mode: MeetingMode = .meeting
    /// "Codex", "Claude", or nil when no provider is ready.
    var provider: String?
    var providerDetail = ""
    var isUnfolded = false
    var isStealth = true
    var labels = ShortcutLabels()
}

/// The compact bar at the top of the screen, à la Cluely: the logo (the grip), listen, ask with its
/// shortcut, ⚙ (mode, provider, settings), Furtif, unfold. A heavier material than the panel;
/// controls press at once.
struct PillView: View {
    let state: PillState
    /// Start session, Pause or Reprendre.
    var onListen: () -> Void = {}
    var onStop: () -> Void = {}
    var onAsk: () -> Void = {}
    /// Mode furtif on / off (not hiding the overlay: ⌥⌘O does that).
    var onStealth: () -> Void = {}
    var onUnfold: () -> Void = {}
    /// ⚙ (mode, main window, tour, quit: reachable in stealth mode too), with the button's frame in
    /// the pill's coordinates (top-left origin) so the drawn menu hangs under it.
    var onMenu: (CGRect) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 6) {
            PillGrip().frame(width: 20, height: 24)
            Button(action: onListen) {
                HStack(spacing: 6) {
                    ListeningDot(isOn: state.isListening && !state.isPaused)
                    Text(listenLabel).font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(PillButtonStyle(prominent: !state.isListening || state.isPaused))
            .overlayHint(listenHelp)

            if state.isListening {
                Button(action: onStop) { Image(systemName: "stop.fill").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(PillButtonStyle(compact: true))
                    .overlayHint(Copy.Pill.stopHelp)
                    .accessibilityLabel(Copy.Pill.stop)
            }

            if let elapsed = state.elapsed {
                Text(Self.clock(elapsed))
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Listening for \(Self.clock(elapsed))")
            }

            Button(action: onAsk) {
                HStack(spacing: 5) {
                    Label(Copy.Pill.ask, systemImage: "text.cursor").font(.system(size: 12, weight: .medium))
                    // Its shortcut, while there is room (listening adds stop and the timer).
                    if !state.isListening {
                        Text(state.labels.ask).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(PillButtonStyle())
            .overlayHint("\(Copy.Pill.askHelp) (\(state.labels.ask))")

            Spacer(minLength: 2)

            // The provider and the mode sit in this menu (`PillMenuContent`): nothing to read in the
            // pill during a call. Drawn by Copilote, not an NSMenu (a system window, seen in shares).
            GeometryReader { proxy in
                Button { onMenu(proxy.frame(in: .global)) } label: {
                    Image(systemName: "gearshape").font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(PillButtonStyle(compact: true))
                .overlayHint(Copy.Pill.more)
                .accessibilityLabel(Copy.Pill.more)
            }
            .frame(width: 28, height: 28)

            // The eye is the stealth mode: out of the Dock and ⌘Tab, the overlay still there for the
            // user. Struck through and in the accent while it is on.
            Button(action: onStealth) {
                HStack(spacing: 4) {
                    Image(systemName: state.isStealth ? "eye.slash" : "eye").font(.system(size: 11, weight: .medium))
                    Text(Copy.Pill.stealth).font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(state.isStealth ? AnyShapeStyle(FicheStyle.accent) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(PillButtonStyle(compact: true))
            .overlayHint(Copy.Pill.stealthHint(state.labels.toggleMode, hide: state.labels.toggleOverlay))
            .accessibilityLabel(Copy.Pill.stealth)
            .accessibilityValue(state.isStealth ? Copy.Pill.stealthOn : Copy.Pill.stealthOff)

            Button(action: onUnfold) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(state.isUnfolded ? 180 : 0))
            }
            .buttonStyle(PillButtonStyle(compact: true))
            .overlayHint(state.isUnfolded ? Copy.Pill.fold : "\(Copy.Pill.unfold) (\(state.labels.answerLatestTopic))")
            .accessibilityLabel(state.isUnfolded ? Copy.Pill.fold : Copy.Pill.unfold)
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
    }

    private var listenLabel: String {
        guard state.isListening else { return Copy.Pill.listen }
        return state.isPaused ? Copy.Pill.resume : Copy.Pill.pause
    }

    private var listenHelp: String {
        guard state.isListening else { return Copy.Pill.listenHelp }
        return state.isPaused ? Copy.Pill.resumeHelp : Copy.Pill.pauseHelp
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct ListeningDot: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? Color.red : Color.white.opacity(0.35))
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(Color.white.opacity(isOn ? 0.25 : 0), lineWidth: 2).scaleEffect(1.8))
    }
}

/// The pill's grip, à la Cluely: Copilote's logo, the only place that moves it (the panel follows).
private struct PillGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = GripView()
        view.setAccessibilityLabel(Copy.Pill.drag)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class GripView: NSView {
        override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 24) }

        /// The menu bar mark, in the secondary label colour; dots if it is missing (renders).
        private static let logo: NSImage? = NSImage(named: "MenuBarIcon").map { template in
            NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                template.draw(in: rect)
                NSColor.secondaryLabelColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { NotificationCenter.default.post(name: Notification.Name("CopiloteWorkspaceDrag"), object: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func draw(_ dirtyRect: NSRect) {
            if let logo = Self.logo {
                return logo.draw(in: NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16))
            }
            NSColor.secondaryLabelColor.setFill()
            for row in 0..<3 {
                for column in 0..<2 {
                    let dot = NSRect(x: bounds.midX - 3.5 + CGFloat(column) * 5, y: bounds.midY - 6 + CGFloat(row) * 5, width: 2, height: 2)
                    NSBezierPath(ovalIn: dot).fill()
                }
            }
        }
    }
}

/// Lighter than the pill's material: the controls are what you act on. Feedback on press.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, compact ? 7 : 10)
            .frame(height: 28)
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Color.primary)
            .background(
                prominent ? AnyShapeStyle(FicheStyle.accent.opacity(configuration.isPressed ? 0.75 : 1)) : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08)),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}
