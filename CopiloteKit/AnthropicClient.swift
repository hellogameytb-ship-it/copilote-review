import Foundation

/// The assistant turn once the stream has ended.
public struct CompletedMessage: Sendable {
    public let content: [JSONValue]
    public let stopReason: String?
    public init(content: [JSONValue], stopReason: String?) { self.content = content; self.stopReason = stopReason }
}

/// Streams a Messages API response over URLSession.
public final class AnthropicClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = AnthropicClient.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    /// Calls `onText` for every text delta, in order, and returns the full assistant turn.
    /// Throws `APIFailure` for API errors (HTTP or mid-stream) and `CancellationError` when cancelled.
    public func streamMessage(
        body: JSONValue,
        apiKey: String,
        onText: @escaping @Sendable (String) async -> Void
    ) async throws -> CompletedMessage {
        let request = try MessageRequest.urlRequest(body: body, apiKey: apiKey)
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var errorBody = Data()
            for try await byte in bytes { errorBody.append(byte) }
            throw APIFailure(httpStatus: status, body: errorBody)
        }

        var parser = MessageStreamParser()
        var stopReason: String?
        var finished = false
        func handle(_ updates: [StreamUpdate]) async throws {
            for update in updates {
                switch update {
                case let .text(text): await onText(text)
                case let .finished(reason): stopReason = reason; finished = true
                case let .failed(failure): throw failure
                }
            }
        }

        var line = Data()
        for try await byte in bytes {
            line.append(byte)
            if byte == UInt8(ascii: "\n") {
                try await handle(parser.feed(line))
                line.removeAll(keepingCapacity: true)
            }
        }
        try await handle(parser.feed(line) + parser.finish())
        try Task.checkCancellation()
        guard finished else {
            throw APIFailure(type: "incomplete_stream", message: "connection closed before the answer was complete")
        }
        return CompletedMessage(content: parser.assistantContent, stopReason: stopReason)
    }

    /// A non-streaming call (short structured answers), returning the message as JSON.
    public func createMessage(body: JSONValue, apiKey: String) async throws -> JSONValue {
        let request = try MessageRequest.urlRequest(body: body, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIFailure(httpStatus: status, body: data) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Opens the TLS connection ahead of the first real request (free endpoint, result ignored).
    public func warmUp(apiKey: String) async {
        let request = MessageRequest.authorized(URL(string: "https://api.anthropic.com/v1/models?limit=1")!, apiKey: apiKey)
        _ = try? await session.data(for: request)
    }
}
