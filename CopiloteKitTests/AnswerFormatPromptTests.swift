import XCTest
@testable import CopiloteKit

/// Each kind of question asks the model for its own ready-to-say format.
final class AnswerFormatPromptTests: XCTestCase {
    private let favouriteBook = BaseSnippet(source: "Mes avis › Livre préféré (avis.md)", text: "L'Étranger de Camus, pour sa phrase sèche.")
    private let story = BaseSnippet(source: "Tram Live › Histoires › Pression / deadline (projets/tram-live.md)", text: "Démo au club dans 48 h…")

    private func instruction(_ format: AnswerFormat, action: AssistAction = .answer, extracts: [BaseSnippet] = [], switchOff: Bool = false) throws -> String {
        var context = AssistContext(extracts: extracts)
        if switchOff { for item in context.items { context.toggle(item.id) } }
        var conversation = Conversation()
        conversation.appendUser(.assist(AssistQuestion(action: action, mode: .meeting, question: "Le sujet", heard: ["La question"], context: context, format: format)))
        return try XCTUnwrap(conversation.messages.first?["content"]?.arrayValue?.last?["text"]?.stringValue)
    }

    func test_anEstimationReasonsInTheOpen_andSaysAForecastIsOne() throws {
        let forecast = try instruction(AnswerFormat(kind: .estimation, asksAboutTheFuture: true))
        for line in ["**Assumptions**", "**Calculation**", "**Range**", "**What changes the result**", "claim an estimate is a fact"] {
            XCTAssertTrue(forecast.contains(line), line)
        }
        XCTAssertTrue(forecast.contains("projection"), forecast)
        XCTAssertFalse(try instruction(AnswerFormat(kind: .estimation)).contains("projection"))
    }

    func test_aFactIsADirectAnswerAndTwoOrThreePoints() throws {
        XCTAssertTrue(try instruction(AnswerFormat(kind: .fact)).contains("2–3 supporting points"))
    }

    func test_aBehaviouralQuestionIsAStoryFromTheBase_readyToSay() throws {
        let text = try instruction(AnswerFormat(kind: .personal, isBehavioural: true), extracts: [story])
        for line in ["**Situation**", "**My actions**", "**Result**", "**What I learned**", "4–6 lines", "first-person"] {
            XCTAssertTrue(text.contains(line), line)
        }
        XCTAssertTrue(text.contains("[1] Tram Live › Histoires"), text)
    }

    func test_anOpinionInAvisIsTakenUpFaithfully() throws {
        let text = try instruction(AnswerFormat(kind: .opinion), extracts: [favouriteBook])
        XCTAssertTrue(text.contains("Faithfully restate"), text)
        XCTAssertFalse(text.contains("## Possible angles"))
    }

    /// Not in avis.md (or switched off): neutral angles, for Que dire too: no sentence with an opinion in it.
    func test_anOpinionNotInTheBaseIsNeverChosenForTheUser() throws {
        for text in [
            try instruction(AnswerFormat(kind: .opinion)),
            try instruction(AnswerFormat(kind: .opinion), extracts: [favouriteBook], switchOff: true),
            try instruction(AnswerFormat(kind: .opinion), action: .whatToSay),
        ] {
            XCTAssertTrue(text.contains("Do not choose one for me"), text)
            XCTAssertTrue(text.contains("## Possible angles"), text)
            XCTAssertFalse(text.contains("**Say:**"), text)
        }
    }

    /// Questions to ask them voice no opinion of the user's: their own format, even on an opinion question.
    func test_questionsToAskKeepTheirFormatOnAnOpinionQuestion() throws {
        let text = try instruction(AnswerFormat(kind: .opinion), action: .questions)
        XCTAssertTrue(text.contains("## Questions to ask"), text)
        XCTAssertFalse(text.contains("## Possible angles"), text)
    }

    func test_technicalAndUnknownKindsKeepTheStructuredAnswer() throws {
        XCTAssertTrue(try instruction(AnswerFormat(kind: .technical)).contains("## Complexity"))
        XCTAssertTrue(try instruction(AnswerFormat(kind: .none)).contains("## Key points"))
    }
}
