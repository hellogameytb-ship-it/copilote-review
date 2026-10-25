import Foundation

/// When case 1 becomes a new question, its answer is drafted by itself, one generation at a time:
/// a newer case 1 (or a turn more on it) replaces the answer in flight; the model correcting the
/// same turn (better title, merge) keeps it; a withdrawn case cancels it. Never over an answer
/// the user asked for (⌥1-4, ⌘↩, the actions).
public struct AutoAnswerPolicy: Sendable {
    public enum Reaction: Equatable, Sendable {
        /// Cancel the automatic answer in flight, if any, and draft this case's.
        case start(Topic)
        case keep
        case cancel
    }

    private var versions: [String: Int] = [:]

    public init() {}

    public mutating func react(to topics: [Topic], change: TopicChange, userIsAnswering: Bool) -> Reaction {
        let id: String
        switch change {
        case let .created(changed), let .updated(changed), let .confirmed(changed): id = changed
        case let .merged(from, into):
            if versions.removeValue(forKey: from) != nil { versions[into] = topics.first { $0.id == into }?.version }
            return .keep
        case let .withdrawn(removed):
            return versions.removeValue(forKey: removed) == nil ? .keep : .cancel
        case .ignored, .dropped, .pinned: return .keep
        }
        guard !userIsAnswering, let topic = topics.first(where: { $0.id == id }), versions[id] != topic.version else { return .keep }
        versions[id] = topic.version
        return .start(topic)
    }
}
