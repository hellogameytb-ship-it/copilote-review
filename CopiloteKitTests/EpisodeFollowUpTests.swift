import XCTest
@testable import CopiloteKit

final class EpisodeFollowUpTests: XCTestCase {
    func test_referring_role_questions_but_not_new_subjects() {
        for text in ["what did you personally do?", "And what was your own contribution?", "Quel était ton rôle ?", "Qu’as-tu fait concrètement ?", "How did you validate it?"] {
            XCTAssertTrue(EpisodeReference.isFollowUp(text), text)
        }
        for text in ["What did you personally do at a different company?", "New topic: how does a heap work?", "What did you do for the Cedar project?"] {
            XCTAssertFalse(EpisodeReference.isFollowUp(text), text)
        }
    }

    func test_missing_sources_prompt_still_gives_concrete_conditional_guidance() {
        for technical in [false, true] {
            var c = Conversation()
            c.preferences.technicalInterview = technical
            c.appendUser(.assist(.init(action: .answer, mode: .technical, question: "What was my contribution?", heard: [], context: AssistContext(), typed: true, format: AnswerFormat(kind: .personal))))
            let wire = CodexPrompt.turnInput(for: c).compactMap { $0["text"]?.stringValue }.joined()
            XCTAssertTrue(wire.contains("Possible answer — use only if accurate"))
            XCTAssertTrue(wire.contains("specific plausible step"))
            XCTAssertTrue(wire.contains("Keep the entire proposed answer hypothetical"))
            XCTAssertFalse(wire.contains("offer a fill-in outline"))
        }
    }

    func test_role_question_with_evidence_uses_past_tense_options_without_hypothetical_guidance() {
        let context = AssistContext(extracts: [BaseSnippet(source: "Cedar", text: "Our team checked duplicate records.")])
        for technical in [false, true] {
            for question in ["What did you personally do?", "Quel était ton rôle ?"] {
                let request = AssistQuestion(action: .answer, mode: .technical, question: question, heard: [], context: context, typed: true)
                let wire = Prompts.assistInstruction(request, technicalInterview: technical)
                XCTAssertTrue(wire.contains(Prompts.personalRoleAnswer))
                XCTAssertFalse(wire.contains(Prompts.possibleAnswer))
            }
        }
        XCTAssertFalse(EpisodeReference.asksForRole("What was the outcome?"))
    }

    func test_normal_rechecks_indexed_text_and_rejects_deleted_episode() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = tmp.appendingPathComponent("Brain")
        let folder = root.appendingPathComponent("projet")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "# Cedar\n## Recovery\nThe queue failed. I rerouted the pending orders. Deliveries resumed.".write(to: folder.appendingPathComponent("Cedar.md"), atomically: true, encoding: .utf8)
        let index = try BaseIndex(url: tmp.appendingPathComponent("store/index.sqlite"))
        _ = try await BaseIndexer(index: index, embedder: NoEmbedder(), store: tmp.appendingPathComponent("store")).run(BaseSource(root: root))
        let base = PersonalBase(search: BaseSearch(index: index, embedder: NoEmbedder()), index: index, root: root)
        let lookup = "Tell me about a time you faced a challenge."
        let first = await AnswerPlan.make(heard: [lookup], base: base)
        XCTAssertEqual(first.extracts.count, 1)
        let ref = EpisodeReference(lookup: lookup, extracts: first.extracts)
        let linked = await AnswerPlan.make(heard: ["What did you personally do?"], base: base, episode: ref)
        XCTAssertEqual(linked.extracts, first.extracts)
        try index.removeAll()
        let deleted = await AnswerPlan.make(heard: ["What did you personally do?"], base: base, episode: ref)
        XCTAssertTrue(deleted.extracts.isEmpty)
    }

}
