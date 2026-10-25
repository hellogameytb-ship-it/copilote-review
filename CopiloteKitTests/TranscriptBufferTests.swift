import XCTest
@testable import CopiloteKit

final class TranscriptBufferTests: XCTestCase {
    func test_retainsOpeningContextBeyondFiveMinutes() {
        var buffer = TranscriptBuffer()

        buffer.append(TranscriptLine(speaker: .them, text: "début de réunion", start: 0, end: 4))
        buffer.append(TranscriptLine(speaker: .me, text: "à 2 minutes", start: 120, end: 124))
        buffer.append(TranscriptLine(speaker: .them, text: "à 5 minutes 10", start: 306, end: 310))

        XCTAssertEqual(buffer.lines.map(\.text), ["début de réunion", "à 2 minutes", "à 5 minutes 10"])
    }

    /// The two channels finalize independently: lines arrive out of spoken order.
    func test_excerptFollowsSpokenOrder_mergesASpeakersConsecutiveLines_andCoversTheLastSeconds() {
        var buffer = TranscriptBuffer()
        buffer.append(TranscriptLine(speaker: .them, text: "Bonjour.", start: 0, end: 1))
        buffer.append(TranscriptLine(speaker: .them, text: "Tu peux te présenter ?", start: 40, end: 42))
        buffer.append(TranscriptLine(speaker: .me, text: "Oui, bien sûr.", start: 43, end: 44))
        buffer.append(TranscriptLine(speaker: .them, text: "Vas-y.", start: 42.5, end: 43))

        XCTAssertEqual(buffer.excerpt(last: 30), "Them : Tu peux te présenter ? Vas-y.\nMe : Oui, bien sûr.")
    }

    /// Ten silent minutes must not keep old lines around just because nobody spoke since.
    func test_silenceDoesNotEraseSessionMemory() {
        var buffer = TranscriptBuffer()
        buffer.append(TranscriptLine(speaker: .them, text: "il y a longtemps", start: 0, end: 4))
        buffer.append(TranscriptLine(speaker: .me, text: "récent", start: 400, end: 403))

        buffer.prune(now: 600)

        XCTAssertEqual(buffer.lines.map(\.text), ["il y a longtemps", "récent"])
    }
}
