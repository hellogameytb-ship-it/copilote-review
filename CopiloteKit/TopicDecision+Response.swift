import Foundation

public struct TopicDecisionError: Error, Equatable {
    public let reason: String
}

extension TopicDecision {
    /// Long enough for 5-8 words, short enough for one case.
    public static let maxTitleLength = 70

    /// Reads the segmenter's structured output from a Messages API response.
    public init(response: JSONValue) throws {
        let text = response["content"]?.arrayValue?.first { $0["type"] == "text" }?["text"]?.stringValue
        try self.init(decisionText: text ?? "")
    }

    /// Reads the structured output itself: `{"action": …, "topic_id": …, "title": …}`.
    public init(decisionText text: String) throws {
        guard let decision = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else {
            throw TopicDecisionError(reason: "no JSON decision in the response")
        }
        let title = Self.clamp(decision["title"]?.stringValue ?? "")
        let id = decision["topic_id"]?.stringValue ?? ""
        switch decision["action"]?.stringValue {
        case "continue" where !id.isEmpty:
            self = .continueTopic(id: id, title: title)
        case "new", "continue":
            self = title.isEmpty ? .ignore : .new(title: title)
        default:
            self = .ignore
        }
    }

    private static func clamp(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxTitleLength else { return trimmed }
        return trimmed.prefix(maxTitleLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
