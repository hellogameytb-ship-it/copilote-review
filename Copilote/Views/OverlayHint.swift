import SwiftUI

extension View {
    /// What a tooltip would say, for VoiceOver only. A tooltip is a system window that
    /// `sharingType = .none` does not cover: on the overlay it would show in a screen share.
    func overlayHint(_ text: String) -> some View {
        accessibilityHint(text)
    }
}
