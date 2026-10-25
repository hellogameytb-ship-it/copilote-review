import XCTest
@testable import CopiloteKit

/// The client against a stubbed network: the only boundary that is faked.
final class AnthropicClientTests: XCTestCase {
    override func tearDown() {
        StubProtocol.response = nil
        super.tearDown()
    }

    func test_streamsTextInOrder_andReturnsTheAssistantTurn() async throws {
        let stream = MessageStreamParserTests.textStream(deltas: ["Idée", " : trier", "."])
        StubProtocol.response = (200, Self.chunks(of: Data(stream.utf8), size: 7))
        let received = TextCollector()

        let completed = try await AnthropicClient(session: Self.stubSession()).streamMessage(
            body: ["model": "claude-sonnet-5-5"], apiKey: "sk-test"
        ) { await received.append($0) }

        let texts = await received.texts
        XCTAssertEqual(texts, ["Idée", " : trier", "."])
        XCTAssertEqual(completed.content, [["type": "text", "text": "Idée : trier."]])
        XCTAssertEqual(completed.stopReason, "end_turn")
    }

    func test_anHTTPErrorBecomesAnAPIFailure() async {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        StubProtocol.response = (401, [Data(body.utf8)])

        do {
            _ = try await AnthropicClient(session: Self.stubSession()).streamMessage(
                body: ["model": "claude-sonnet-5-5"], apiKey: "bad"
            ) { _ in }
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? APIFailure, APIFailure(type: "authentication_error", message: "invalid x-api-key"))
        }
    }

    func test_aStreamCutBeforeMessageStopIsAFailure() async {
        let stream = MessageStreamParserTests.textStream(deltas: ["Début"])
        let cut = stream.components(separatedBy: "event: x\ndata: {\"type\":\"message_stop\"}").first!
        StubProtocol.response = (200, [Data(cut.utf8)])

        do {
            _ = try await AnthropicClient(session: Self.stubSession()).streamMessage(
                body: ["model": "claude-sonnet-5-5"], apiKey: "sk-test"
            ) { _ in }
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual((error as? APIFailure)?.type, "incomplete_stream")
        }
    }

    func test_theTopicSegmenterReadsTheModelsStructuredDecision() async throws {
        let decision = #"{"action":"new","topic_id":"","title":"Complexité d'un arbre binaire"}"#
        let message = """
        {"type":"message","role":"assistant","stop_reason":"end_turn",
         "content":[{"type":"text","text":\(String(decoding: try JSONEncoder().encode(decision), as: UTF8.self))}]}
        """
        StubProtocol.response = (200, [Data(message.utf8)])
        let segmenter = ClaudeTopicSegmenter(client: AnthropicClient(session: Self.stubSession()), apiKey: "sk-test")

        let result = try await segmenter.decide(turn: Turn(speaker: .them, text: "Et un arbre binaire ?", start: 0, end: 2), topics: [], context: "")

        XCTAssertEqual(result, .new(title: "Complexité d'un arbre binaire"))
    }

    func test_aFailedNonStreamingCallBecomesAnAPIFailure() async {
        StubProtocol.response = (529, [Data(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8)])

        do {
            _ = try await AnthropicClient(session: Self.stubSession()).createMessage(body: ["model": "claude-haiku-5-5"], apiKey: "sk-test")
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? APIFailure, APIFailure(type: "overloaded_error", message: "Overloaded"))
        }
    }

    private static func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func chunks(of data: Data, size: Int) -> [Data] {
        stride(from: 0, to: data.count, by: size).map { data.subdata(in: $0..<min($0 + size, data.count)) }
    }
}

private actor TextCollector {
    private(set) var texts: [String] = []
    func append(_ text: String) { texts.append(text) }
}

private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (status: Int, chunks: [Data])?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let (status, chunks) = Self.response, let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["content-type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        chunks.forEach { client?.urlProtocol(self, didLoad: $0) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
