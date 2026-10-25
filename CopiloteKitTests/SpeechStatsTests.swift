import XCTest
@testable import CopiloteKit

/// Final Round's diction signals (share of talk time, words, pace, verbal tics), computed on the
/// Mac from the transcript: no model, nothing sent.
final class SpeechStatsTests: XCTestCase {
    private func line(_ speaker: Speaker, _ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TranscriptLine {
        TranscriptLine(speaker: speaker, text: text, start: start, end: end)
    }

    func test_shareOfTalkTimeWordsAndPace() throws {
        let stats = try XCTUnwrap(SpeechStats(transcript: [
            line(.them, "Parle-moi de ton dernier projet.", 0, 20),
            line(.me, "J'ai construit une appli de quiz et de fiches pour réviser.", 20, 50),
            line(.them, "Combien d'utilisateurs ?", 50, 60),
        ]))

        XCTAssertEqual(stats.talkShare, 0.5, accuracy: 0.001)
        XCTAssertEqual(stats.words, 11)
        XCTAssertEqual(stats.wordsPerMinute, 22)
        XCTAssertTrue(stats.summary.contains("50%"), stats.summary)
        XCTAssertTrue(stats.summary.contains("11 words"), stats.summary)
    }

    func test_verbalTicsAreWholeWordsOrPhrasesMostFrequentFirst() throws {
        let stats = try XCTUnwrap(SpeechStats(transcript: [
            line(.me, "Euh, du coup j'ai, euh, refait le parseur.", 0, 10),
            line(.me, "C'était généreux de leur part, du coup. Euh voilà.", 10, 20),
            line(.them, "Euh, d'accord.", 20, 22),
        ]))

        XCTAssertEqual(stats.fillers, [SpeechStats.Filler(word: "euh", count: 3), SpeechStats.Filler(word: "du coup", count: 2)])
        XCTAssertTrue(stats.summary.contains("« euh » ×3"), stats.summary)
    }

    func test_noStatsWhenTheUserNeverSpoke() {
        XCTAssertNil(SpeechStats(transcript: [line(.them, "Bonjour à tous.", 0, 3)]))
    }

    func test_noPaceOnLessThanThirtySecondsOfSpeech() throws {
        let stats = try XCTUnwrap(SpeechStats(transcript: [line(.me, "Oui, tout à fait.", 0, 2)]))

        XCTAssertNil(stats.wordsPerMinute)
        XCTAssertFalse(stats.summary.contains("words/min"), stats.summary)
    }
}
