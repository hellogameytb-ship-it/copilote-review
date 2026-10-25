import Foundation

/// How Copilote speaks and takes notes, chosen in the pill (a default in the settings).
public enum MeetingMode: String, CaseIterable, Codable, Sendable {
    case meeting = "reunion"
    case technical = "technique"
    case friends = "potes"
    case presentation

    public var name: String {
        switch self {
        case .meeting: return "Meeting"
        case .technical: return "Technical"
        case .friends: return "Casual"
        case .presentation: return "Presentation"
        }
    }

    /// Added to every request made in this mode.
    public var tone: String {
        switch self {
        case .meeting: return "Professional and direct, with short natural spoken sentences."
        case .technical: return "Technically precise: correct terminology, complexity and trade-offs; no filler."
        case .friends: return "Relaxed, short and natural; avoid jargon."
        case .presentation: return "Brief, confident answers that connect back to my presentation."
        }
    }

    /// What an answer looks like in this mode (added to Répondre and Que dire).
    public var answerGuidance: String {
        switch self {
        case .meeting: return "Focus on decisions: what, who and when."
        case .technical: return "Be precise about complexity, trade-offs and edge cases; code only when useful."
        case .friends: return "Keep it light: two or three sentences, headings only for code."
        case .presentation: return "Answer in one or two sentences, then transition back to my presentation."
        }
    }

    /// What the end-of-meeting notes look for in this mode.
    public var notesFocus: String {
        switch self {
        case .meeting: return "Emphasize decisions, actions and owners."
        case .technical: return "Emphasize technical decisions, rationale and open questions."
        case .friends: return "Keep plans, dates and reminders; avoid meeting jargon."
        case .presentation: return "Emphasize audience questions and points to revisit."
        }
    }

    /// The sections of quick notes ("Session notes") in this mode.
    public var noteSections: [String] {
        switch self {
        case .meeting: return ["Key points", "Decisions", "Action items"]
        case .technical: return ["Technical points", "Decisions and trade-offs", "To verify"]
        case .friends: return ["Conversation", "Plans", "Reminders"]
        case .presentation: return ["Audience questions", "To revisit", "Reactions"]
        }
    }
}

/// The three actions on the current context.
public enum AssistAction: String, CaseIterable, Sendable {
    /// Complete, structured answer.
    case answer
    /// One sentence ready to say, and the likely follow-ups.
    case whatToSay
    /// Questions the user could ask them now (Cluely's "Follow-up questions").
    case questions
    /// Notes on the fly.
    case notes

    /// Répondre and Que dire put words in the user's mouth: never an opinion they did not write.
    public var speaksForTheUser: Bool { self == .answer || self == .whatToSay }

    public var name: String {
        switch self {
        case .answer: return "Refresh answer"
        case .whatToSay: return "Short version"
        case .questions: return "Suggest follow-ups"
        case .notes: return "Session notes"
        }
    }
}

/// Set once in the settings, sent with every request.
public struct AnswerPreferences: Equatable, Sendable {
    public enum Language: String, CaseIterable, Sendable {
        case auto, french, english

        public var name: String {
            switch self {
            case .auto: return "Match the question"
            case .french: return "French"
            case .english: return "English"
            }
        }
    }

    /// Who the user is talking to, about what, how to answer: "Entretien de stage SWE, réponses courtes".
    public var instructions: String
    public var language: Language

    public init(instructions: String = "", language: Language = .english) {
        self.instructions = instructions
        self.language = language
    }
}

/// An action on a case, on the last phrases, or on a typed question ("Demander").
public struct AssistQuestion: Equatable, Sendable {
    public let action: AssistAction
    public let mode: MeetingMode
    /// The case's title, or the typed question.
    public let question: String?
    /// What the others said about the case.
    public let heard: [String]
    public let context: AssistContext
    /// Typed by the user in "Demander".
    public let typed: Bool
    /// A case's kind of question: its own format (nil: the generic one).
    public let format: AnswerFormat?
    public var earlierAnswers = ""
    public var priorTypedRequests: [String] = []
    public var personalNotes: [String] = []
    public var webSources: [WebSource] = []
    public var webAttempted = false

    public init(
        action: AssistAction, mode: MeetingMode, question: String?, heard: [String], context: AssistContext,
        typed: Bool = false, format: AnswerFormat? = nil
    ) {
        self.action = action
        self.mode = mode
        self.question = question
        self.heard = heard
        self.context = context
        self.typed = typed
        self.format = format
    }
}
