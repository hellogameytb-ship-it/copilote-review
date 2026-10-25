import Foundation

/// Turns a conversation (Messages API format) into the input of one Codex turn.
public enum CodexPrompt {
    public static func turnInput(for conversation: Conversation) -> [JSONValue] {
        guard let last = conversation.messages.last?["content"]?.arrayValue else { return [] }
        let earlier = Array(conversation.messages.dropLast())
        guard !earlier.isEmpty else { return last.compactMap(inputItem) }
        // Earlier captures are attached again (numbered in the transcript), like the Messages API history.
        var earlierImages: [JSONValue] = []
        var lines: [String] = []
        for message in earlier {
            let blocks = message["content"]?.arrayValue ?? []
            var parts: [String] = []
            for block in blocks where block["type"] == "image" {
                if let image = inputItem(block) {
                    earlierImages.append(image)
                    parts.append("[screenshot \(earlierImages.count) attached]")
                }
            }
            parts += blocks.filter { $0["type"] == "text" }.compactMap { $0["text"]?.stringValue }
            let speaker = message["role"]?.stringValue == "assistant" ? "Copilote" : "Me"
            lines.append("\(speaker) : " + parts.joined(separator: " "))
        }
        let history: JSONValue = ["type": "text", "text": .string("Earlier exchanges:\n" + lines.joined(separator: "\n"))]
        return earlierImages + [history] + last.compactMap(inputItem)
    }

    private static func inputItem(_ block: JSONValue) -> JSONValue? {
        switch block["type"]?.stringValue {
        case "text":
            return ["type": "text", "text": block["text"] ?? ""]
        case "image":
            guard let media = block["source"]?["media_type"]?.stringValue, let data = block["source"]?["data"]?.stringValue else { return nil }
            return ["type": "image", "url": .string("data:\(media);base64,\(data)")]
        default:
            return nil
        }
    }
}
