import AppKit
import Combine
import CopiloteKit

/// Répondre / Que dire / Notes, and "Demander": on the chosen case or the last phrases, with
/// the context the user left switched on, in the session's mode.
@MainActor
final class AssistController: ObservableObject {
    @Published var mode: MeetingMode {
        didSet { session.mode = mode }
    }
    @Published private(set) var context = AssistContext()
    @Published var isContextOpen = false {
        didSet { if isContextOpen { refresh() } }
    }
    @Published var askText = ""
    /// The case the actions apply to (the last one answered or clicked); nil = last phrases.
    @Published private(set) var target: Topic?
    /// The last "Que dire", read back into its sentence and follow-ups.
    @Published private(set) var whatToSay: WhatToSay?

    var onChatCleared: (() -> Void)?
    weak var listening: ListeningController?
    private let session: SessionController
    private let base: BaseController
    private let overlay: OverlayController
    private var extracts: [BaseSnippet] = []
    /// The target case's kind of question (nil: the last phrases).
    private var format: AnswerFormat?
    /// The latest lookup only: a slow one must not overwrite a newer target's extracts.
    private var extractsTask: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []

    init(settings: SettingsStore, session: SessionController, base: BaseController, overlay: OverlayController) {
        mode = settings.mode
        self.session = session
        self.base = base
        self.overlay = overlay
        session.mode = mode
        session.onFailedTypedRequest = { [weak self] text in
            guard let self,self.askText.isEmpty else { return }
            self.askText=text
        }
        session.$lastFinished
            .sink { [weak self] finished in
                guard let self else { return }
                self.whatToSay = finished.flatMap { $0.action == .whatToSay ? WhatToSay(markdown: $0.text) : nil }
            }
            .store(in: &subscriptions)
        session.$isAnswering
            .filter { $0 }
            .sink { [weak self] _ in self?.whatToSay = nil }
            .store(in: &subscriptions)
    }

    func observe(_ listening: ListeningController) {
        self.listening = listening
        session.onClearChat = { [weak self] in
            guard let self else { return }
            self.extractsTask?.cancel()
            self.target = nil; self.extracts = []; self.format = nil
            self.context.refresh(lines: [], captures: self.session.stackImages, extracts: [])
            self.askText = ""; self.whatToSay = nil
            self.listening?.resetChatContext()
            self.onChatCleared?()
            self.refresh()
        }
        session.conversationLines = { [weak listening] in listening?.transcript.lines ?? [] }
        listening.$transcript
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    func select(_ topic: Topic?) {
        target = topic
        loadExtracts {}
    }

    /// ⌥1-4, a click on a case: Répondre on it, in its kind's format, with the context
    /// switches applied; nothing new if its answer (drafted by itself) is already on screen.
    func answer(_ topic: Topic) {
        extractsTask?.cancel()
        target = topic
        if session.showCachedAnswer(for: topic) {
            overlay.reveal()
            return
        }
        session.prepareFreshAnswer()
        loadExtracts { [weak self] in self?.runSelected(.answer) }
    }

    /// Lines, captures and base extracts as of now; the user's switches are kept.
    func refresh() {
        let lines = listening?.transcript.lines ?? []
        context.refresh(lines: lines, captures: session.stackImages, extracts: extracts)
    }

    func toggle(_ id: String) {
        context.toggle(id)
    }

    func includeAll() {
        for item in context.items where !item.isIncluded { context.toggle(item.id) }
    }

    func run(_ action: AssistAction) {
        if action == .answer { answerNow() } else { runSelected(action) }
    }

    /// Shared by Answer and its existing keyboard shortcut; a fresh lookup for frozen speech.
    func answerNow() {
        guard !session.isPastingImages else { session.reportImagePastePending(); return }
        extractsTask?.cancel()
        session.prepareFreshAnswer()
        refresh()
        let frozenContext = context
        let lines = listening?.transcript.lines ?? []
        let interim = listening?.recentProvisionalSpeech() ?? []
        target = nil
        overlay.reveal()
        guard let snapshot = LiveAnswerSnapshot(lines: lines, context: frozenContext, provisional: interim, capturedAt: listening?.answerSnapshotTime()) else {
            session.noSpeechToAnswer()
            return
        }
        var question = AssistQuestion(action: .answer, mode: mode, question: snapshot.focusText, heard: [],
                                      context: frozenContext)
        question.liveSnapshot = snapshot
        // A single complete working exchange also prevents the base plan's suffix(2) from
        // reducing a fragmented question to its closing acknowledgement.
        let plan = base.snapshotPlan(heard: [snapshot.focusText], conversation: snapshot.recentLines)
        session.assist(question, label: "Answer · latest speech", topic: nil, plan: plan)
    }

    private func runSelected(_ action: AssistAction) {
        refresh()
        let question = AssistQuestion(
            action: action, mode: mode, question: target?.title, heard: target?.excerpt ?? [], context: context, format: format
        )
        // Répondre and Que dire give neutral angles for an opinion not in avis.md: the card says why.
        base.answering(target, neutralOpinion: question.isOpinionMissing && action.speaksForTheUser)
        session.assist(question, label: "\(action.name) · \(target?.title ?? "current conversation")", topic: target)
    }

    /// "Demander": the typed question, then the keyboard goes back to the call.
    func submitAsk() {
        guard !session.isPastingImages else { session.reportImagePastePending(); return }
        let text = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        overlay.endTyping()
        guard !text.isEmpty else { return }
        askText = ""
        target = nil
        extractsTask?.cancel()
        extractsTask = Task {
            let topic = Topic(id: "typed", title: text, excerpt: [text], createdAt: Date(), updatedAt: Date())
            let plan = await base.plan(for: topic, conversation: listening?.transcript.lines ?? [])
            guard !Task.isCancelled else { return }
            extracts = plan.extracts
            format = plan.format
            refresh()
            let question = AssistQuestion(action: .answer, mode: mode, question: text, heard: [], context: context, typed: true, format: plan.format)
            session.assist(question, label: "Ask · \(text.prefix(40))", topic: nil)
        }
    }

    /// A case: its plan (format and the extracts it may use). The last phrases: what the base has on them.
    private func loadExtracts(then done: @escaping () -> Void) {
        let target = target
        let text = listening?.transcript.lines.suffix(3).map(\.text).joined(separator: "\n") ?? ""
        extractsTask?.cancel()
        extractsTask = Task {
            let plan: AnswerPlan
            if let target {
                plan = await base.plan(for: target, conversation: listening?.transcript.lines ?? [])
            } else {
                plan = AnswerPlan(format: AnswerFormat(kind: .none), extracts: text.isEmpty ? [] : await base.snippets(for: text))
            }
            guard !Task.isCancelled else { return }
            extracts = plan.extracts
            format = target == nil ? nil : plan.format
            refresh()
            done()
        }
    }
}
