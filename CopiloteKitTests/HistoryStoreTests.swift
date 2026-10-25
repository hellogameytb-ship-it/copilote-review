import XCTest
@testable import CopiloteKit

final class HistoryStoreTests: XCTestCase {
    private var folder: URL!
    private var store: HistoryStore!
    private let october19 = Date(timeIntervalSince1970: 1_792_400_000) // 2026-10-19

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)")
        store = try HistoryStore(url: folder.appendingPathComponent("history.sqlite"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func test_sessionsComeBackNewestFirst_withTheirSummary() throws {
        try store.save(.sample(title: "Point produit", started: october19.addingTimeInterval(-86_400)))
        try store.save(.sample(title: "Entretien technique", started: october19, mode: .technical))

        let sessions = try store.sessions()

        XCTAssertEqual(sessions.map(\.title), ["Entretien technique", "Point produit"])
        XCTAssertEqual(sessions.first?.mode, .technical)
        XCTAssertEqual(sessions.first?.duration, 1_800)
    }

    /// Full text over titles, transcripts, answers and notes, accents aside.
    func test_searchFindsAWordAnywhereInASession() throws {
        try store.save(.sample(title: "Point produit", started: october19, line: "On garde la sortie au 12 novembre."))
        try store.save(.sample(title: "Café", started: october19, line: "Tu as vu le match hier ?"))

        XCTAssertEqual(try store.search("novembre").map(\.title), ["Point produit"])
        XCTAssertEqual(try store.search("cafe").map(\.title), ["Café"])
        XCTAssertEqual(try store.search("demo").map(\.title), ["Point produit", "Café"], "in the notes of both")
        XCTAssertEqual(try store.search("girafe"), [])
    }

    func test_aDeletedSessionIsGoneEverywhere() throws {
        let record = SessionRecord.sample(title: "À supprimer", started: october19)
        try store.save(record)

        try store.delete(id: record.id)

        XCTAssertEqual(try store.sessions(), [])
        XCTAssertNil(try store.session(id: record.id))
        XCTAssertEqual(try store.search("supprimer"), [])
    }

    /// Retention: older sessions go, recent ones stay.
    func test_purgeRemovesSessionsOlderThanTheRetention() throws {
        try store.save(.sample(title: "Vieux", started: october19.addingTimeInterval(-40 * 86_400)))
        try store.save(.sample(title: "Récent", started: october19.addingTimeInterval(-3 * 86_400)))

        XCTAssertEqual(try store.purge(olderThanDays: 30, now: october19), 1)
        XCTAssertEqual(try store.sessions().map(\.title), ["Récent"])
    }

    func test_aSessionOpensWhole_andExportsToMarkdown() throws {
        let record = SessionRecord.sample(title: "Point produit", started: october19, line: "On garde la sortie au 12 novembre.")
        try store.save(record)

        let opened = try XCTUnwrap(try store.session(id: record.id))
        XCTAssertEqual(opened, record)

        let markdown = opened.markdown
        XCTAssertTrue(markdown.hasPrefix("# Point produit\n"), markdown)
        XCTAssertTrue(markdown.contains("Mode: Meeting · duration: 30 min"), markdown)
        XCTAssertTrue(markdown.contains("## Cases\n- Date de sortie"), markdown)
        XCTAssertTrue(markdown.contains("**Them** : On garde la sortie au 12 novembre."), markdown)
        XCTAssertTrue(markdown.contains("## Answers\n### Répondre · Date de sortie"), markdown)
        XCTAssertTrue(markdown.contains("## Notes\n## Key points") || markdown.contains("### Key points"), markdown)
        XCTAssertTrue(markdown.contains("## Follow-up email\n**Subject:** Follow-up"), markdown)
    }
}

extension SessionRecord {
    static func sample(title: String, started: Date, mode: MeetingMode = .meeting, line: String = "On en reparle.") -> SessionRecord {
        let notes = MeetingNotes(
            title: title, keyPoints: [.init(text: "Préparer la démo", evidence: line)], decisions: [], actions: [],
            openQuestions: [], nextSteps: []
        )
        return SessionRecord(
            id: UUID(), started: started, duration: 1_800, mode: mode, title: title,
            transcript: [TranscriptLine(speaker: .them, text: line, start: 1, end: 3)],
            topics: [RecordedTopic(title: "Date de sortie", excerpt: [line])],
            answers: [RecordedAnswer(label: "Répondre · Date de sortie", markdown: "On peut tenir le 12.")],
            notes: notes, email: notes.email(mode: mode), review: nil
        )
    }
}

final class SessionRecordTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_792_400_000)

    /// What a session keeps: the transcript only with history on, its answers only, a title.
    func test_anEndedSessionKeepsItsOwnAnswers_andTheTranscriptOnlyWhenAsked() {
        let lines = [TranscriptLine(speaker: .them, text: "On garde le 12 ?", start: 1, end: 2)]
        let topics = [Topic(id: "t1", title: "Date de sortie", excerpt: ["On garde le 12 ?"], createdAt: started, updatedAt: started)]
        let answers = [
            (date: started.addingTimeInterval(-60), label: "Avant la réunion", text: "…"),
            (date: started.addingTimeInterval(120), label: "Répondre · Date de sortie", text: "Oui, le 12."),
        ]

        let kept = SessionRecord.ended(started: started, duration: 600, mode: .meeting, lines: lines, topics: topics, answers: answers, keepTranscript: true)
        let light = SessionRecord.ended(started: started, duration: 600, mode: .meeting, lines: lines, topics: [], answers: [], keepTranscript: false)

        XCTAssertEqual(kept.title, "Date de sortie")
        XCTAssertEqual(kept.answers.map(\.label), ["Répondre · Date de sortie"])
        XCTAssertEqual(kept.transcript, lines)
        XCTAssertEqual(light.transcript, [])
        XCTAssertTrue(light.title.hasPrefix("Session on "), light.title)
    }
}
