import Foundation

/// How a case is answered (step 4b), from the kind of question heard.
public struct AnswerFormat: Equatable, Sendable {
    public let kind: QuestionKind
    /// "Un projet qui t'a mis sous pression": situation → ce que j'ai fait → résultat → ce que j'en retiens.
    public let isBehavioural: Bool
    /// "Les ventes en 2027": a projection, never a known figure.
    public let asksAboutTheFuture: Bool

    public init(kind: QuestionKind, isBehavioural: Bool = false, asksAboutTheFuture: Bool = false) {
        self.kind = kind
        self.isBehavioural = isBehavioural
        self.asksAboutTheFuture = asksAboutTheFuture
    }

    public init(question: String, today: CalendarDay = .today()) {
        let kind = QuestionKind(question: question, today: today)
        self.init(
            kind: kind,
            isBehavioural: kind == .personal && QueryIntent(question: question, today: today).isBehavioral,
            asksAboutTheFuture: QuestionKind.asksAboutTheFuture(question, today: today)
        )
    }
}

/// A case's format and the extracts of the base it may rest on: avis.md alone for an opinion,
/// what the search finds about the user (fiches, stories) for anything else.
public struct AnswerPlan: Equatable, Sendable {
    public let format: AnswerFormat
    public let extracts: [BaseSnippet]

    public init(format: AnswerFormat, extracts: [BaseSnippet]) {
        self.format = format
        self.extracts = extracts
    }

    /// Small talk and statements are answered only when the user asks.
    public var isWorthDrafting: Bool { format.kind != .none }

    /// The last two turns heard tell the kind: a follow-up alone ("et pourquoi ?") says too little.
    public static func make(heard: [String], base: PersonalBase?, conversation: [TranscriptLine] = [], interviewEvidence: InterviewEvidenceStore? = nil, episode: EpisodeReference? = nil, technicalInterview: Bool = false, today: CalendarDay = .today()) async -> AnswerPlan {
        guard heard.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return AnswerPlan(format: AnswerFormat(kind: .none), extracts: [])
        }
        if EpisodeReference.isFollowUp(heard.joined(separator: "\n")) {
            let format = AnswerFormat(kind: .personal)
            guard let episode else { return AnswerPlan(format: format, extracts: []) }
            let privateRefs = episode.extracts.filter { $0.interviewRevision != nil }
            let verified = privateRefs.isEmpty ? [] : interviewEvidence?.revalidated(privateRefs) ?? []
            let localRefs = episode.extracts.filter { $0.interviewRevision == nil }
            let local = localRefs.isEmpty ? [] : (try? await base?.search.revalidated(localRefs, lookup: episode.lookup)) ?? []
            return AnswerPlan(format: format, extracts: verified + local)
        }
        if technicalInterview || interviewEvidence != nil, let focus = InterviewFocus.resolve(heard: heard, conversation: conversation) {
            let format = AnswerFormat(kind: .personal)
            if let preferred = interviewEvidence?.snippets(for: focus), !preferred.isEmpty {
                return AnswerPlan(format: format, extracts: preferred)
            }
            let local = try? await base?.search.interviewSnippet(for: focus)
            return AnswerPlan(format: format, extracts: local.map { [$0] } ?? [])

        }
        var heard = heard
        let latest = heard.last?.lowercased() ?? ""
        if latest.split(separator: " ").count < 16,
           ["stack", "measure", "metric", "technolog", "result", "this project", "that project"].contains(where: latest.contains) {
            let preceding = conversation.suffix(8).map(\.text).filter { !heard.contains($0) }
            heard = preceding + heard
        }
        let question = heard.suffix(2).joined(separator: " ")
        let format = AnswerFormat(question: question, today: today)
        if let interviewEvidence {
            let current = InterviewEvidenceStore.currentQuestion(heard)
            let preferred = interviewEvidence.snippets(for: current)
            if !preferred.isEmpty {
                let format = AnswerFormat(kind: .personal, isBehavioural: QueryIntent(question: current, today: today).isBehavioral)
                return AnswerPlan(format: format, extracts: preferred)
            }
            // A new general question in a long exchange must not inherit a biographical lookup.
            if current != question && !QueryIntent(question: current, today: today).isPersonal,
               QuestionKind(question: current, today: today) != .opinion {
                return AnswerPlan(format: AnswerFormat(question: current, today: today), extracts: [])
            }
        }
        guard let base else { return AnswerPlan(format: format, extracts: []) }
        let extracts = format.kind == .opinion
            ? await base.opinions(for: question)
            : await base.snippets(for: heard.joined(separator: "\n"), today: today)
        return AnswerPlan(format: format, extracts: extracts)
    }
}

extension AssistQuestion {
    /// An opinion question with nothing from avis.md going with it: neutral angles only.
    public var isOpinionMissing: Bool {
        format?.kind == .opinion && context.includedExtracts.isEmpty
    }

    /// The answer Copilote drafts by itself for a case (app and replay alike): the kind's format,
    /// the extracts the plan allows, the recent phrases.
    public static func draft(for topic: Topic, plan: AnswerPlan, lines: [TranscriptLine], mode: MeetingMode) -> AssistQuestion {
        let context = AssistContext(lines: lines, captures: [], extracts: plan.extracts)
        return AssistQuestion(action: .answer, mode: mode, question: topic.title, heard: topic.excerpt, context: context, format: plan.format)
    }
}
