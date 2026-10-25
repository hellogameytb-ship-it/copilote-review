import Foundation

/// Notes after the meeting, in five sections. Every item comes with a verbatim quote of the
/// transcript; items whose quote is not found are dropped: nothing invented.
public struct MeetingNotes: Equatable, Sendable, Codable {
    public struct Item: Equatable, Sendable, Codable {
        public let text: String
        public let evidence: String
    }

    public struct Action: Equatable, Sendable, Codable {
        public let text: String
        public let owner: String?
        public let evidence: String
    }

    public let title: String
    public let keyPoints: [Item]
    public let decisions: [Item]
    public let actions: [Action]
    public let openQuestions: [Item]
    public let nextSteps: [Item]

    /// The five sections, actions as boxes to tick.
    public var markdown: String {
        func section(_ title: String, _ lines: [String]) -> String {
            "## \(title)\n" + (lines.isEmpty ? "_None._" : lines.joined(separator: "\n"))
        }
        return [
            section("Key points", keyPoints.map { "- \($0.text)" }),
            section("Decisions", decisions.map { "- \($0.text)" }),
            section("Actions", actions.map { "- [ ] \($0.label)" }),
            section("Open questions", openQuestions.map { "- \($0.text)" }),
            section("Next steps", nextSteps.map { "- \($0.text)" }),
        ].joined(separator: "\n\n")
    }

    /// Written from the kept notes only (no free text from the model), in the mode's tone.
    public func email(mode: MeetingMode) -> FollowUpEmail {
        let casual = mode == .friends
        var body = [casual ? "Hi," : "Hello,", "", casual ? "Thanks for the chat! Here are my takeaways:" : "Thank you for the discussion. Here are my takeaways:"]
        let retained = decisions.isEmpty ? keyPoints : decisions
        body += retained.isEmpty ? ["- (no decisions yet)"] : retained.map { "- \($0.text)" }
        if !actions.isEmpty { body += ["", "Next steps:"] + actions.map { "- \($0.label)" } }
        if !openQuestions.isEmpty { body += ["", "Open questions:"] + openQuestions.map { "- \($0.text)" } }
        if !nextSteps.isEmpty { body += ["", "Then:"] + nextSteps.map { "- \($0.text)" } }
        body += ["", casual ? "See you," : "Best,"]
        let subject = title.isEmpty ? "Follow-up" : "Follow-up: \(title)"
        return FollowUpEmail(subject: subject, body: body.joined(separator: "\n"))
    }
}

extension MeetingNotes.Action {
    /// "Préparer la démo (Moi)".
    var label: String { owner.map { "\(text) (\($0))" } ?? text }
}

public struct FollowUpEmail: Equatable, Sendable, Codable {
    public let subject: String
    public let body: String

    /// What "Copier l'e-mail" puts on the clipboard.
    public var text: String { "Subject: \(subject)\n\n\(body)" }
}

/// What the end of a meeting produces: the notes, their email, the optional self-review, and the
/// user's diction (computed locally).
public struct MeetingReport: Equatable, Sendable {
    public let notes: MeetingNotes
    public let email: FollowUpEmail
    public let review: SelfReview?
    public let stats: SpeechStats?

    public init(notes: MeetingNotes, email: FollowUpEmail, review: SelfReview?, stats: SpeechStats? = nil) {
        self.notes = notes
        self.email = email
        self.review = review
        self.stats = stats
    }
}

public enum MeetingNotesRequest {
    public static let system = """
    Write meeting notes in English from the transcript. Never invent facts. Each item must supply
    a verbatim transcript quote in "preuve" as evidence; omit anything with no supporting quote.
    Preserve the schema's JSON keys; write titles and descriptions in English, keeping quotes verbatim.
    """

    public static func prompt(transcript: [TranscriptLine], mode: MeetingMode) -> String {
        """
        Mode: \(mode.name). \(mode.notesFocus)
        Transcript (Me = user, Them = other participants):
        \(transcript.map(\.labeled).joined(separator: "\n"))

        Return JSON using the supplied schema: a 3–8 word English title, key points, decisions,
        actions ("qui" = owner or empty if unknown), open questions and next steps.
        For each item, "preuve" is an exact consecutive quote from the transcript. Lists may be empty.
        """
    }

    static let item: JSONValue = [
        "type": "object",
        "properties": ["texte": ["type": "string"], "preuve": ["type": "string"]],
        "required": ["texte", "preuve"],
        "additionalProperties": false,
    ]

    public static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "titre": ["type": "string"],
            "points_cles": ["type": "array", "items": item],
            "decisions": ["type": "array", "items": item],
            "actions": ["type": "array", "items": [
                "type": "object",
                "properties": ["texte": ["type": "string"], "qui": ["type": "string"], "preuve": ["type": "string"]],
                "required": ["texte", "qui", "preuve"],
                "additionalProperties": false,
            ]],
            "questions_ouvertes": ["type": "array", "items": item],
            "suite": ["type": "array", "items": item],
        ],
        "required": ["titre", "points_cles", "decisions", "actions", "questions_ouvertes", "suite"],
        "additionalProperties": false,
    ]

    /// The model's JSON (French keys, as the schema asks).
    private struct Answer: Decodable {
        struct Item: Decodable {
            let text: String
            let evidence: String
            let owner: String?

            enum CodingKeys: String, CodingKey {
                case text = "texte", evidence = "preuve", owner = "qui"
            }
        }

        let title: String
        let keyPoints: [Item]
        let decisions: [Item]
        let actions: [Item]
        let openQuestions: [Item]
        let nextSteps: [Item]

        enum CodingKeys: String, CodingKey {
            case title = "titre", keyPoints = "points_cles", decisions, actions, openQuestions = "questions_ouvertes", nextSteps = "suite"
        }
    }

    public static func notes(fromJSON text: String, transcript: [TranscriptLine]) throws -> MeetingNotes {
        let answer = try JSONDecoder().decode(Answer.self, from: Data(JSONText.object(in: text).utf8))
        let said = Quotes(transcript.map(\.text))
        func kept(_ items: [Answer.Item]) -> [MeetingNotes.Item] {
            items.filter { said.contains($0.evidence) }.map { MeetingNotes.Item(text: $0.text, evidence: $0.evidence) }
        }
        return MeetingNotes(
            title: answer.title.trimmingCharacters(in: .whitespacesAndNewlines),
            keyPoints: kept(answer.keyPoints),
            decisions: kept(answer.decisions),
            actions: answer.actions.filter { said.contains($0.evidence) }.map {
                let owner = $0.owner?.trimmingCharacters(in: .whitespaces) ?? ""
                return MeetingNotes.Action(text: $0.text, owner: owner.isEmpty ? nil : owner, evidence: $0.evidence)
            },
            openQuestions: kept(answer.openQuestions),
            nextSteps: kept(answer.nextSteps)
        )
    }
}

/// Optional (off by default): a review of what the user said ("Moi" channel only).
public struct SelfReview: Equatable, Sendable, Codable {
    public struct Rephrasing: Equatable, Sendable, Codable {
        public let original: String
        public let better: String

        public init(original: String, better: String) {
            self.original = original
            self.better = better
        }
    }

    public let strengths: [String]
    public let improvements: [String]
    /// Only for phrases the user actually said.
    public let rephrasings: [Rephrasing]

    public init(strengths: [String], improvements: [String], rephrasings: [Rephrasing]) {
        self.strengths = strengths
        self.improvements = improvements
        self.rephrasings = rephrasings
    }

    public var markdown: String {
        func list(_ items: [String]) -> String { items.isEmpty ? "_None._" : items.map { "- \($0)" }.joined(separator: "\n") }
        let clearer = rephrasings.isEmpty ? "_None._" : rephrasings.map { "- « \($0.original) » → \($0.better)" }.joined(separator: "\n")
        return "## Strengths\n\(list(strengths))\n\n## To improve\n\(list(improvements))\n\n## Clearer wording\n\(clearer)"
    }
}

public enum SelfReviewRequest {
    public static let system = """
    Help the user improve their spoken answers. Review only their own statements, kindly and precisely.
    Respond in English. Each rephrasing must quote their exact words in "original"; preserve the JSON schema keys.
    """

    public static func prompt(transcript: [TranscriptLine]) -> String {
        """
        My statements during the meeting:
        \(transcript.filter { $0.speaker == .me }.map { "- \($0.text)" }.joined(separator: "\n"))
        Return JSON: 2–3 strengths, 2–3 improvements, and up to 3 clearer rephrasings, in English.
        """
    }

    public static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "points_forts": ["type": "array", "items": ["type": "string"]],
            "a_ameliorer": ["type": "array", "items": ["type": "string"]],
            "reformulations": ["type": "array", "items": [
                "type": "object",
                "properties": ["original": ["type": "string"], "mieux": ["type": "string"]],
                "required": ["original", "mieux"],
                "additionalProperties": false,
            ]],
        ],
        "required": ["points_forts", "a_ameliorer", "reformulations"],
        "additionalProperties": false,
    ]

    /// The model's JSON (French keys, as the schema asks).
    private struct Answer: Decodable {
        struct Rephrasing: Decodable {
            let original: String
            let better: String

            enum CodingKeys: String, CodingKey {
                case original, better = "mieux"
            }
        }

        let strengths: [String]
        let improvements: [String]
        let rephrasings: [Rephrasing]

        enum CodingKeys: String, CodingKey {
            case strengths = "points_forts", improvements = "a_ameliorer", rephrasings = "reformulations"
        }
    }

    public static func review(fromJSON text: String, transcript: [TranscriptLine]) throws -> SelfReview {
        let answer = try JSONDecoder().decode(Answer.self, from: Data(JSONText.object(in: text).utf8))
        let mine = Quotes(transcript.filter { $0.speaker == .me }.map(\.text))
        return SelfReview(
            strengths: answer.strengths,
            improvements: answer.improvements,
            rephrasings: answer.rephrasings.filter { mine.contains($0.original) }.map { .init(original: $0.original, better: $0.better) }
        )
    }
}

/// Is a quote really in what was said? Compared word by word, accents and punctuation aside.
struct Quotes {
    private let said: String

    init(_ lines: [String]) {
        said = " " + lines.map { BaseText.tokens(of: $0).joined(separator: " ") }.joined(separator: " | ") + " "
    }

    func contains(_ quote: String) -> Bool {
        let words = BaseText.tokens(of: quote)
        guard words.count >= 2 else { return false }
        return said.contains(" " + words.joined(separator: " ") + " ")
    }
}

/// The JSON object in a model's answer (a fenced block or bare).
enum JSONText {
    static func object(in text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return text }
        return String(text[start...end])
    }
}

extension LLMProvider {
    /// The notes of a session through this provider (JSON answer, then checked against the transcript).
    public func meetingNotes(transcript: [TranscriptLine], mode: MeetingMode) async throws -> MeetingNotes {
        let answer = try await complete(
            system: MeetingNotesRequest.system, prompt: MeetingNotesRequest.prompt(transcript: transcript, mode: mode),
            images: [], schema: MeetingNotesRequest.schema
        )
        return try MeetingNotesRequest.notes(fromJSON: answer, transcript: transcript)
    }

    public func selfReview(transcript: [TranscriptLine]) async throws -> SelfReview {
        let answer = try await complete(
            system: SelfReviewRequest.system, prompt: SelfReviewRequest.prompt(transcript: transcript),
            images: [], schema: SelfReviewRequest.schema
        )
        return try SelfReviewRequest.review(fromJSON: answer, transcript: transcript)
    }
}
