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
    var autoAnswer = true
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
    var onAutoAnswer: () -> Void = {}
    var onPrivacyHelp: () -> Void = {}
    var onUnfold: () -> Void = {}
    /// ⚙ (mode, main window, tour, quit: reachable in stealth mode too), with the button's frame in
    /// the pill's coordinates (top-left origin) so the drawn menu hangs under it.
    var onMenu: (CGRect) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            PillGrip().frame(width: 20, height: 24)
            separator
            Button(action: onListen) {
                HStack(spacing: 6) {
                    ListeningDot(isOn: state.isListening && !state.isPaused)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(listenLabel).font(.system(size: 12, weight: .semibold))
                        if let elapsed = state.elapsed {
                            Text(Self.clock(elapsed)).font(.system(size: 9, weight: .medium).monospacedDigit())
                        }
                    }
                }
            }
            .buttonStyle(PillButtonStyle())
            .overlayHint(listenHelp)
            .accessibilityLabel(state.isListening ? (state.isPaused ? "Listening paused. Resume" : "Listening on. Pause") : "Start session")

            if state.isListening {
                Button(action: onStop) {
                    Image(systemName: "stop.fill").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 25, height: 25).background(Color.red, in: Circle())
                }
                    .buttonStyle(.plain)
                    .overlayHint(Copy.Pill.stopHelp)
                    .accessibilityLabel(Copy.Pill.stop)
            }

            separator
            Toggle(state.autoAnswer ? "Auto ON" : "Auto OFF", isOn: Binding(get: { state.autoAnswer }, set: { _ in onAutoAnswer() }))
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11, weight: .medium))
            .overlayHint("Automatic answers for new subjects. Independent of listening and Stealth.")

            Button(action: onAsk) {
                HStack(spacing: 5) {
                    Label(Copy.Pill.ask, systemImage: "text.cursor").font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(PillButtonStyle())
            .overlayHint("\(Copy.Pill.askHelp) (\(state.labels.ask))")

            Spacer(minLength: 2)
            separator

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

            HStack(spacing: 5) {
                Button(action: onPrivacyHelp) { StealthStateLabel(isOn: state.isStealth) }
                    .buttonStyle(.plain)
                    .overlayHint(Copy.Settings.stealthHelp + " Click for details.")
                Button(state.isStealth ? "Turn off" : "Turn on", action: onStealth)
                    .font(.system(size: 10.5, weight: .medium))
                    .buttonStyle(PillButtonStyle(compact: true))
                    .accessibilityLabel(state.isStealth ? "Turn Stealth off" : "Turn Stealth on")
            }

            Button(action: onUnfold) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(state.isUnfolded ? 180 : 0))
            }
            .buttonStyle(PillButtonStyle(compact: true))
            .overlayHint(state.isUnfolded ? Copy.Pill.fold : "\(Copy.Pill.unfold) (\(state.labels.answerLatestTopic))")
            .accessibilityLabel(state.isUnfolded ? Copy.Pill.fold : Copy.Pill.unfold)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private var separator: some View { Rectangle().fill(Color.primary.opacity(0.16)).frame(width: 0.5, height: 20) }

    private var listenLabel: String {
        guard state.isListening else { return "Listen" }
        return state.isPaused ? "Paused" : "Listening"
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
            .fill(isOn ? Color.red : Color.primary.opacity(0.4))
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

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { NotificationCenter.default.post(name: Notification.Name("CopiloteWorkspaceDrag"), object: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.setFill()
            for row in 0..<2 {
                for column in 0..<3 {
                    let dot = NSRect(x: bounds.midX - 6 + CGFloat(column) * 5, y: bounds.midY - 3.5 + CGFloat(row) * 5, width: 2.5, height: 2.5)
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
            .padding(.horizontal, compact ? 4 : 6)
            .frame(height: 28)
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Color.primary)
            .background(
                prominent ? AnyShapeStyle(Color.blue.opacity(configuration.isPressed ? 0.28 : 0.18)) : AnyShapeStyle(Color.primary.opacity(configuration.isPressed ? 0.12 : 0)),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Reused by the capsule and settings: words and distinct icons carry the state without colour.
struct StealthStateLabel: View {
    let isOn: Bool
    var body: some View {
        Label(isOn ? "Stealth ON" : "Stealth OFF", systemImage: isOn ? "eye.slash.fill" : "eye")
            .font(.system(size: 11, weight: .medium))
            .accessibilityLabel(isOn ? "Stealth ON · protection requested" : "Stealth OFF · sharing allowed")
    }
}
