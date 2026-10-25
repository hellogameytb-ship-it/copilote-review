import XCTest
@testable import CopiloteKit

final class CodexRPCTests: XCTestCase {
    /// Every thread: nothing persisted, read-only sandbox, never asks for approval, empty working directory.
    func test_threadsAreEphemeral_readOnly_neverApproved_inADedicatedEmptyDirectory() {
        let message = CodexRPC.threadStart(
            id: 2, model: "gpt-5.6-luna", workingDirectory: "/tmp/copilote-codex", baseInstructions: "Sois concis.", serviceTier: "priority"
        )

        XCTAssertEqual(message["method"], "thread/start")
        XCTAssertEqual(message["id"], 2)
        XCTAssertEqual(message["params"], [
            "model": "gpt-5.6-luna",
            "cwd": "/tmp/copilote-codex",
            "baseInstructions": "Sois concis.",
            "ephemeral": true,
            "sandbox": "read-only",
            "approvalPolicy": "never",
            "serviceTier": "priority",
        ])
    }

    func test_aTurnCarriesTheInput_lowEffort_andTheOptionalJSONSchema() {
        let schema: JSONValue = ["type": "object"]

        let message = CodexRPC.turnStart(id: 3, threadID: "th-1", input: [["type": "text", "text": "Bonjour"]], effort: "low", outputSchema: schema)

        XCTAssertEqual(message["method"], "turn/start")
        XCTAssertEqual(message["params"], [
            "threadId": "th-1",
            "input": [["type": "text", "text": "Bonjour"]],
            "effort": "low",
            "outputSchema": ["type": "object"],
        ])
    }

    /// Any request from the server (approval, user input) is refused: Copilote only reads answers.
    func test_requestsFromTheServerAreRefused() {
        XCTAssertEqual(CodexRPC.refusal(of: .int(9)), [
            "jsonrpc": "2.0", "id": 9, "error": ["code": -32601, "message": "Copilote n'autorise aucune action."],
        ])
    }

    /// ⌘⇧X or a replaced background answer: Codex must stop generating, and the thread is released.
    func test_interruptsATurnAndReleasesItsThread() {
        XCTAssertEqual(CodexRPC.turnInterrupt(id: 5, threadID: "th-1", turnID: "tu-1")["params"], ["threadId": "th-1", "turnId": "tu-1"])
        XCTAssertEqual(CodexRPC.turnInterrupt(id: 5, threadID: "th-1", turnID: "tu-1")["method"], "turn/interrupt")
        XCTAssertEqual(CodexRPC.threadUnsubscribe(id: 6, threadID: "th-1")["method"], "thread/unsubscribe")
        XCTAssertEqual(CodexRPC.threadUnsubscribe(id: 6, threadID: "th-1")["params"], ["threadId": "th-1"])
    }

    func test_handshake() {
        XCTAssertEqual(CodexRPC.initialize(id: 1)["params"]?["clientInfo"]?["name"], "copilote")
        XCTAssertEqual(CodexRPC.initialized, ["jsonrpc": "2.0", "method": "initialized"])
    }
}
