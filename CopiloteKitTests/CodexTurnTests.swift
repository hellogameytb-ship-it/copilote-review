import XCTest
@testable import CopiloteKit

/// One Codex turn followed from the app-server's messages.
final class CodexTurnTests: XCTestCase {
    /// Codex may retry after an error: the deltas of both attempts add up, the completed message does not.
    func test_theCompletedMessageIsTheAnswer_evenAfterARetriedAttempt() {
        var turn = CodexTurn()

        XCTAssertEqual(turn.apply(.agentDelta(threadID: "th", text: "Bon")), "Bon")
        _ = turn.apply(.error(threadID: "th", message: "stream disconnected", willRetry: true))
        _ = turn.apply(.agentDelta(threadID: "th", text: "Bonjour"))
        _ = turn.apply(.agentMessageCompleted(threadID: "th", text: "Bonjour"))
        _ = turn.apply(.turnCompleted(threadID: "th", failure: nil))

        XCTAssertEqual(turn.result, .success("Bonjour"))
    }

    func test_aFinalErrorFailsTheTurn_andNothingIsFinishedBeforeTheEnd() {
        var turn = CodexTurn()
        _ = turn.apply(.error(threadID: "th", message: "usage limit reached", willRetry: false))
        XCTAssertNil(turn.result)

        _ = turn.apply(.turnCompleted(threadID: "th", failure: nil))

        XCTAssertEqual(turn.result, .failure(CodexFailure(message: "usage limit reached")))
    }

    func test_withoutACompletedMessageTheStreamedTextIsKept() {
        var turn = CodexTurn()
        _ = turn.apply(.agentDelta(threadID: "th", text: "Réponse "))
        _ = turn.apply(.agentDelta(threadID: "th", text: "courte"))
        _ = turn.apply(.turnCompleted(threadID: "th", failure: nil))

        XCTAssertEqual(turn.result, .success("Réponse courte"))
    }
}
