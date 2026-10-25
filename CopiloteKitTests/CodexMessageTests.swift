import XCTest
@testable import CopiloteKit

/// Lines recorded from `codex app-server` 0.144.1 (ids shortened, nothing personal kept).
enum CodexFixtures {
    static let delta = #"{"method": "item/agentMessage/delta", "params": {"threadId": "th-1", "turnId": "tu-1", "itemId": "msg_1", "delta": " complex"}}"#
    static let turnCompleted = #"{"method": "turn/completed", "params": {"threadId": "th-1", "turn": {"id": "tu-1", "items": [], "itemsView": "notLoaded", "status": "completed", "error": null, "startedAt": 1792417071, "completedAt": 1792417076, "durationMs": 4970}}}"#
    static let turnFailed = #"{"method": "turn/completed", "params": {"threadId": "th-2", "turn": {"id": "tu-2", "items": [], "itemsView": "notLoaded", "status": "failed", "error": {"message": "{\"type\":\"error\",\"status\":400,\"error\":{\"type\":\"invalid_request_error\",\"message\":\"The 'gpt-6.1-sol' model is not supported when using Codex with a ChatGPT account.\"}}", "codexErrorInfo": "other", "additionalDetails": null}, "startedAt": 1792417076, "completedAt": 1792417080, "durationMs": 3919}}}"#
    static let errorNotification = #"{"method": "error", "params": {"error": {"message": "{\"type\":\"error\",\"status\":400,\"error\":{\"type\":\"invalid_request_error\",\"message\":\"The 'gpt-6.1-sol' model is not supported when using Codex with a ChatGPT account.\"}}", "codexErrorInfo": "other", "additionalDetails": null}, "willRetry": false, "threadId": "th-2", "turnId": "tu-2"}}"#
    static let threadStartResponse = #"{"id": 2, "result": {"thread": {"id": "th-1", "extra": null, "sessionId": "th-1", "forkedFromId": null, "parentThreadId": null, "preview": "", "ephemeral": true}}}"#
    static let agentMessageCompleted = #"{"method": "item/completed", "params": {"item": {"type": "agentMessage", "id": "msg_1", "text": "La capture demande l’algorithme.", "phase": "final_answer", "memoryCitation": null}, "threadId": "th-1", "turnId": "tu-1"}}"#
    static let warning = #"{"method": "warning", "params": {"threadId": "th-2", "message": "Model metadata for `gpt-6.1-sol` not found."}}"#
}

final class CodexMessageTests: XCTestCase {
    func test_readsAStreamedPieceOfTheAnswer() {
        XCTAssertEqual(CodexMessage(line: CodexFixtures.delta), .agentDelta(threadID: "th-1", text: " complex"))
    }

    /// The useful text is nested: the error message is itself a JSON string from the API.
    func test_readsTheEndOfATurn_withTheAPIsOwnErrorMessageWhenItFailed() {
        XCTAssertEqual(CodexMessage(line: CodexFixtures.turnCompleted), .turnCompleted(threadID: "th-1", failure: nil))
        XCTAssertEqual(
            CodexMessage(line: CodexFixtures.turnFailed),
            .turnCompleted(threadID: "th-2", failure: "The 'gpt-6.1-sol' model is not supported when using Codex with a ChatGPT account.")
        )
    }

    func test_readsErrorNotifications_andWhetherCodexRetriesOnItsOwn() {
        XCTAssertEqual(
            CodexMessage(line: CodexFixtures.errorNotification),
            .error(threadID: "th-2", message: "The 'gpt-6.1-sol' model is not supported when using Codex with a ChatGPT account.", willRetry: false)
        )
    }

    func test_readsResponsesToOurRequests_byID() {
        guard case let .response(id, result) = CodexMessage(line: CodexFixtures.threadStartResponse) else {
            return XCTFail("expected a response")
        }
        XCTAssertEqual(id, 2)
        XCTAssertEqual(result["thread"]?["id"], "th-1")
        XCTAssertEqual(
            CodexMessage(line: #"{"id": 3, "error": {"code": -32600, "message": "Invalid request: unknown field"}}"#),
            .responseError(id: 3, message: "Invalid request: unknown field")
        )
    }

    /// Approvals or user-input requests: Copilote must answer them (with a refusal) or the turn hangs.
    func test_recognisesRequestsSentByTheServer() {
        XCTAssertEqual(
            CodexMessage(line: #"{"id": 9, "method": "item/tool/requestUserInput", "params": {"threadId": "th-1"}}"#),
            .serverRequest(id: 9, method: "item/tool/requestUserInput")
        )
        // JSON-RPC ids may be strings too: those requests must be refused as well.
        XCTAssertEqual(
            CodexMessage(line: #"{"id": "apr-1", "method": "item/commandExecution/requestApproval", "params": {}}"#),
            .serverRequest(id: "apr-1", method: "item/commandExecution/requestApproval")
        )
        XCTAssertEqual(CodexMessage(line: CodexFixtures.warning), .other(method: "warning"))
    }

    /// The completed message is the authoritative text (deltas of a retried attempt would add up).
    func test_readsTheCompletedAnswer() {
        XCTAssertEqual(CodexMessage(line: CodexFixtures.agentMessageCompleted), .agentMessageCompleted(threadID: "th-1", text: "La capture demande l’algorithme."))
    }
}
