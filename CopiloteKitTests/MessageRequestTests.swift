import XCTest
@testable import CopiloteKit

final class MessageRequestTests: XCTestCase {
    func test_screenshotsAreSentInCaptureOrder_beforeTheInstruction() throws {
        var conversation = Conversation()
        conversation.appendUser(.screenshots([.fake("page 1"), .fake("page 2"), .fake("page 3")]))

        let body = MessageRequest.body(for: conversation, settings: .init(model: "claude-sonnet-5-5"))

        let content = try XCTUnwrap(body["messages"]?.arrayValue?.first?["content"]?.arrayValue)
        XCTAssertEqual(content.prefix(3).compactMap { $0["source"]?["data"]?.stringValue }, [
            Data("page 1".utf8).base64EncodedString(),
            Data("page 2".utf8).base64EncodedString(),
            Data("page 3".utf8).base64EncodedString(),
        ])
        XCTAssertEqual(content[0], [
            "type": "image",
            "source": ["type": "base64", "media_type": "image/jpeg", "data": .string(Data("page 1".utf8).base64EncodedString())],
        ])
        XCTAssertEqual(content.last?["type"], "text")
        XCTAssertEqual(content.last?["text"]?.stringValue?.contains("3 ordered screenshot"), true)
    }

    /// Latency: no up-front thinking and low effort, so text starts streaming right away.
    func test_sonnet55RunsWithoutUpFrontThinking_atTheConfiguredEffort() {
        let body = MessageRequest.body(for: .oneQuestion, settings: .init(model: "claude-sonnet-5-5", effort: .low))

        XCTAssertEqual(body["thinking"], ["type": "between_tools"])
        XCTAssertEqual(body["output_config"], ["effort": "low"])
    }

    /// `between_tools` exists only on Sonnet 5.5; other models keep their default thinking.
    func test_otherModelsKeepTheirDefaultThinking() {
        let body = MessageRequest.body(for: .oneQuestion, settings: .init(model: "claude-opus-5-5", effort: .medium))

        XCTAssertNil(body["thinking"])
        XCTAssertEqual(body["output_config"], ["effort": "medium"])
    }

    func test_modelDefaultEffortSendsNoOutputConfig() {
        let body = MessageRequest.body(for: .oneQuestion, settings: .init(model: "claude-haiku-4-5", effort: nil))

        XCTAssertNil(body["output_config"])
    }
}

final class MessageURLRequestTests: XCTestCase {
    func test_postsJSONToTheMessagesEndpointWithTheAPIKeyAndVersionHeaders() throws {
        let body: JSONValue = ["model": "claude-sonnet-5-5", "stream": true]

        let request = try MessageRequest.urlRequest(body: body, apiKey: "sk-ant-test")

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody)), body)
    }
}

final class ConversationTests: XCTestCase {
    func test_followUpsReplayThePreviousTurns_includingTheAssistantContentAsReceived() {
        var conversation = Conversation.oneQuestion
        let answer: [JSONValue] = [
            ["type": "thinking", "thinking": "", "signature": "sig"],
            ["type": "text", "text": "Trois pointeurs."],
        ]
        conversation.appendAssistant(content: answer)
        conversation.appendUser(.screenshots([.fake("follow-up")]))

        let messages = MessageRequest.body(for: conversation, settings: .init(model: "claude-sonnet-5-5"))["messages"]?.arrayValue

        XCTAssertEqual(messages?.map { $0["role"]?.stringValue }, ["user", "assistant", "user"])
        XCTAssertEqual(messages?[1]["content"], .array(answer))
    }

    func test_requestsUseAutomaticPromptCaching_soFollowUpsDoNotReprocessScreenshots() {
        let body = MessageRequest.body(for: .oneQuestion, settings: .init(model: "claude-sonnet-5-5"))

        XCTAssertEqual(body["cache_control"], ["type": "ephemeral"])
    }
}

final class TopicAnswerInputTests: XCTestCase {
    /// ⌥1-4: the topic, what they said, recent context, and the capture stack if there is one.
    func test_answeringATopicSendsItsExcerptAndContext_afterAnyCaptures() throws {
        var conversation = Conversation()
        let question = TopicQuestion(
            title: "Cycles et ramasse-miettes Java",
            excerpt: ["Comment marche le GC ?", "Et les cycles de références ?"],
            context: "Them : Comment marche le GC ?\nMe : Il marque les objets atteignables.",
            screenshots: [.fake("diagram")]
        )

        conversation.appendUser(.topic(question))

        let content = try XCTUnwrap(conversation.messages.first?["content"]?.arrayValue)
        XCTAssertEqual(content.first?["type"], "image")
        let text = try XCTUnwrap(content.last?["text"]?.stringValue)
        XCTAssertTrue(text.contains("Cycles et ramasse-miettes Java"), text)
        XCTAssertTrue(text.contains("Comment marche le GC ?\nEt les cycles de références ?"), text)
        XCTAssertTrue(text.contains("Me : Il marque les objets atteignables."), text)
    }
}

extension Conversation {
    static var oneQuestion: Conversation {
        var conversation = Conversation()
        conversation.appendUser(.clipboardText("Inverse une liste chaînée."))
        return conversation
    }
}
