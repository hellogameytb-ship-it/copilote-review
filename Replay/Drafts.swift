import CopiloteKit
import Foundation

/// The drafted answer to case 1, as the app does it (`ListeningController.answerAutomatically`,
/// `SessionController`): `AutoAnswerPolicy` → `AnswerPlan` → one generation at a time, with a
/// fresh conversation each time (automatic answers stay out of it). A newer draft replaces the
/// one in flight only once it starts; a withdrawn case cancels only its own. Times are counted
/// from the end of the others' turn and from their last syllable.
actor Drafter {
    struct Draft {
        let topic: String
        let kind: String
        let firstWord: Double
        let complete: Double
        let sinceVoice: Double
        let invented: String?
    }

    private let provider: any LLMProvider
    private let base: PersonalBase?
    private let today: CalendarDay
    private let audioStart: ContinuousClock.Instant
    private let speed: Double
    private var policy = AutoAnswerPolicy()
    /// Looking up the plan of the latest case 1 (cancelled by a newer one, like the app's `drafting`).
    private var planning: Task<Void, Never>?
    /// The answer streaming, and the case it answers.
    private var streaming: (topicID: String, task: Task<Void, Never>)?
    private var lines: [TranscriptLine] = []
    /// Turn start → when its end was heard.
    private var heard: [TimeInterval: ContinuousClock.Instant] = [:]
    private var drafts: [Draft] = []
    private var cancelled = 0

    init(provider: any LLMProvider, base: PersonalBase?, today: CalendarDay, audioStart: ContinuousClock.Instant, speed: Double) {
        self.provider = provider
        self.base = base
        self.today = today
        self.audioStart = audioStart
        self.speed = speed
    }

    func handle(_ event: ListeningEvent, at instant: ContinuousClock.Instant) {
        switch event {
        case let .line(line, _, _):
            lines.append(line)
        case let .turn(turn) where turn.speaker == .them:
            heard[turn.start] = instant
        case let .topics(update):
            switch policy.react(to: update.topics, change: update.change, userIsAnswering: false) {
            case .keep:
                break
            case .cancel:
                planning?.cancel()
                if case let .withdrawn(id) = update.change, streaming?.topicID == id { streaming?.task.cancel() }
            case let .start(topic):
                planning?.cancel()
                let turn = update.turn
                let reference = turn.flatMap { heard[$0.start] } ?? instant
                let voiceEnded = turn.map { audioInstant(audioStart, $0.end, speed: speed) } ?? instant
                let lines = lines
                planning = Task {
                    let plan = await AnswerPlan.make(heard: topic.excerpt, base: base, today: today)
                    guard plan.isWorthDrafting, TurnCompletion.requestsAnswer(topic.excerpt.last ?? topic.title), !Task.isCancelled else { return }
                    await self.start(topic, plan: plan, lines: lines, since: reference, voiceEnded: voiceEnded)
                }
            }
        default:
            break
        }
    }

    /// The last draft, to its end.
    func finish() async {
        await planning?.value
        await streaming?.task.value
    }

    private func start(_ topic: Topic, plan: AnswerPlan, lines: [TranscriptLine], since reference: ContinuousClock.Instant, voiceEnded: ContinuousClock.Instant) {
        streaming?.task.cancel()
        streaming = (topic.id, Task { await self.draft(topic, plan: plan, lines: lines, since: reference, voiceEnded: voiceEnded) })
    }

    private func draft(_ topic: Topic, plan: AnswerPlan, lines: [TranscriptLine], since reference: ContinuousClock.Instant, voiceEnded: ContinuousClock.Instant) async {
        let question = AssistQuestion.draft(for: topic, plan: plan, lines: lines, mode: .meeting)
        var conversation = Conversation()
        conversation.appendUser(.assist(question))
        let kind = Self.describe(plan, question)
        let first = FirstWord()
        do {
            let answer = try await provider.streamAnswer(to: conversation) { _ in await first.mark(reference) }
            try Task.checkCancellation()
            let text = answer.content.compactMap { $0["text"]?.stringValue }.joined()
            let draft = Draft(
                topic: topic.title, kind: kind, firstWord: await first.value ?? 0,
                complete: (ContinuousClock.now - reference).seconds, sinceVoice: (ContinuousClock.now - voiceEnded).seconds,
                invented: question.isOpinionMissing ? OpinionGuard.firstPersonOpinion(in: text) : nil
            )
            drafts.append(draft)
            let check = question.isOpinionMissing ? (draft.invented.map { " · ⚠️ avis inventé : « \($0) »" } ?? " · aucun avis inventé") : ""
            let sources = plan.extracts.isEmpty ? "" : " · \(plan.extracts.count) extrait(s) : \(plan.extracts[0].source)"
            Swift.print(String(
                format: "  ✍ RÉPONSE RÉDIGÉE (%@) « %@ » : 1er mot +%.1f s, complète +%.1f s après la fin du tour (%.1f s après la dernière syllabe)%@%@",
                kind, topic.title, draft.firstWord, draft.complete, draft.sinceVoice, sources, check
            ))
            Swift.print(text.split(separator: "\n", omittingEmptySubsequences: false).map { "     │ \($0)" }.joined(separator: "\n"))
        } catch {
            if Task.isCancelled || error is CancellationError {
                cancelled += 1
                Swift.print("  ✕ réponse à « \(topic.title) » annulée : une case plus récente l'a remplacée")
            } else {
                Swift.print("  ✕ réponse à « \(topic.title) » impossible : \((error as? CodexFailure)?.userMessage ?? (error as? APIFailure)?.userMessage ?? "\(error)")")
            }
        }
    }

    func summary() {
        guard !drafts.isEmpty else { return }
        let invented = drafts.compactMap(\.invented)
        Swift.print(String(
            format: "Réponses rédigées : %d (%@) · 1er mot médiane %.1f s · complète médiane %.1f s, max %.1f s après la fin du tour · %d annulée(s) · avis inventé : %@",
            drafts.count, drafts.map(\.kind).joined(separator: ", "), drafts.map(\.firstWord).median,
            drafts.map(\.complete).median, drafts.map(\.complete).max() ?? 0, cancelled,
            invented.isEmpty ? "aucun" : invented.joined(separator: " ; ")
        ))
    }

    private static func describe(_ plan: AnswerPlan, _ question: AssistQuestion) -> String {
        switch plan.format.kind {
        case .estimation: return plan.format.asksAboutTheFuture ? "estimation, projection" : "estimation"
        case .fact: return "connaissance"
        case .opinion: return question.isOpinionMissing ? "avis absent de la base" : "avis de avis.md"
        case .personal: return plan.format.isBehavioural ? "histoire perso" : "perso"
        case .technical: return "technique"
        case .none: return "aucun"
        }
    }
}
