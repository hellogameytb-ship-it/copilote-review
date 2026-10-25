import XCTest
@testable import CopiloteKit

/// The segmenter answers with structured output: a JSON text block in the message content.
final class TopicDecisionParsingTests: XCTestCase {
    func test_readsANewTopicFromTheMessageResponse() throws {
        let response = try Self.response(#"{"action":"new","topic_id":"","title":"Complexité d'une recherche dans un arbre"}"#)

        XCTAssertEqual(try TopicDecision(response: response), .new(title: "Complexité d'une recherche dans un arbre"))
    }

    func test_readsAContinuationAndSmallTalk() throws {
        XCTAssertEqual(
            try TopicDecision(response: Self.response(#"{"action":"continue","topic_id":"t2","title":"Cycles et ramasse-miettes"}"#)),
            .continueTopic(id: "t2", title: "Cycles et ramasse-miettes")
        )
        XCTAssertEqual(try TopicDecision(response: Self.response(#"{"action":"ignore","topic_id":"","title":""}"#)), .ignore)
    }

    /// Defensive reading: a title must exist to show a case, and stays short.
    func test_aDecisionWithoutUsableFieldsIsRepaired() throws {
        XCTAssertEqual(
            try TopicDecision(response: Self.response(#"{"action":"continue","topic_id":"","title":"Sans identifiant"}"#)),
            .new(title: "Sans identifiant")
        )
        XCTAssertEqual(try TopicDecision(response: Self.response(#"{"action":"new","topic_id":"","title":"  "}"#)), .ignore)
        XCTAssertEqual(
            try TopicDecision(response: Self.response(#"{"action":"continue","topic_id":"t1","title":""}"#)),
            .continueTopic(id: "t1", title: "")
        )
        let long = String(repeating: "mot ", count: 40)
        guard case let .new(title) = try TopicDecision(response: Self.response(#"{"action":"new","topic_id":"","title":"\#(long)"}"#)) else {
            return XCTFail("expected a new topic")
        }
        XCTAssertLessThanOrEqual(title.count, TopicDecision.maxTitleLength)
        XCTAssertTrue(title.hasSuffix("…"))
    }

    func test_anAnswerWithoutAJSONDecisionIsAnError() throws {
        let refusal = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8))

        XCTAssertThrowsError(try TopicDecision(response: refusal))
        XCTAssertThrowsError(try TopicDecision(response: Self.response("pas du JSON")))
    }

    /// Codex returns the structured output as the answer's text.
    func test_readsADecisionFromItsJSONText() throws {
        XCTAssertEqual(
            try TopicDecision(decisionText: #"{"action":"continue","topic_id":"t1","title":"Ton dernier projet et sa durée"}"#),
            .continueTopic(id: "t1", title: "Ton dernier projet et sa durée")
        )
        XCTAssertThrowsError(try TopicDecision(decisionText: "Je pense que c'est une suite."))
    }

    static func response(_ decisionJSON: String) throws -> JSONValue {
        let body = """
        {"id":"msg_1","type":"message","role":"assistant","model":"claude-haiku-5-5","stop_reason":"end_turn",
         "content":[{"type":"text","text":\(String(decoding: try JSONEncoder().encode(decisionJSON), as: UTF8.self))}]}
        """
        return try JSONDecoder().decode(JSONValue.self, from: Data(body.utf8))
    }
}
