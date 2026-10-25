import Foundation

/// Topic segmentation by Claude Haiku 5.5 (see `TopicRequest`).
public struct ClaudeTopicSegmenter: TopicSegmenter {
    private let client: AnthropicClient
    private let apiKey: String

    public init(client: AnthropicClient, apiKey: String) {
        self.client = client
        self.apiKey = apiKey
    }

    public func decide(turn: Turn, topics: [Topic], context: String) async throws -> TopicDecision {
        let response = try await client.createMessage(body: TopicRequest.body(turn: turn, topics: topics, context: context), apiKey: apiKey)
        return try TopicDecision(response: response)
    }
}
