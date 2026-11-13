import XCTest
@testable import CopiloteKit

final class InterviewFocusTests: XCTestCase {
    func test_recover_subject_across_fragment_without_answering_old_topic() {
        func focus(_ lines: [String]) -> InterviewFocus.Subject? {
            InterviewFocus.resolve(heard: [lines.map { "Them : " + $0 }.joined(separator: "\n")], conversation: [])?.subject
        }
        XCTAssertEqual(focus(["Tell me about your machine learning work.", "How did you handle class imbalance?", "What approach did you take?"]), .imbalance)
        XCTAssertEqual(focus(["How do you use AI tools in your coding workflow?", "Can you walk me through a specific example?"]), .workflow)
        XCTAssertEqual(focus(["What database systems have you used?", "Have you worked with any of those?"]), .databases)
        XCTAssertEqual(focus(["Can you describe an AI output you questioned?", "How did you handle it?"]), .verification)
        XCTAssertEqual(focus(["I will end the interview now", "They may reach you soon"]), .closing)
        XCTAssertNil(focus(["What database systems have you used?", "Explain how a heap works."]))
    }

    func test_graduation_reads_only_matching_cv_line_and_revalidates() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let index = try BaseIndex(url: tmp.appendingPathComponent("index.sqlite"))
        let cv = BaseItem(id: "cv", kind: .cv, source: "CV.md", title: "Resume", text: "Resume\nExpected graduation: May 2031")
        let note = BaseItem(id: "note", kind: .note, source: "test.md", title: "Example", text: "Expected graduation: May 2030")
        try index.replace(file: "CV.md", stamp: "1", items: [cv, note], vectors: [nil, nil])
        let search = BaseSearch(index: index, embedder: NoEmbedder())
        let selected = try await search.graduationSnippet()
        XCTAssertEqual(selected?.text, "Expected graduation: May 2031")
        let ref = try XCTUnwrap(selected)
        let current = try await search.revalidated([ref], lookup: "When will you graduate?")
        XCTAssertEqual(current, [ref])
        try index.removeAll()
        let gone = try await search.revalidated([ref], lookup: "When will you graduate?")
        XCTAssertTrue(gone.isEmpty)
    }

    func test_automatic_suppresses_asr_question_marks_on_explanations_but_accepts_requests() {
        XCTAssertFalse(TurnCompletion.automaticRequest("You would be working on engineering projects?"))
        XCTAssertFalse(TurnCompletion.automaticRequest("What I can tell you is that the team will follow up."))
        XCTAssertFalse(TurnCompletion.automaticRequest("I will end the interview now."))
        XCTAssertTrue(TurnCompletion.automaticRequest("Which project did you own?"))
    }
}
