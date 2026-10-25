import CopiloteKit
import SwiftUI

/// The pill, fed by the app's state; its timer ticks once a second while listening.
struct PillHost: View {
    @ObservedObject var listening: ListeningController
    @ObservedObject var assist: AssistController
    @ObservedObject var providers: ProviderController
    @ObservedObject var overlay: OverlayModel
    let onAsk: () -> Void
    @ObservedObject var settings: SettingsStore
    let onStealth: () -> Void
    let onUnfold: () -> Void
    /// ⚙: the menu for this state, under the button (its frame in the pill's coordinates).
    var onMenu: (PillState, CGRect) -> Void = { _, _ in }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = PillState(
                isListening: listening.isListening, isPaused: listening.isPaused, elapsed: listening.elapsed(at: context.date),
                mode: assist.mode, provider: providerName, providerDetail: providers.activeDescription, isUnfolded: overlay.isUnfolded,
                isStealth: settings.stealth, labels: ShortcutLabels.current
            )
            PillView(
                state: state,
                onListen: listening.pauseOrResume, onStop: listening.toggle, onAsk: onAsk, onStealth: onStealth, onUnfold: onUnfold,
                onMenu: { onMenu(state, $0) }
            )
        }
    }

    private var providerName: String? {
        guard providers.current() != nil else { return nil }
        return providers.activeKind == .codex ? "Codex" : "Claude"
    }
}
