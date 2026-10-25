import Foundation

/// A question or statement from the others that the user could answer.
public struct Topic: Equatable, Sendable, Identifiable {
    public let id: String
    public var title: String
    /// What the others said about it, turn by turn.
    public var excerpt: [String]
    public let createdAt: Date
    public var updatedAt: Date
    /// Bumped on every update: a pre-computed answer is only valid for one version.
    public var version: Int
    /// A pinned case never leaves the board (⌥⇧1-4).
    public var isPinned = false
    /// Shown at once from keywords; the model has not confirmed it yet.
    public var isProvisional = false

    public init(
        id: String, title: String, excerpt: [String], createdAt: Date, updatedAt: Date, version: Int = 1,
        isPinned: Bool = false, isProvisional: Bool = false
    ) {
        self.id = id
        self.title = title
        self.excerpt = excerpt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.isPinned = isPinned
        self.isProvisional = isProvisional
    }
}

/// What applying a decision did to the board.
public enum TopicChange: Equatable, Sendable {
    case created(id: String)
    case updated(id: String)
    case ignored
    /// New topic, but all four cases are pinned.
    case dropped
    case pinned(id: String)
    /// The model confirmed an instant case, maybe under a better title.
    case confirmed(id: String)
    /// The model found that an instant case was another one's topic: one case left.
    case merged(from: String, into: String)
    /// The model found nothing to answer in an instant case: it leaves the board.
    case withdrawn(id: String)
}

/// What the topic segmenter decided for one turn.
public enum TopicDecision: Equatable, Sendable {
    case new(title: String)
    case continueTopic(id: String, title: String)
    /// Small talk, acknowledgements: nothing to answer.
    case ignore
}

/// The 4 topic cases of the overlay: newest first, FIFO.
public struct TopicBoard: Sendable {
    public static let capacity = 4

    public private(set) var topics: [Topic] = []
    private var nextID = 1

    public init() {}

    @discardableResult
    public mutating func apply(_ decision: TopicDecision, turn: Turn, at date: Date) -> TopicChange {
        apply(decision, turn: turn, at: date, provisional: false).change
    }

    /// A new case may push the oldest unpinned one out: returned, to bring back if the new one goes.
    mutating func apply(_ decision: TopicDecision, turn: Turn, at date: Date, provisional: Bool) -> (change: TopicChange, evicted: Topic?) {
        switch decision {
        case let .new(title):
            return insert(title: title, turn: turn, at: date, provisional: provisional)
        case let .continueTopic(id, title):
            guard let index = topics.firstIndex(where: { $0.id == id }) else {
                let title = title.isEmpty ? LexicalTopicSegmenter.title(for: turn.text) : title
                return insert(title: title, turn: turn, at: date, provisional: provisional)
            }
            if !title.isEmpty { topics[index].title = title }
            topics[index].excerpt.append(turn.text)
            topics[index].updatedAt = date
            topics[index].version += 1
            return (.updated(id: id), nil)
        case .ignore:
            return (.ignored, nil)
        }
    }

    public mutating func togglePin(id: String) {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[index].isPinned.toggle()
    }

    private mutating func insert(title: String, turn: Turn, at date: Date, provisional: Bool) -> (change: TopicChange, evicted: Topic?) {
        var evicted: Topic?
        if topics.count >= Self.capacity {
            guard let oldestUnpinned = topics.lastIndex(where: { !$0.isPinned }) else { return (.dropped, nil) }
            evicted = topics.remove(at: oldestUnpinned)
        }
        let topic = Topic(
            id: "t\(nextID)", title: title, excerpt: [turn.text], createdAt: date, updatedAt: date, version: 1,
            isProvisional: provisional
        )
        topics.insert(topic, at: 0)
        nextID += 1
        return (.created(id: topic.id), evicted)
    }
}

// MARK: Correcting instant cases

extension TopicBoard {
    func contains(_ id: String) -> Bool {
        topics.contains { $0.id == id }
    }

    /// The model kept the case: a better title does not change what was asked (same version).
    mutating func confirm(_ id: String, title: String) {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return }
        if !title.isEmpty { topics[index].title = title }
        topics[index].isProvisional = false
    }

    /// Takes one turn's words out of a case. True when nothing is left in it.
    @discardableResult
    mutating func remove(_ text: String, from id: String) -> Bool {
        guard let index = topics.firstIndex(where: { $0.id == id }),
              let line = topics[index].excerpt.lastIndex(of: text) else { return false }
        topics[index].excerpt.remove(at: line)
        topics[index].version += 1
        return topics[index].excerpt.isEmpty
    }

    @discardableResult
    mutating func remove(_ id: String) -> Topic? {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return nil }
        return topics.remove(at: index)
    }

    /// A case pushed out by an instant case comes back, in its place, if there is room. Not an
    /// instant case itself: its own decision already settled whether it stays.
    mutating func restore(_ topic: Topic?) {
        guard let topic, !topic.isProvisional, topics.count < Self.capacity else { return }
        topics = Self.inserting(topic, into: topics)
    }

    /// One case left: the target, with the merged case's words and pin.
    mutating func merge(_ merged: Topic, into target: String, title: String, at date: Date) {
        guard let index = topics.firstIndex(where: { $0.id == target }) else { return }
        topics[index].excerpt += merged.excerpt
        if !title.isEmpty { topics[index].title = title }
        topics[index].updatedAt = date
        topics[index].version += 1
        topics[index].isPinned = topics[index].isPinned || merged.isPinned
    }

    func isPinned(_ id: String) -> Bool {
        topics.first { $0.id == id }?.isPinned ?? false
    }

    mutating func rename(_ id: String, to title: String) {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[index].title = title
    }

    /// Newest first: a topic goes back before the first one created earlier than it.
    static func inserting(_ topic: Topic, into topics: [Topic]) -> [Topic] {
        guard !topics.contains(where: { $0.id == topic.id }) else { return topics }
        var topics = topics
        topics.insert(topic, at: topics.firstIndex { $0.createdAt < topic.createdAt } ?? topics.endIndex)
        return topics
    }
}
