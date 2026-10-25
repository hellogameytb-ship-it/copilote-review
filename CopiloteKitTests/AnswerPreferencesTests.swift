import XCTest
@testable import CopiloteKit

/// What the user sets once (Cluely's custom prompt, Final Round's company and role, the answers'
/// language) goes with every request.
final class AnswerPreferencesTests: XCTestCase {
    private func lastText(_ conversation: Conversation) throws -> String {
        try XCTUnwrap(conversation.messages.last?["content"]?.arrayValue?.last?["text"]?.stringValue)
    }

    func test_theUsersContextAndLanguageGoWithEveryRequest() throws {
        var conversation = Conversation()
        conversation.preferences = AnswerPreferences(instructions: "Entretien chez Hexa Trading (fictif), stage SWE.", language: .english)

        conversation.appendUser(.clipboardText("Explique ce code"))
        let text = try lastText(conversation)

        XCTAssertTrue(text.contains("Entretien chez Hexa Trading (fictif), stage SWE."), text)
        XCTAssertTrue(text.contains("Always answer in English"), text)
    }

    /// Only the request's last turn carries them: they don't pile up in the kept turns, and an edit
    /// in the middle of a session applies to the next request.
    func test_onlyTheLastTurnCarriesThemAndAnEditAppliesAtOnce() throws {
        var conversation = Conversation()
        conversation.preferences = AnswerPreferences(instructions: "Réponses courtes.")
        conversation.appendUser(.clipboardText("Première question"))
        conversation.appendAssistant(content: [["type": "text", "text": "Réponse."]])
        conversation.appendUser(.clipboardText("Deuxième question"))
        conversation.preferences = AnswerPreferences(instructions: "Réponses détaillées.")

        let first = try XCTUnwrap(conversation.messages.first?["content"]?.arrayValue?.last?["text"]?.stringValue)
        XCTAssertFalse(first.contains("Réponses courtes."), first)
        let last = try lastText(conversation)
        XCTAssertTrue(last.contains("Réponses détaillées."), last)
        XCTAssertFalse(last.contains("Réponses courtes."), last)
    }

    func test_nothingSetAddsNothing() throws {
        var conversation = Conversation()
        conversation.appendUser(.clipboardText("Explique ce code"))
        XCTAssertFalse(try lastText(conversation).contains("Mes consignes"))
    }

    /// Cluely's "Follow-up questions": what the user could ask them now.
    func test_questionsToAskIsAnActionOfItsOwn() throws {
        var conversation = Conversation()
        conversation.appendUser(.assist(AssistQuestion(action: .questions, mode: .meeting, question: nil, heard: [], context: AssistContext())))
        let text = try lastText(conversation)
        XCTAssertTrue(text.contains("## Questions to ask"), text)
        XCTAssertEqual(AssistAction.questions.name, "Suggest follow-ups")
    }
}
