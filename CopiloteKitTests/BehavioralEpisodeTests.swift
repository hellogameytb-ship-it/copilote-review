import XCTest
@testable import CopiloteKit

final class BehavioralEpisodeTests: XCTestCase {
    private func item(_ source: String, _ body: String, _ kind: BaseKind = .project) -> BaseItem {
        BaseItem(id: source, kind: kind, source: source, title: "Record", text: body)
    }
    private let question = "Tell me about a time you faced a challenge."
    func test_qualityBeforeRetrievalCutoffAndParaphrases() {
        let distractors = (1...25).map { item("Projects/\($0).md", "The challenge was keeping work centralized. We wanted a shared inbox.") }
        let partial = item("CV.md", "An outage interrupted work. I investigated the queue.", .cv)
        let confirmed = item("Career/Interview notes.md", "A shipment failed. I traced the damaged seal and replaced it. As a result the shipment resumed.", .note)
        let corpus = (distractors + [partial, confirmed]).flatMap(BehavioralEpisode.passages)
        for query in [question, "Describe a setback you overcame.", "When something went wrong, what did you do?", "Tell me about a time when things went wrong."] {
            let intent = QueryIntent(question: query)
            XCTAssertTrue(intent.isBehavioral && intent.isPersonal)
            let selected = BehavioralEpisode.best(for: intent, in: corpus)
            XCTAssertEqual(selected.count, 1)
            XCTAssertTrue(selected.first?.source.contains("Interview notes.md") == true)
            XCTAssertTrue(selected.first?.text.contains("shipment failed") == true)
            XCTAssertTrue(selected.first?.text.contains("replaced it") == true)
            XCTAssertTrue(selected.first?.text.contains("shipment resumed") == true)
        }
    }
    func test_mentions_plans_unconfirmed_examples_other_people_and_excluded_sources_do_not_make_an_episode() {
        let story = "A shipment failed. I traced the seal and replaced it. The shipment resumed."
        let items = [
            item("work.md", "The challenge was keeping work centralized."),
            item("work.md", "A shipment failed. I would replace a damaged seal."),
            item("work.md", "A shipment failed. My colleague traced the seal and recovered the box."),
            item("CV/Entretien.md", "**À confirmer avant de l’utiliser**\n> " + story, .note),
            item("CV/Entretien.md", "Sample answer\n" + story, .note),
            item("Private/Interview.md", story, .note),
            item("Archives/Interview.md", story, .note),
            item("Unrelated reading.md", story, .note)
        ]
        XCTAssertTrue(items.flatMap(BehavioralEpisode.passages).isEmpty)
    }
    func test_partial_episode_preserves_only_what_is_documented() throws {
        let passage = "The queue failed. I inspected the import logs."
        let result = BehavioralEpisode.best(for: QueryIntent(question: question), in: BehavioralEpisode.passages(in: item("cv.md", passage, .cv)))
        XCTAssertEqual(try XCTUnwrap(result.first).text, passage)
    }
    func test_distinct_star_fields_stay_together_and_another_section_stays_out() throws {
        let note = item("Career/Entretien.md", """
            **Situation:** The batch failed at midnight.

            **Action:** I rerouted the pending orders.

            **Result:** The deliveries resumed that morning.

            ## Unrelated question
            I replaced an unrelated keyboard.
            """, .note)
        let selected = BehavioralEpisode.best(for: QueryIntent(question: question), in: BehavioralEpisode.passages(in: note))
        let text = try XCTUnwrap(selected.first?.text)
        XCTAssertTrue(text.contains("batch failed"))
        XCTAssertTrue(text.contains("rerouted"))
        XCTAssertTrue(text.contains("deliveries resumed"))
        XCTAssertFalse(text.contains("keyboard"))
    }

    func test_unconfirmed_interview_section_split_across_index_items_is_not_evidence() {
        func chunk(_ n: Int, _ text: String) -> BaseItem {
            var row = item("Career/Interview.md", text, .note)
            row.id = "Career/Interview.md#\(n)"
            row.section = "Extrait \(n)"
            return row
        }
        let rows = [chunk(1, "**A possible story — to confirm**"),
                    chunk(2, "> A shipment failed. I traced the seal and restored the shipment."),
                    chunk(3, "**Separate documented experience**\nThe batch failed. I rerouted the orders. Deliveries resumed.")]
        let selected = BehavioralEpisode.best(for: QueryIntent(question: question), in: BehavioralEpisode.catalog(rows.reversed()))
        XCTAssertEqual(selected.count, 1)
        XCTAssertTrue(selected[0].text.contains("rerouted"))
        XCTAssertFalse(selected[0].text.contains("seal"))
    }

    func test_named_project_keeps_its_own_episode_even_with_a_richer_unrelated_story() {
        let partial = item("Projects/Cedar.md", "The import failed. I inspected the logs.")
        let unrelated = item("Projects/Birch.md", "The batch failed. I rerouted the orders. Deliveries resumed.")
        let corpus = [partial, unrelated].flatMap(BehavioralEpisode.passages)
        let selected = BehavioralEpisode.best(for: QueryIntent(question: "What challenge did you face on Cedar?"), in: corpus, namedProjects: ["cedar"])
        XCTAssertEqual(selected.count, 1)
        XCTAssertTrue(selected[0].source.contains("Cedar.md"))
    }

    func test_specific_theme_does_not_fall_back_to_unrelated_rich_story() {
        let incident = item("Project.md", "The queue failed. I traced the messages and recovered the pending orders.")
        XCTAssertTrue(BehavioralEpisode.best(for: QueryIntent(question: "Describe a disagreement you handled."), in: BehavioralEpisode.passages(in: incident)).isEmpty)
    }
}
