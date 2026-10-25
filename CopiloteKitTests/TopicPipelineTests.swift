import XCTest
@testable import CopiloteKit

final class TopicPipelineTests: XCTestCase {
    /// A network failure must not lose the turn: the keyword fallback decides instead.
    func test_whenTheModelCallFailsTheKeywordFallbackDecides() async {
        let updates = UpdateLog()
        let pipeline = TopicPipeline(segmenter: FailingSegmenter(), segmenterName: "claude-haiku-5-5") { updates.append($0) }

        await pipeline.handle(.them("Est-ce que tu peux m'expliquer comment fonctionne le ramasse-miettes en Java ?"))

        await pipeline.waitForModel()

        let topics = await pipeline.board.topics
        XCTAssertEqual(topics.map(\.title), ["Comment fonctionne le ramasse-miettes en Java"])
        XCTAssertEqual(topics.map(\.isProvisional), [false])
        XCTAssertEqual(updates.sources, ["lexical", "lexical (fallback: overloaded_error)"])
    }

    /// Only the others' questions become topics; the user's own words are context.
    func test_theUsersOwnTurnsDoNotOpenTopics() async {
        let pipeline = TopicPipeline(segmenter: nil, segmenterName: "") { _ in }

        await pipeline.handle(Turn(speaker: .me, text: "Je pense qu'on devrait migrer la base de données.", start: 0, end: 3))

        let topics = await pipeline.board.topics
        XCTAssertEqual(topics, [])
    }
}

/// Option 2: the case shows from keywords at once, the model corrects it without making it jump.
final class InstantTopicTests: XCTestCase {
    func test_aQuestionGetsItsCaseAtOnce_thenTheModelRenamesIt() async {
        let gate = Gate()
        let updates = UpdateLog()
        let segmenter = ScriptedSegmenter(gate: gate, decisions: [.new(title: "Ramasse-miettes en Java")])
        let pipeline = TopicPipeline(segmenter: segmenter, segmenterName: "codex") { updates.append($0) }

        await pipeline.handle(.them("Est-ce que tu peux m'expliquer comment fonctionne le ramasse-miettes en Java ?"))

        var topics = await pipeline.board.topics
        XCTAssertEqual(topics.map(\.title), ["Comment fonctionne le ramasse-miettes en Java"], "shown before the model answers")
        XCTAssertEqual(topics.map(\.isProvisional), [true])

        await gate.open()
        await pipeline.waitForModel()

        topics = await pipeline.board.topics
        XCTAssertEqual(topics.map(\.id), ["t1"], "the same case, renamed in place")
        XCTAssertEqual(topics.map(\.title), ["Ramasse-miettes en Java"])
        XCTAssertEqual(topics.map(\.isProvisional), [false])
        XCTAssertEqual(topics.first?.version, 1, "a better title alone keeps a prepared answer valid")
        XCTAssertEqual(updates.changes, [.created(id: "t1"), .confirmed(id: "t1")])
        XCTAssertEqual(updates.finals, [false, true])
    }

    func test_codexMergesTwoInstantCasesIntoOne() async {
        let gate = Gate()
        let updates = UpdateLog()
        let segmenter = ScriptedSegmenter(gate: gate, decisions: [
            .new(title: "La mémoire en Java"),
            .continueTopic(id: "t1", title: "Mémoire et ramasse-miettes en Java"),
        ])
        let pipeline = TopicPipeline(segmenter: segmenter, segmenterName: "codex") { updates.append($0) }

        await pipeline.handle(.them("Comment tu gères la mémoire dans une application Java ?", at: 0))
        await pipeline.handle(.them("Et le ramasse-miettes, il se déclenche quand exactement ?", at: 6))

        let instant = await pipeline.board.topics
        XCTAssertEqual(instant.map(\.id), ["t2", "t1"], "both turns shown without waiting for the model")

        await gate.open()
        await gate.open()
        await pipeline.waitForModel()

        let topics = await pipeline.board.topics
        XCTAssertEqual(topics.map(\.id), ["t1"])
        XCTAssertEqual(topics.map(\.title), ["Mémoire et ramasse-miettes en Java"])
        XCTAssertEqual(topics.first?.excerpt.count, 2)
        XCTAssertEqual(topics.map(\.isProvisional), [false])
        XCTAssertEqual(updates.changes.last, .merged(from: "t2", into: "t1"))
        XCTAssertEqual(segmenter.seen, [[], ["La mémoire en Java"]], "each turn is decided without the instant cases being corrected")
    }

    /// Small talk the keywords took for a question: the case goes, the one it pushed out comes back.
    func test_aCaseTheModelIgnoresLeavesTheBoardAsItWas() async {
        let questions = [
            "Quelle base de données tu choisirais pour un réseau social ?",
            "Comment tu testes une application iOS avant une sortie ?",
            "Parle-moi de ton dernier stage en entreprise.",
            "Tu ferais comment pour estimer le marché des trottinettes ?",
        ]
        let updates = UpdateLog()
        let segmenter = ScriptedSegmenter(decisions: questions.map { .new(title: String($0.prefix(12))) } + [.ignore])
        let pipeline = TopicPipeline(segmenter: segmenter, segmenterName: "codex") { updates.append($0) }
        for (index, question) in questions.enumerated() {
            await pipeline.handle(.them(question, at: Double(index) * 10))
        }
        await pipeline.waitForModel()
        let before = await pipeline.board.topics

        await pipeline.handle(.them("Bon, on a sacrément avancé aujourd'hui, c'était super agréable.", at: 50))
        await pipeline.waitForModel()

        let after = await pipeline.board.topics
        XCTAssertEqual(after, before)
        XCTAssertEqual(updates.changes.suffix(2), [.created(id: "t5"), .withdrawn(id: "t5")])
    }
}

/// The model's word on odd boards: nothing vanishes, nothing withdrawn comes back.
final class InstantTopicEdgeTests: XCTestCase {
    /// The model answers with the instant case's own id (it never saw it): the case stays.
    func test_aContinuationOfTheInstantCaseItselfKeepsIt() async {
        let segmenter = ScriptedSegmenter(decisions: [.continueTopic(id: "t1", title: "Ramasse-miettes en Java")])
        let pipeline = TopicPipeline(segmenter: segmenter, segmenterName: "codex") { _ in }

        await pipeline.handle(.them("Comment fonctionne le ramasse-miettes en Java ?"))
        await pipeline.waitForModel()

        let topics = await pipeline.board.topics
        XCTAssertEqual(topics.map(\.title), ["Ramasse-miettes en Java"])
        XCTAssertEqual(topics.map(\.isProvisional), [false])
    }

    /// Three pinned cases: a second instant case pushes out the first, which the model then withdraws.
    func test_anInstantCaseWithdrawnWhileOutOfTheBoardDoesNotComeBack() async throws {
        let gate = Gate()
        let questions = [
            "Quelle base de données tu choisirais pour un réseau social ?",
            "Comment tu testes une application iOS avant une sortie ?",
            "Tu ferais comment pour estimer le marché des trottinettes ?",
        ]
        let segmenter = ScriptedSegmenter(gate: gate, decisions: questions.map { .new(title: String($0.prefix(12))) } + [.ignore, .ignore])
        let pipeline = TopicPipeline(segmenter: segmenter, segmenterName: "codex") { _ in }
        for (index, question) in questions.enumerated() {
            await pipeline.handle(.them(question, at: Double(index) * 10))
            await gate.open()
        }
        await pipeline.waitForModel()
        for id in ["t1", "t2", "t3"] { await pipeline.togglePin(id: id) }

        await pipeline.handle(.them("Bon, on a sacrément avancé aujourd'hui, c'était super agréable.", at: 40))
        await pipeline.handle(.them("Franchement, la terrasse du café était bondée ce midi.", at: 50))
        await gate.open()
        await gate.open()
        await pipeline.waitForModel()

        let topics = await pipeline.board.topics
        XCTAssertEqual(Set(topics.map(\.id)), ["t1", "t2", "t3"])
        XCTAssertFalse(topics.contains(where: \.isProvisional))
    }
}

/// Lets a test hold the model's answer until it says so.
private actor Gate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var credits = 0

    func wait() async {
        if credits > 0 {
            credits -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        if waiting.isEmpty { credits += 1 } else { waiting.removeFirst().resume() }
    }
}

/// Returns its decisions in order and records the case titles it was shown.
private final class ScriptedSegmenter: TopicSegmenter, @unchecked Sendable {
    private let lock = NSLock()
    private let gate: Gate?
    private var decisions: [TopicDecision]
    private var shown: [[String]] = []

    init(gate: Gate? = nil, decisions: [TopicDecision]) {
        self.gate = gate
        self.decisions = decisions
    }

    var seen: [[String]] { lock.withLock { shown } }

    func decide(turn: Turn, topics: [Topic], context: String) async throws -> TopicDecision {
        lock.withLock { shown.append(topics.map(\.title)) }
        if let gate { await gate.wait() }
        return lock.withLock { decisions.removeFirst() }
    }
}

private struct FailingSegmenter: TopicSegmenter {
    func decide(turn: Turn, topics: [Topic], context: String) async throws -> TopicDecision {
        throw APIFailure(type: "overloaded_error", message: "Overloaded")
    }
}

private final class UpdateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [TopicUpdate] = []
    var sources: [String] { lock.withLock { log.map(\.source) } }
    var changes: [TopicChange] { lock.withLock { log.map(\.change) } }
    var finals: [Bool] { lock.withLock { log.map(\.isFinal) } }
    func append(_ update: TopicUpdate) { lock.withLock { log.append(update) } }
}
