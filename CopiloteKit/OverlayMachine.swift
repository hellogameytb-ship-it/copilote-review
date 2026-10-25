import Foundation

/// The overlay's states, à la Cluely: a compact pill at the top of the screen, unfolded into
/// the panel (cases + answer) on click or ⌘↩, hidden by ⌘\. The panel takes the keyboard only
/// while the user types in "Demander", then gives it back to the call app.
public struct OverlayMachine: Equatable, Sendable {
    public enum Presentation: Equatable, Sendable {
        case hidden
        case pill
        case panel
    }

    public enum Event: Equatable, Sendable {
        /// ⌘\.
        case toggleVisibility
        case pillClicked
        /// ⌘↩: help me now.
        case assist(hasTopic: Bool)
        case startTyping
        case endTyping
        /// An answer began from another shortcut (⌥1-4, captures, clipboard).
        case answerStarted
    }

    public enum Effect: Equatable, Sendable {
        case answerLatestTopic
        case takeKeyboard
        case giveKeyboardBack
    }

    public private(set) var presentation: Presentation = .pill
    public private(set) var isTyping = false
    /// What ⌘\ brings back.
    private var lastVisible: Presentation = .pill

    public init() {}

    @discardableResult
    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .toggleVisibility:
            let effects = stopTyping()
            if presentation == .hidden {
                presentation = lastVisible
            } else {
                lastVisible = presentation
                presentation = .hidden
            }
            return effects
        case .pillClicked:
            guard presentation != .hidden else { return [] }
            let effects = stopTyping()
            presentation = presentation == .panel ? .pill : .panel
            return effects
        case let .assist(hasTopic):
            presentation = .panel
            return hasTopic ? [.answerLatestTopic] : []
        case .startTyping:
            presentation = .panel
            guard !isTyping else { return [] }
            isTyping = true
            return [.takeKeyboard]
        case .endTyping:
            return stopTyping()
        case .answerStarted:
            if presentation == .pill { presentation = .panel }
            return []
        }
    }

    private mutating func stopTyping() -> [Effect] {
        guard isTyping else { return [] }
        isTyping = false
        return [.giveKeyboardBack]
    }
}
