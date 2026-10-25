import XCTest
@testable import CopiloteKit

final class BaseContextTests: XCTestCase {
    /// ⌥1-4 on a personal topic: the best extracts of the base go with it, each with its source.
    func test_aPersonalTopicCarriesNumberedExtracts_withTheirSource() throws {
        let numbers = BaseItem(id: "projets/revisio.md#chiffres", kind: .project, source: "projets/revisio.md", title: "Revisio",
                               section: "Chiffres", text: "Revisio\nChiffres\n120 utilisateurs la première semaine.")
        let skills = BaseItem.cv("Compétences", "- Langages : Python, TypeScript, Swift, C")
        var conversation = Conversation()

        conversation.appendUser(.topic(TopicQuestion(
            title: "Ton projet Revisio", excerpt: ["C'est quoi ton projet ?"], context: "", screenshots: [],
            personal: BaseContext.snippets(from: [numbers, skills])
        )))

        let text = try XCTUnwrap(conversation.messages.first?["content"]?.arrayValue?.last?["text"]?.stringValue)
        XCTAssertTrue(text.contains("[1] Revisio › Chiffres (projets/revisio.md)\n120 utilisateurs la première semaine."), text)
        XCTAssertTrue(text.contains("[2] CV › Compétences (cv.md)\n- Langages : Python, TypeScript, Swift, C"), text)
        XCTAssertTrue(text.contains("Cite [1]"), "the model is asked to cite its source")
    }

    func test_atMostFiveExtracts_eachCutOnAWord() {
        let long = BaseItem(id: "notes/a.md#x", kind: .note, source: "notes/a.md", title: "Notes", section: "Long",
                            text: "Notes\nLong\n" + String(repeating: "mot ", count: 300))
        let snippets = BaseContext.snippets(from: Array(repeating: long, count: 8))

        XCTAssertEqual(snippets.count, 5)
        XCTAssertLessThanOrEqual(snippets[0].text.count, 401)
        XCTAssertTrue(snippets[0].text.hasSuffix("…"))
        XCTAssertFalse(snippets[0].text.contains("mot mo…"))
    }

    func test_aTopicWithoutExtractsKeepsTheUsualPrompt() throws {
        var conversation = Conversation()
        conversation.appendUser(.topic(TopicQuestion(title: "GC", excerpt: ["Comment marche le GC ?"], context: "", screenshots: [])))

        let text = try XCTUnwrap(conversation.messages.first?["content"]?.arrayValue?.last?["text"]?.stringValue)
        XCTAssertFalse(text.contains("base perso"))
    }
}
