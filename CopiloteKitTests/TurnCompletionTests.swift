import XCTest
@testable import CopiloteKit

final class TurnCompletionTests: XCTestCase {
    func test_incompleteFrenchAndEnglishWaitForContinuation() {
        for text in ["Comment comparer Python et", "What happens if", "Comment faire avec"] {
            XCTAssertFalse(TurnCompletion.isComplete(text))
        }
        XCTAssertTrue(TurnCompletion.isComplete("Comment comparer Python et Swift ?"))
        XCTAssertTrue(TurnCompletion.isComplete("What is a binary search tree?"))
    }
    func test_autoReplyRequiresAQuestionOrRequest() {
        XCTAssertFalse(TurnCompletion.requestsAnswer("Notre code utilise une table de hachage."))
        XCTAssertFalse(TurnCompletion.requestsAnswer("Comment comparer Python et"))
        XCTAssertTrue(TurnCompletion.requestsAnswer("Est-ce que Swift fonctionne sur Linux"))
        XCTAssertTrue(TurnCompletion.requestsAnswer("Why is a cache useful"))
    }
    func test_pauseAfterConjunctionDoesNotProduceAPrematureQuestion() {
        var assembler = TurnAssembler(speaker: .them)
        assembler.handle(.speechStarted(at: 0))
        assembler.addFinal("Comment comparer Python et", start: 0, end: 2)
        assembler.handle(.speechEnded(at: 2))
        XCTAssertEqual(assembler.advance(to: 2.85), [])
        assembler.handle(.speechStarted(at: 3))
        assembler.addFinal("Swift ?", start: 3, end: 4)
        assembler.handle(.speechEnded(at: 4))
        XCTAssertEqual(assembler.advance(to: 4.85).map(\.text), ["Comment comparer Python et Swift ?"])
    }
}
