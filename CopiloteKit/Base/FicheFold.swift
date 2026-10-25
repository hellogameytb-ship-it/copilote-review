import Foundation

/// The answer on screen, as far as the fiche above it is concerned.
public enum AnswerPhase: Equatable, Sendable {
    case none
    /// Asked, no words yet.
    case waiting
    case reading

    /// An error notice alone is nothing to read: the fiche stays open over it.
    public init(text: String, failed: Bool) {
        if !text.isEmpty {
            self = .reading
        } else {
            self = failed ? .none : .waiting
        }
    }
}

/// The fiche above an answer (the user, after the UX review): open until the answer has words, then
/// folded to one line so what to say comes first; never folded over nothing. A click opens it
/// again, and that choice holds until the next fiche.
public struct FicheFold: Equatable, Sendable {
    public private(set) var isFolded = false
    private var openedByUser = false

    public init() {}

    public mutating func ficheShown() {
        isFolded = false
        openedByUser = false
    }

    public mutating func answer(_ phase: AnswerPhase) {
        switch phase {
        case .none, .waiting: isFolded = false
        case .reading: if !openedByUser { isFolded = true }
        }
    }

    /// The folded line or the open fiche's chevron.
    public mutating func toggle() {
        isFolded.toggle()
        openedByUser = !isFolded
    }

    /// « Afficher » on a suggested fiche: open, and kept open.
    public mutating func open() {
        isFolded = false
        openedByUser = true
    }
}
