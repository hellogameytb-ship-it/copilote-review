import Foundation

/// What the user sends with one shortcut.
public enum UserInput: Equatable, Sendable {
    case screenshots([CapturedImage])
    case clipboardText(String)
    case clipboardImage(CapturedImage)
    /// ⌥1-4 / ⌘↩: answer one of the topic cases.
    case topic(TopicQuestion)
    /// Répondre / Que dire / Notes, or a typed question, with the chosen context.
    case assist(AssistQuestion)
}

/// A topic case as sent to the model.
public struct TopicQuestion: Equatable, Sendable {
    public let title: String
    /// What the others said about it, turn by turn.
    public let excerpt: [String]
    /// The last minutes of the conversation, both speakers.
    public let context: String
    /// The capture stack, if the user had captured something.
    public let screenshots: [CapturedImage]
    /// Extracts of the personal base when the topic is about the user (see `BaseContext`).
    public let personal: [BaseSnippet]

    public init(title: String, excerpt: [String], context: String, screenshots: [CapturedImage], personal: [BaseSnippet] = []) {
        self.title = title
        self.excerpt = excerpt
        self.context = context
        self.screenshots = screenshots
        self.personal = personal
    }
}

/// The session's context: every turn since the last ⌘⇧X, in API wire format.
public struct Conversation: Equatable, Sendable {
    /// The turns as kept (the preferences are not in them).
    private var turns: [JSONValue] = []
    /// The meeting mode: its tone and the structured format join every new request.
    public var mode: MeetingMode?
    /// The user's standing context and the answers' language, with every request.
    public var preferences = AnswerPreferences()

    public init() {}

    public var isEmpty: Bool { turns.isEmpty }

    /// What goes out: the turns, the preferences joined to the last user turn only, so they don't
    /// pile up in the context and an edit applies to the next request.
    public var messages: [JSONValue] {
        guard let line = Prompts.preferences(preferences), let last = turns.last, last["role"] == "user",
              var content = last["content"]?.arrayValue, case let .string(text)? = content.last?["text"] else { return turns }
        content[content.count - 1] = ["type": "text", "text": .string(text + "\n\n" + line)]
        return turns.dropLast() + [["role": "user", "content": .array(content)]]
    }

    public mutating func appendUser(_ input: UserInput) {
        var content = Self.content(for: input)
        if let mode, let style = Prompts.style(for: input, mode: mode), case let .string(text)? = content.last?["text"] {
            content[content.count - 1] = ["type": "text", "text": .string(text + "\n\n" + style)]
        }
        turns.append(["role": "user", "content": .array(content)])
    }

    /// The assistant turn, content blocks exactly as streamed (see `MessageStreamParser.assistantContent`).
    public mutating func appendAssistant(content: [JSONValue]) {
        turns.append(["role": "assistant", "content": .array(content)])
    }

    public mutating func clear() {
        turns.removeAll()
    }

    private static func content(for input: UserInput) -> [JSONValue] {
        switch input {
        case let .screenshots(images):
            return images.map(imageBlock) + [textBlock(Prompts.screenshotsInstruction(count: images.count))]
        case let .clipboardText(text):
            return [textBlock(Prompts.clipboardTextInstruction(text))]
        case let .clipboardImage(image):
            return [imageBlock(image), textBlock(Prompts.clipboardImageInstruction)]
        case let .topic(question):
            return question.screenshots.map(imageBlock) + [textBlock(Prompts.topicInstruction(question))]
        case let .assist(question):
            return question.context.includedCaptures.map(imageBlock) + [textBlock(Prompts.assistInstruction(question))]
        }
    }

    static func imageBlock(_ image: CapturedImage) -> JSONValue {
        [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": .string(image.mediaType),
                "data": .string(image.data.base64EncodedString()),
            ],
        ]
    }

    private static func textBlock(_ text: String) -> JSONValue {
        ["type": "text", "text": .string(text)]
    }
}
