import Foundation

/// The service that answers (streaming) and segments topics.
public protocol LLMProvider: Sendable {
    var kind: ProviderKind { get }
    /// Shown to the user: "Codex · gpt-5.6-luna", "Anthropic · claude-sonnet-5-5".
    var label: String { get }
    var topicSegmenter: any TopicSegmenter { get }
    /// Shown next to the topic decisions, e.g. "Codex · gpt-5.6-luna", "claude-haiku-5-5".
    var topicSegmenterName: String { get }
    /// `conversation` ends with the new user turn.
    func streamAnswer(to conversation: Conversation, onText: @escaping @Sendable (String) async -> Void) async throws -> CompletedMessage
    /// Gets the connection (or the Codex process) ready before the first request.
    func warmUp() async
    /// One request outside the conversation (diagrams, captions, notes); `schema`: a JSON answer.
    func complete(system: String, prompt: String, images: [CapturedImage], schema: JSONValue?) async throws -> String
}

extension LLMProvider {
    public func complete(system: String, prompt: String, images: [CapturedImage]) async throws -> String {
        try await complete(system: system, prompt: prompt, images: images, schema: nil)
    }
}

/// The Messages API with the key from the Keychain (step 1 client, unchanged).
public struct AnthropicProvider: LLMProvider {
    private let client: AnthropicClient
    private let apiKey: String
    private let settings: ModelSettings

    public init(client: AnthropicClient, apiKey: String, settings: ModelSettings) {
        self.client = client
        self.apiKey = apiKey
        self.settings = settings
    }

    public var kind: ProviderKind { .anthropic }
    public var label: String { "Anthropic · \(settings.model)" }
    public var topicSegmenter: any TopicSegmenter { ClaudeTopicSegmenter(client: client, apiKey: apiKey) }
    public var topicSegmenterName: String { TopicRequest.model }

    public func streamAnswer(to conversation: Conversation, onText: @escaping @Sendable (String) async -> Void) async throws -> CompletedMessage {
        try await client.streamMessage(body: MessageRequest.body(for: conversation, settings: settings), apiKey: apiKey, onText: onText)
    }

    public func warmUp() async {
        await client.warmUp(apiKey: apiKey)
    }

    public func complete(system: String, prompt: String, images: [CapturedImage], schema: JSONValue?) async throws -> String {
        let message = try await client.createMessage(
            body: MessageRequest.completionBody(system: system, prompt: prompt, images: images, schema: schema, settings: settings), apiKey: apiKey
        )
        return (message["content"]?.arrayValue ?? []).compactMap { $0["type"] == "text" ? $0["text"]?.stringValue : nil }.joined()
    }
}
