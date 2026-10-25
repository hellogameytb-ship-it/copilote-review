import Foundation

public enum Effort: String, CaseIterable, Sendable {
    case low, medium, high
}

public struct ModelSettings: Equatable, Sendable {
    public static let defaultModel = "claude-sonnet-5-5"

    public var model: String
    /// nil leaves the model's own default (some models, like Haiku 4.5, reject the parameter).
    public var effort: Effort?
    public var maxTokens: Int

    public init(model: String, effort: Effort? = .low, maxTokens: Int = 16_000) {
        self.model = model
        self.effort = effort
        self.maxTokens = maxTokens
    }
}

/// Builds the streaming Messages API request for the current conversation.
public enum MessageRequest {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public static func urlRequest(body: JSONValue, apiKey: String) throws -> URLRequest {
        var request = authorized(endpoint, apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Any Anthropic API request: key and API version headers.
    public static func authorized(_ url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return request
    }

    public static func body(for conversation: Conversation, settings: ModelSettings) -> JSONValue {
        var fields: [String: JSONValue] = [
            "model": .string(settings.model),
            "max_tokens": .int(settings.maxTokens),
            "stream": true,
            "system": .string(Prompts.system),
            "messages": .array(conversation.messages),
            // Automatic caching: follow-ups reuse the already-processed screenshots.
            "cache_control": ["type": "ephemeral"],
        ]
        if supportsBetweenToolsThinking(settings.model) {
            // Sonnet 5.5's lowest thinking setting: no up-front thinking, so text starts at once.
            fields["thinking"] = ["type": "between_tools"]
        }
        if let effort = settings.effort {
            fields["output_config"] = ["effort": .string(effort.rawValue)]
        }
        return .object(fields)
    }

    /// A single non-streamed request with its own system prompt (offline batches).
    public static func completionBody(
        system: String, prompt: String, images: [CapturedImage], schema: JSONValue? = nil, settings: ModelSettings
    ) -> JSONValue {
        var fields: [String: JSONValue] = [
            "model": .string(settings.model),
            "max_tokens": 4096,
            "system": .string(system),
            "messages": [["role": "user", "content": .array(images.map(Conversation.imageBlock) + [["type": "text", "text": .string(prompt)]])]],
        ]
        if supportsBetweenToolsThinking(settings.model) { fields["thinking"] = ["type": "between_tools"] }
        var output: [String: JSONValue] = [:]
        if let effort = settings.effort { output["effort"] = .string(effort.rawValue) }
        if let schema { output["format"] = ["type": "json_schema", "schema": schema] }
        if !output.isEmpty { fields["output_config"] = .object(output) }
        return .object(fields)
    }

    private static func supportsBetweenToolsThinking(_ model: String) -> Bool {
        model == "claude-sonnet-5-5"
    }
}
