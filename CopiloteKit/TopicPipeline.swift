import Foundation

/// The board after one turn of the others was decided.
public struct TopicUpdate: Sendable {
    public let topics: [Topic]
    public let change: TopicChange
    public let turn: Turn?
    /// Which segmenter decided ("codex", "lexical", "lexical (fallback: …)").
    public let source: String
    /// Since the turn ended, in seconds.
    public let latency: TimeInterval
    /// False for the instant keyword case the model will still correct.
    public let isFinal: Bool
}

/// Turns of the others → topic decisions → the 4-case board, with the transcript kept for context.
///
/// A turn shows at once from keywords. With a model, its decision follows (in turn order, never
/// holding up the next instant case) and corrects the instant case in place: better title, merged
/// into the case it belongs to, or withdrawn. When the model call fails, the keywords stand.
public actor TopicPipeline {
    public private(set) var board = TopicBoard()
    public private(set) var transcript = TranscriptBuffer()

    private let segmenter: (any TopicSegmenter)?
    private let segmenterName: String
    private let lexical = LexicalTopicSegmenter()
    private let onUpdate: @Sendable (TopicUpdate) -> Void
    /// Turns shown from keywords whose model decision has not come back, oldest first.
    private var pending: [Pending] = []
    private var modelQueue: Task<Void, Never>?
    private var nextSequence = 0

    private struct Pending {
        let sequence: Int
        let turn: Turn
        var placement: Placement
        let started: TimeInterval
    }

    /// Where the keywords put a turn, to undo it if the model decides otherwise.
    private enum Placement: Equatable {
        case created(id: String, evicted: Topic?)
        case appended(id: String)
        case nowhere
    }

    /// Without a segmenter (no provider), keywords only.
    public init(segmenter: (any TopicSegmenter)?, segmenterName: String, onUpdate: @escaping @Sendable (TopicUpdate) -> Void) {
        self.segmenter = segmenter
        self.segmenterName = segmenter == nil ? "lexical" : segmenterName
        self.onUpdate = onUpdate
    }

    public func add(_ line: TranscriptLine) {
        transcript.append(line)
    }

    /// Only the others' turns open or continue topics. Returns once the instant case is shown;
    /// callers await each turn (`ListeningSession` does), so turns are decided in order.
    public func handle(_ turn: Turn) async {
        guard turn.speaker == .them else { return }
        for request in InterviewerRequests.turns(in: turn) { await handleRequest(request) }
    }

    private func handleRequest(_ turn: Turn) async {
        let started = Self.now
        let decision = lexical.decision(for: turn, topics: board.topics)
        guard segmenter != nil else {
            publish(board.apply(decision, turn: turn, at: Date()), turn: turn, source: segmenterName, started: started, isFinal: true)
            return
        }
        let (change, evicted) = board.apply(decision, turn: turn, at: Date(), provisional: true)
        let placement: Placement
        switch change {
        case let .created(id): placement = .created(id: id, evicted: evicted)
        case let .updated(id): placement = .appended(id: id)
        default: placement = .nowhere
        }
        nextSequence += 1
        let sequence = nextSequence
        pending.append(Pending(sequence: sequence, turn: turn, placement: placement, started: started))
        publish(change, turn: turn, source: "lexical", started: started, isFinal: false)

        let previous = modelQueue
        modelQueue = Task {
            await previous?.value
            await self.decideWithModel(sequence)
        }
    }

    /// Waits for the model's decisions on every turn handled so far.
    public func waitForModel() async {
        while !pending.isEmpty, let queue = modelQueue {
            await queue.value
        }
    }

    public func togglePin(id: String) {
        board.togglePin(id: id)
        onUpdate(TopicUpdate(topics: board.topics, change: .pinned(id: id), turn: nil, source: "", latency: 0, isFinal: true))
    }

    /// The last `seconds` of the conversation, both speakers.
    public func context(last seconds: TimeInterval) -> String {
        transcript.excerpt(last: seconds)
    }

    private func decideWithModel(_ sequence: Int) async {
        guard let segmenter, let turn = pending.first(where: { $0.sequence == sequence })?.turn else { return }
        let decision: TopicDecision?
        let source: String
        do {
            decision = try await segmenter.decide(turn: turn, topics: topicsBeforePendingTurns(), context: transcript.excerpt(last: .infinity))
            source = segmenterName
        } catch {
            decision = nil
            source = "lexical (fallback: \((error as? APIFailure)?.type ?? String(describing: type(of: error))))"
        }
        guard let index = pending.firstIndex(where: { $0.sequence == sequence }) else { return }
        let item = pending.remove(at: index)
        publish(correct(item, with: decision), turn: turn, source: source, started: item.started, isFinal: true)
    }

    /// The board as the model last left it: every instant case and word still pending taken out,
    /// newest first.
    private func topicsBeforePendingTurns() -> [Topic] {
        var view = board
        for item in pending.reversed() {
            switch item.placement {
            case let .created(id, evicted):
                view.remove(id)
                view.restore(evicted)
            case let .appended(id):
                view.remove(item.turn.text, from: id)
            case .nowhere:
                break
            }
        }
        return view.topics
    }

    /// Moves the turn from where the keywords put it to where the model did, keeping case ids.
    /// Without a decision (the call failed), the keywords stand.
    private func correct(_ item: Pending, with decision: TopicDecision?) -> TopicChange {
        let now = Date()
        switch (item.placement, decision) {
        case let (.created(id, _), nil):
            board.confirm(id, title: "")
            return .confirmed(id: id)
        case let (.appended(id), nil):
            return .confirmed(id: id)
        case (.nowhere, nil):
            return .ignored

        // The model never saw the instant case: its own id back means "a new topic".
        case let (.created(id, evicted), .continueTopic(target, title))
            where target != id && (board.contains(target) || evicted?.id == target):
            guard let merged = board.remove(id) else { return board.apply(.continueTopic(id: target, title: title), turn: item.turn, at: now) }
            board.restore(evicted)
            board.merge(merged, into: target, title: title, at: now)
            for index in pending.indices where pending[index].placement == .appended(id: id) {
                pending[index].placement = .appended(id: target)
            }
            return .merged(from: id, into: target)
        case let (.created(id, _), .new(title)), let (.created(id, _), .continueTopic(_, title)):
            board.confirm(id, title: title)
            return .confirmed(id: id)
        case let (.created(id, evicted), .ignore):
            guard board.contains(id) else { return .ignored }
            // A pinned case is the user's choice: it stays.
            guard !board.isPinned(id) else {
                board.confirm(id, title: "")
                return .confirmed(id: id)
            }
            guard !board.remove(item.turn.text, from: id) else {
                board.remove(id)
                board.restore(evicted)
                return .withdrawn(id: id)
            }
            // Later instant turns went into this case: it becomes the first one's.
            if let next = pending.firstIndex(where: { $0.placement == .appended(id: id) }) {
                pending[next].placement = .created(id: id, evicted: evicted)
                board.rename(id, to: LexicalTopicSegmenter.title(for: pending[next].turn.text))
            }
            return .updated(id: id)

        case let (.appended(id), .continueTopic(target, title)) where target == id:
            board.confirm(id, title: title)
            return .confirmed(id: id)
        case let (.appended(id), decision?):
            board.remove(item.turn.text, from: id)
            return board.apply(decision, turn: item.turn, at: now)
        case let (.nowhere, decision?):
            return board.apply(decision, turn: item.turn, at: now)
        }
    }

    private func publish(_ change: TopicChange, turn: Turn, source: String, started: TimeInterval, isFinal: Bool) {
        onUpdate(TopicUpdate(topics: board.topics, change: change, turn: turn, source: source, latency: Self.now - started, isFinal: isFinal))
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
