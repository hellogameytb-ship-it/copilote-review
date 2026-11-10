import XCTest
import CryptoKit
@testable import CopiloteKit

final class InterviewEvidenceStoreTests: XCTestCase {
    private var root: URL!
    private var database: URL!
    private var source: URL!
    private var note: URL!
    private var reader: InterviewEvidenceStore { .init(database: database, root: root) }
    private let question = "Tell me about a time you faced a challenge."

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        database = root.appendingPathComponent("evidence.sqlite")
        source = root.appendingPathComponent("CV/Recruiter.pdf")
        note = root.appendingPathComponent("CV/Interview.md")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fictional source revision 1".utf8).write(to: source)
        try Data("fictional preparation note".utf8).write(to: note)
        try SQLiteDatabase(path: database.path).execute("create table evidence(id text,topic text,tags text,passage text,source text,source_sha256 text)")
        try insert("a", "Harbor", "challenge technical teamwork", "The team tested a simulated queue.", file: source)
        try insert("b", "Harbor", "challenge technical teamwork", "The simulated delay was reduced by 12%.", file: source)
        try insert("c", "Unrelated role", "education", "UNRELATED_DIPLOMA", file: source)
        try insert("d", "Academic recovery", "challenge setback resilience failure academic", "I failed the course, retook it and passed.", file: note)
    }
    private func insert(_ id: String, _ topic: String, _ tags: String, _ passage: String, file: URL) throws {
        let hash = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
        let label = file.lastPathComponent + (file == source ? " · p. 1" : " · preparation")
        try SQLiteDatabase(path: database.path).run("insert into evidence values(?,?,?,?,?,?)", [id, topic, tags, passage, label, hash].map(SQLiteDatabase.Value.text))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func test_recruiterCVSelectedForBehavioralParaphrasesWithOriginalQualifiers() throws {
        for q in [question, "When something went wrong, what did you do?", "Raconte-moi un défi que tu as surmonté."] {
            let results = reader.snippets(for: q)
            let best = try XCTUnwrap(results.first, q)
            XCTAssertEqual(results.count, 1)
            XCTAssertTrue(best.source.contains("Recruiter CV"), q)
            XCTAssertTrue(best.source.contains("p. 1"))
            XCTAssertTrue(best.source.contains("team project"))
            XCTAssertTrue(best.text.contains("team tested a simulated queue"))
            XCTAssertTrue(best.text.contains("reduced by 12%"))
            XCTAssertFalse(best.text.contains("UNRELATED_DIPLOMA"))
        }
    }
    func test_specific_academic_setback_uses_preparation_provenance() throws {
        let best = try XCTUnwrap(reader.snippets(for: "What academic setback or failure did you overcome?").first)
        XCTAssertTrue(best.source.contains("Interview preparation note"))
        XCTAssertTrue(best.text.contains("retook"))
    }
    func test_normal_technical_and_shifted_live_requests_do_not_attach_private_rows() async {
        let inactive = await AnswerPlan.make(heard: [question], base: nil)
        XCTAssertTrue(inactive.extracts.isEmpty)
        XCTAssertTrue(reader.snippets(for: "Explain the lifetime of a C++ reference.").isEmpty)
        XCTAssertTrue(reader.snippets(for: "Which language would you use for a new project?").isEmpty)
        XCTAssertTrue(reader.snippets(for: "How would you design a project in Java?").isEmpty)
        let shifted = await AnswerPlan.make(heard: ["Them : \(question)\nThem : Explain the lifetime of a C++ reference.\nThem : okay"], base: nil, interviewEvidence: reader)
        XCTAssertTrue(shifted.extracts.isEmpty)
    }
    func test_stale_pdf_is_rejected_and_replacement_reloads_next_request() throws {
        try Data("fictional source revision 2".utf8).write(to: source)
        XCTAssertFalse(reader.snippets(for: question).contains { $0.source.contains("Recruiter CV") })
        try insert("e", "Revised role", "challenge", "I traced a broken spool and restored the import.", file: source)
        let best = try XCTUnwrap(reader.snippets(for: question).first)
        XCTAssertTrue(best.text.contains("spool"))
        XCTAssertFalse(best.text.contains("simulated delay"))
    }
    func test_missing_db_and_disabled_extract_fail_closed() throws {
        let missing = root.appendingPathComponent("missing.sqlite")
        XCTAssertTrue(InterviewEvidenceStore(database: missing, root: root).snippets(for: question).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let result = try XCTUnwrap(reader.snippets(for: question).first)
        var context = AssistContext(extracts: [result])
        context.toggle("extract-" + result.source)
        context.refresh(lines: [], captures: [], extracts: [])
        context.replaceExtracts(with: [result])
        XCTAssertTrue(context.includedExtracts.isEmpty)
    }
    func test_followup_revalidates_original_source_and_never_substitutes_another_episode() async throws {
        let ref = try XCTUnwrap(reader.snippets(for: question).first)
        let episode = EpisodeReference(lookup: question, extracts: [ref])
        func follow() async -> AnswerPlan {
            await AnswerPlan.make(heard: ["what did you personally do?"], base: nil, interviewEvidence: reader, episode: episode)
        }
        let valid = await follow()
        XCTAssertEqual(valid.extracts, [ref])
        try Data("updated real source bytes".utf8).write(to: source)
        let changed = await follow()
        XCTAssertTrue(changed.extracts.isEmpty)
        let unrelated = await AnswerPlan.make(heard: ["Explain a linked list"], base: nil, interviewEvidence: reader, episode: episode)
        XCTAssertTrue(unrelated.extracts.isEmpty)
    }

}
