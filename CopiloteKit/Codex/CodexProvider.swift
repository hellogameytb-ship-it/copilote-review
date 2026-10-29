import Foundation

/// Answers and topic decisions through the `codex` CLI and the user's ChatGPT subscription.
public struct CodexProvider: LLMProvider {
    /// The fastest model listed for ChatGPT accounts (Oct. 2026); `gpt-5.6-sol` is the alternative.
    public static let defaultModel = "gpt-5.6-luna"

    private let server: CodexAppServer
    private let answerModel: String
    private let topicModel: String
    /// "priority" (Codex's "Fast": 1.5× speed, more usage) or nil for the standard tier.
    private let serviceTier: String?

    public init(server: CodexAppServer, answerModel: String, topicModel: String, serviceTier: String?) {
        self.server = server
        self.answerModel = answerModel
        self.topicModel = topicModel
        self.serviceTier = serviceTier
    }

    public var kind: ProviderKind { .codex }
    public var label: String { "Codex · \(answerModel)" }

    public var topicSegmenter: any TopicSegmenter {
        CodexTopicSegmenter(server: server, model: topicModel, serviceTier: serviceTier)
    }

    public var topicSegmenterName: String { "Codex · \(topicModel)" }

    public func streamAnswer(to conversation: Conversation, onText: @escaping @Sendable (String) async -> Void) async throws -> CompletedMessage {
        let request = CodexAppServer.TurnRequest(
            model: answerModel, serviceTier: serviceTier, instructions: Prompts.system, input: CodexPrompt.turnInput(for: conversation), work: CodexRequestContext.work
        )
        let text = try await server.run(request, onText: onText)
        return CompletedMessage(content: text.isEmpty ? [] : [["type": "text", "text": .string(text)]], stopReason: "end_turn")
    }

    public func warmUp() async {
        try? await server.start()
    }

    public func complete(system: String, prompt: String, images: [CapturedImage], schema: JSONValue?) async throws -> String {
        let input: [JSONValue] = images.map { ["type": "image", "url": .string("data:\($0.mediaType);base64,\($0.data.base64EncodedString())")] }
            + [["type": "text", "text": .string(prompt)]]
        return try await server.run(
            CodexAppServer.TurnRequest(model: answerModel, serviceTier: serviceTier, instructions: system, input: input, outputSchema: schema, work: CodexRequestContext.work == .manual ? .completion : CodexRequestContext.work)
        ) { _ in }
    }
}

/// Topic decisions by Codex, with the same prompt and JSON schema as the Claude segmenter.
public struct CodexTopicSegmenter: TopicSegmenter {
    let server: CodexAppServer
    let model: String
    let serviceTier: String?

    public var coalescesPendingTurns: Bool { true }

    public func decide(turn: Turn, topics: [Topic], context: String) async throws -> TopicDecision {
        let request = CodexAppServer.TurnRequest(
            model: model, serviceTier: serviceTier, instructions: TopicRequest.system,
            input: [["type": "text", "text": .string(TopicRequest.prompt(turn: turn, topics: topics, context: context))]],
            outputSchema: TopicRequest.schema,
            // A late decision is worthless: the keyword fallback takes over.
            timeout: .seconds(15), work: .grouping
        )
        return try await TopicDecision(decisionText: server.run(request) { _ in })
    }
}
