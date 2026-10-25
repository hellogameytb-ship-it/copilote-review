import XCTest
@testable import CopiloteKit

final class TopicRequestTests: XCTestCase {
    func test_asksTheFastModelForAStructuredDecision_withoutThinking() throws {
        let board = TopicBoard.filled(["Ramasse-miettes en Java"])

        let body = TopicRequest.body(turn: .them("Et pour les cycles de références ?"), topics: board.topics, context: "Eux : Bonjour.")

        XCTAssertEqual(body["model"], "claude-haiku-5-5")
        XCTAssertEqual(body["thinking"], ["type": "disabled"])
        XCTAssertEqual(body["output_config"]?["effort"], "low")
        XCTAssertEqual(body["output_config"]?["format"]?["type"], "json_schema")
        XCTAssertEqual(
            body["output_config"]?["format"]?["schema"]?["properties"]?["action"]?["enum"],
            ["new", "continue", "ignore"]
        )
        XCTAssertNil(body["stream"])
        let prompt = try XCTUnwrap(body["messages"]?.arrayValue?.first?["content"]?.stringValue)
        XCTAssertTrue(prompt.contains("t1 · Ramasse-miettes en Java"), prompt)
        XCTAssertTrue(prompt.contains("Et pour les cycles de références ?"), prompt)
        XCTAssertTrue(prompt.contains("Eux : Bonjour."), prompt)
    }
}
