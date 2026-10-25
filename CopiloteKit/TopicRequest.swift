import Foundation

/// The fast "which topic is this turn about?" call: Haiku 5.5, no thinking, low effort,
/// structured output. A few hundred input tokens per turn at $0.10 / MTok.
public enum TopicRequest {
    public static let model = "claude-haiku-5-5"

    public static let system = """
    Split an interview into subjects that the user can respond to. For the interviewer's new turn:
    - new: a distinct question, instruction or substantive assertion;
    - continue: a follow-up, clarification or return to a displayed subject, with that subject's id;
    - ignore: greetings, acknowledgement or small talk requiring no answer.
    Implicit requests count: "Present your projects", "Which stack", "Then measure this".
    Keep the stack of a named project on that project's card, even if another subject is newer.
    A separate estimation or measurement task opens its own card; a refinement stays on that card.
    Use the user's own statements as context, never as new interviewer questions.
    Titles must be concise English (5–8 words), regardless of the spoken language.
    For continue, provide an updated title or an empty string; for ignore, an empty string.
    """

    public static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "action": ["type": "string", "enum": ["new", "continue", "ignore"]],
            "topic_id": ["type": "string"],
            "title": ["type": "string"],
        ],
        "required": ["action", "topic_id", "title"],
        "additionalProperties": false,
    ]

    public static func body(turn: Turn, topics: [Topic], context: String) -> JSONValue {
        [
            "model": .string(model),
            "max_tokens": 256,
            "system": .string(system),
            "messages": [["role": "user", "content": .string(prompt(turn: turn, topics: topics, context: context))]],
            "thinking": ["type": "disabled"],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
        ]
    }

    /// The user message, shared by every provider.
    public static func prompt(turn: Turn, topics: [Topic], context: String) -> String {
        let shown = topics.isEmpty
            ? "(none)"
            : topics.map { "- \($0.id) · \($0.title) · latest excerpt : « \($0.excerpt.last ?? "") »" }.joined(separator: "\n")
        return """
        Displayed subjects, newest first:
        \(shown)

        Conversation context:
        \(context.isEmpty ? "(none)" : context)

        New interviewer turn:
        « \(turn.text) »
        """
    }
}
