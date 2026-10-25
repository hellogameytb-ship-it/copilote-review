import XCTest
@testable import CopiloteKit

/// FR and EN transcribers run side by side on the same audio; the arbiter keeps the more confident one.
final class LanguageArbiterTests: XCTestCase {
    func test_keepsTheMoreConfidentLanguageForTheSameSpeech() {
        var arbiter = LanguageArbiter(languages: ["fr", "en"])

        let first = arbiter.add(.init(language: "fr", text: "Comment marche le ramasse-miettes ?", start: 0, end: 4, confidence: 0.95), receivedAt: 10)
        let second = arbiter.add(.init(language: "en", text: "Common marsh the ramus mix", start: 0, end: 4, confidence: 0.19), receivedAt: 10.01)

        XCTAssertEqual(first, [])
        XCTAssertEqual(second, [ArbitratedText(language: "fr", text: "Comment marche le ramasse-miettes ?", start: 0, end: 4)])
    }

    /// One language may split a passage into two sentences where the other gives one.
    func test_waitsUntilBothLanguagesHaveCoveredTheSamePassage() {
        var arbiter = LanguageArbiter(languages: ["fr", "en"])

        XCTAssertEqual(arbiter.add(.init(language: "fr", text: "Première phrase.", start: 0, end: 2, confidence: 0.9), receivedAt: 1), [])
        XCTAssertEqual(arbiter.add(.init(language: "en", text: "Premier frays.", start: 0, end: 4, confidence: 0.3), receivedAt: 1.1), [])

        XCTAssertEqual(
            arbiter.add(.init(language: "fr", text: "Deuxième phrase.", start: 2, end: 4, confidence: 0.9), receivedAt: 1.2),
            [ArbitratedText(language: "fr", text: "Première phrase. Deuxième phrase.", start: 0, end: 4)]
        )
    }

    /// If one transcriber stays silent, the other's text still comes out, a moment later.
    func test_aLanguageThatStaysSilentDoesNotBlockTheOther() {
        var arbiter = LanguageArbiter(languages: ["fr", "en"])
        XCTAssertEqual(arbiter.add(.init(language: "en", text: "Hello there.", start: 0, end: 1, confidence: 0.8), receivedAt: 5), [])

        XCTAssertEqual(arbiter.advance(to: 5.3), [])
        XCTAssertEqual(arbiter.advance(to: 5.7), [ArbitratedText(language: "en", text: "Hello there.", start: 0, end: 1)])
    }

    /// Live (volatile) text is shown from the language that won last.
    func test_thePreferredLanguageFollowsTheLastWinner() {
        var arbiter = LanguageArbiter(languages: ["fr", "en"])
        XCTAssertEqual(arbiter.preferredLanguage, "fr")

        _ = arbiter.add(.init(language: "fr", text: "Wat is ze", start: 0, end: 2, confidence: 0.6), receivedAt: 1)
        _ = arbiter.add(.init(language: "en", text: "What is the", start: 0, end: 2, confidence: 0.95), receivedAt: 1)

        XCTAssertEqual(arbiter.preferredLanguage, "en")
    }

    /// FR covered 0-4 s, EN only 0-2 s when the timeout decided; EN's late 2-4 s must not come out again.
    func test_aLateResultForAPassageAlreadyDecidedIsDropped() {
        var arbiter = LanguageArbiter(languages: ["fr", "en"])
        _ = arbiter.add(.init(language: "fr", text: "Phrase complète.", start: 0, end: 4, confidence: 0.9), receivedAt: 1)
        _ = arbiter.add(.init(language: "en", text: "Frays", start: 0, end: 2, confidence: 0.4), receivedAt: 1)
        XCTAssertEqual(arbiter.advance(to: 1.7).map(\.text), ["Phrase complète."])

        XCTAssertEqual(arbiter.add(.init(language: "en", text: "complete.", start: 2, end: 4, confidence: 0.5), receivedAt: 2), [])
        XCTAssertEqual(arbiter.advance(to: 3), [])
    }
}
