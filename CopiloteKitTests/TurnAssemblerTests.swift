import XCTest
@testable import CopiloteKit

/// Turns are cut from VAD events (when the speaker stops) and filled with final transcripts.
final class TurnAssemblerTests: XCTestCase {
    func test_aTurnEndsOnceTheSpeakerHasBeenQuietLongEnough_andItsTextIsFinal() {
        var assembler = TurnAssembler(speaker: .them)
        assembler.handle(.speechStarted(at: 0))
        assembler.addFinal("Comment marche le ramasse-miettes ?", start: 0.1, end: 2.9)
        assembler.handle(.speechEnded(at: 3.0))

        XCTAssertEqual(assembler.advance(to: 3.5), [])
        XCTAssertEqual(assembler.advance(to: 3.85), [
            Turn(speaker: .them, text: "Comment marche le ramasse-miettes ?", start: 0, end: 3.0),
        ])
    }

    func test_aShortPauseInsideATurnDoesNotSplitIt() {
        var assembler = TurnAssembler(speaker: .them)
        assembler.handle(.speechStarted(at: 0))
        assembler.addFinal("Bonjour.", start: 0, end: 2)
        assembler.handle(.speechEnded(at: 2))
        XCTAssertEqual(assembler.advance(to: 2.5), [])
        assembler.handle(.speechStarted(at: 2.5))
        assembler.addFinal("Ça va ?", start: 2.5, end: 5)
        assembler.handle(.speechEnded(at: 5))

        XCTAssertEqual(assembler.advance(to: 6), [Turn(speaker: .them, text: "Bonjour. Ça va ?", start: 0, end: 5)])
    }

    /// The transcriber finalizes a little after the VAD notices the silence.
    func test_waitsForTheLastFinalTranscript_butNotForever() {
        var waiting = TurnAssembler(speaker: .them)
        waiting.handle(.speechStarted(at: 0))
        waiting.addFinal("Première phrase.", start: 0, end: 1.5)
        waiting.handle(.speechEnded(at: 3))
        XCTAssertEqual(waiting.advance(to: 3.9), [])
        waiting.addFinal("Deuxième phrase.", start: 1.6, end: 2.9)
        XCTAssertEqual(waiting.advance(to: 4.0).map(\.text), ["Première phrase. Deuxième phrase."])

        var givingUp = TurnAssembler(speaker: .them)
        givingUp.handle(.speechStarted(at: 0))
        givingUp.addFinal("Première phrase.", start: 0, end: 1.5)
        givingUp.handle(.speechEnded(at: 3))
        XCTAssertEqual(givingUp.advance(to: 4.6).map(\.text), ["Première phrase."])
    }

    /// A long monologue still feeds the topic segmenter every ~10 s.
    func test_longContinuousSpeechIsCutEveryTenSeconds() {
        var assembler = TurnAssembler(speaker: .them)
        assembler.handle(.speechStarted(at: 0))
        assembler.addFinal("Alors voilà le contexte.", start: 0, end: 4)
        assembler.addFinal("On a une base de données qui sature.", start: 4, end: 9.5)
        XCTAssertEqual(assembler.advance(to: 9.9), [])

        XCTAssertEqual(assembler.advance(to: 10.1), [
            Turn(speaker: .them, text: "Alors voilà le contexte. On a une base de données qui sature.", start: 0, end: 9.5),
        ])

        assembler.addFinal("Comment tu ferais ?", start: 9.5, end: 11)
        assembler.handle(.speechEnded(at: 11.2))
        XCTAssertEqual(assembler.advance(to: 12.1), [Turn(speaker: .them, text: "Comment tu ferais ?", start: 9.5, end: 11.2)])
    }

    func test_flushReturnsWhatIsLeftWhenTheStreamEnds() {
        var assembler = TurnAssembler(speaker: .me)
        assembler.handle(.speechStarted(at: 1))
        assembler.addFinal("Je finis ma phrase", start: 1, end: 2)

        XCTAssertEqual(assembler.flush(), [Turn(speaker: .me, text: "Je finis ma phrase", start: 1, end: 2)])
        XCTAssertEqual(assembler.flush(), [])
    }
}
