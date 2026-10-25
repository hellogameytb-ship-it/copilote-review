import AVFoundation
import CopiloteKit

/// ⌘⇧L: a listening session. System audio ("Eux") and microphone ("Moi") are transcribed on
/// the device, the others' turns become topic cases. Nothing is written to disk; the transcript
/// keeps five minutes while listening and is dropped when listening stops.
@MainActor
final class ListeningController: ObservableObject {
    enum State: Equatable {
        case idle
        case starting(String)
        case listening
        case failed(String)
    }

    struct LiveRow: Identifiable, Equatable {
        let id: String
        let speaker: Speaker
        let text: String
        let isVolatile: Bool
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var topics: [Topic] = []
    @Published private(set) var transcript = TranscriptBuffer()
    @Published private(set) var volatile: [Speaker: String] = [:]
    @Published private(set) var speaking: Set<Speaker> = []
    /// Shown in the settings: which segmenter decided last and how fast.
    @Published private(set) var segmenterStatus = ""
    /// When listening started (the pill's timer).
    @Published private(set) var startedDate: Date?
    /// Paused: the session stays (transcript, cases, timer) but no sound is transcribed.
    @Published private(set) var isPaused = false
    private var pausedSince: Date?
    private var pausedTotal: TimeInterval = 0
    /// Read on the audio threads.
    private let gate = PauseGate()
    /// Every phrase of the session, in memory only, for the end-of-meeting notes (setting on) and
    /// the history (setting on). Dropped once the session is handed over.
    private(set) var sessionLines: [TranscriptLine] = []

    /// Listening stopped: the session to write notes for and maybe keep.
    var onSessionEnded: ((EndedSession) -> Void)?
    /// A case was answered (⌥1-4, ⌘↩, click): the actions answer it and then apply to it.
    var onTopicChosen: ((Topic) -> Void)?
    /// Case 1's answer drafted itself: the actions apply to that case.
    var onAutomaticAnswer: ((Topic) -> Void)?

    struct EndedSession {
        let started: Date
        let duration: TimeInterval
        let lines: [TranscriptLine]
        let topics: [Topic]
    }

    /// Topic answers go through the session (same streaming, history, context).
    weak var answers: SessionController?

    @Published var transcriptExpanded = false { didSet { settings.defaults.set(transcriptExpanded, forKey: "transcriptExpanded") } }
    private let settings: SettingsStore
    private let providers: ProviderController
    private let base: BaseController
    private let systemAudio = SystemAudioCapture()
    private let microphone = MicrophoneCapture()
    private var session: ListeningSession?
    /// Case 1's answer, drafted by itself (setting on).
    private var autoAnswers = AutoAnswerPolicy()
    private var drafting: [String: Task<Void, Never>] = [:]
    private var preparationIDs: [String: UUID] = [:]
    private var pendingAnswers: [String: Topic] = [:]
    /// Listening forgotten after the call: stopped, so the transcript leaves memory and the notes
    /// are written.
    private var idle = IdleStop(now: 0)
    private var idleTimer: Task<Void, Never>?
    /// Something to say in the overlay's status line (listening stopped by itself).
    var onNotice: ((String) -> Void)?
    /// Uptime when listening started: the channels' audio clock starts there too.
    private var startedAt: TimeInterval = 0
    private var generation = UUID()
    private var isStopping = false
    private var recetteSpeaker = Speaker.them
    private(set) var recetteEvents: [String: Int] = [:]
    var diagnosticAudioObserver: (@Sendable (Speaker, AVAudioPCMBuffer) -> Void)?

    init(settings: SettingsStore, providers: ProviderController, base: BaseController) {
        self.settings = settings
        transcriptExpanded = settings.defaults.bool(forKey: "transcriptExpanded")
        self.providers = providers
        self.base = base
    }

    var isListening: Bool { state == .listening }

    /// Final lines then the live (volatile) text, oldest first.
    func rows(limit: Int) -> [LiveRow] {
        var rows = transcript.lines.suffix(limit).map {
            LiveRow(id: "\($0.speaker.rawValue)-\($0.start)", speaker: $0.speaker, text: $0.text, isVolatile: false)
        }
        for speaker in [Speaker.them, .me] {
            if let text = volatile[speaker], !text.isEmpty {
                rows.append(LiveRow(id: "live-\(speaker.rawValue)", speaker: speaker, text: text, isVolatile: true))
            }
        }
        return Array(rows.suffix(limit))
    }

    /// The pill's button: pause while listening, resume while paused.
    func pauseOrResume() {
        guard isListening else { return toggle() }
        setPaused(!isPaused)
    }

    private func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        gate.isPaused = paused
        isPaused = paused
        if paused {
            drafting.values.forEach { $0.cancel() }; drafting = [:]; pendingAnswers = [:]; preparationIDs = [:]
            answers?.cancelAutomatic()
            base.dismiss()
            volatile = [:]
            speaking = []
            pausedSince = Date()
            idle.pause(at: Self.uptime)
        } else {
            if let since = pausedSince {
                pausedTotal += Date().timeIntervalSince(since)
                pausedSince = nil
            }
            idle.resume(at: Self.uptime)
        }
        armIdleStop()
    }

    /// Listening time, pauses left out.
    func elapsed(at date: Date) -> TimeInterval? {
        guard let startedDate else { return nil }
        return date.timeIntervalSince(startedDate) - pausedTotal - (pausedSince.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggle() {
        switch state {
        case .listening: Task { await stop() }
        case .starting: break
        case .idle, .failed: Task { await start() }
        }
    }

    // MARK: Start / stop

    func start(channels: Set<Speaker> = [.me, .them]) async {
        guard !isStopping, !isListening else { return }
        guard channels == [.me, .them] || DiagnosticRecette.isRequested else { return }
        guard #available(macOS 26, *) else {
            state = .failed("Transcription requires macOS 26 or later.")
            return
        }
        guard !channels.contains(.them) || ScreenCapturer.hasPermission else {
            ScreenCapturer.requestPermission()
            state = .failed(CaptureError.permissionDenied.errorDescription ?? "")
            return
        }
        generation = UUID()
        let run = generation
        gate.isPaused = false
        // Set before any await: a second ⌘⇧L during the microphone prompt must not start twice.
        state = .starting("Preparing transcription…")
        var microphoneAllowed = channels.contains(.me) && MicrophoneCapture.permission == .authorized
        if channels.contains(.me) && MicrophoneCapture.permission == .notDetermined {
            microphoneAllowed = await MicrophoneCapture.requestPermission()
        }

        topics = []
        transcript = TranscriptBuffer()
        volatile = [:]
        autoAnswers = AutoAnswerPolicy()
        drafting.values.forEach { $0.cancel() }; drafting = [:]; pendingAnswers = [:]; preparationIDs = [:]
        answers?.forgetTopics()
        do {
            var transcribers: [(Speaker, any Transcriber)] = []
            if channels.contains(.them) { transcribers.append((.them, try await SpeechAnalyzerTranscriber())) }
            if microphoneAllowed { transcribers.append((.me, try await SpeechAnalyzerTranscriber())) }
            guard generation == run else { return }
            let provider = providers.current()
            let segmenterName = provider?.topicSegmenterName ?? "lexical"
            let session = ListeningSession(transcribers: transcribers, segmenter: provider?.topicSegmenter, segmenterName: segmenterName) { [weak self] event in
                // FIFO hop to the main thread keeps events in order.
                DispatchQueue.main.async { MainActor.assumeIsolated { if self?.generation == run { self?.handle(event) } } }
            }
            self.session = session
            let observer = DiagnosticRecette.isRequested ? diagnosticAudioObserver : nil
            systemAudio.onBuffer = { [gate] in
                observer?(.them, $0)
                if !gate.isPaused { session.append($0, from: .them) }
            }
            systemAudio.onStop = { [weak self] error in
                DispatchQueue.main.async { MainActor.assumeIsolated { if self?.generation == run { self?.fail("Audio capture interrupted: \(error.localizedDescription)") } } }
            }
            if channels.contains(.them) { try await systemAudio.start() }
            guard generation == run else { await systemAudio.stop(); return }
            if microphoneAllowed {
                microphone.onBuffer = { [gate] in
                    observer?(.me, $0)
                    if !gate.isPaused { session.append($0, from: .me) }
                }
                microphone.onFailure = { [weak self] message in
                    DispatchQueue.main.async { MainActor.assumeIsolated { if self?.generation == run { self?.segmenterStatus = "Microphone interrupted: \(message)" } } }
                }
                try microphone.start()
            }
            startedAt = ProcessInfo.processInfo.systemUptime
            startedDate = Date()
            sessionLines = []
            setPaused(false)
            pausedTotal = 0
            segmenterStatus = provider == nil ? "Keywords (offline: \(providers.unavailableReason))" : segmenterName
            if channels.contains(.me) && !microphoneAllowed { segmenterStatus += " · microphone unavailable: only Them is transcribed" }
            state = .listening
            idle = IdleStop(now: Self.uptime)
            armIdleStop()
        } catch {
            guard generation == run else { return }
            await stop()
            state = .failed("Could not start listening: \(error.localizedDescription)")
        }
    }

    /// Stops capturing at once; the last turns are decided in the background.
    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        // Invalidate callbacks before awaiting capture shutdown. An old ASR/model result must
        // never reopen a card or start a reply in this or the next listening session.
        generation = UUID()
        gate.isPaused = true
        state = .starting("Ending session…")
        answers?.cancelAutomatic()
        base.dismiss()
        drafting.values.forEach { $0.cancel() }; drafting = [:]; pendingAnswers = [:]; preparationIDs = [:]
        idleTimer?.cancel()
        idleTimer = nil
        microphone.stop()
        await systemAudio.stop()
        // The capture callbacks hold the session (and its speech models) until released.
        microphone.onBuffer = nil
        systemAudio.onBuffer = nil
        let finishing = session
        session = nil
        volatile = [:]
        speaking = []
        await finishing?.finish(discardPending: true)
        state = .idle
        if let started = startedDate {
            onSessionEnded?(EndedSession(started: started, duration: Date().timeIntervalSince(started), lines: sessionLines, topics: topics))
        }
        startedDate = nil
        sessionLines = []
        setPaused(false)
        pausedTotal = 0
        // Nothing of the conversation stays in memory once listening is over, except the cases.
        transcript = TranscriptBuffer()
    }

    func beginRecetteConversation() {
        guard DiagnosticRecette.isRequested else { return }
        generation = UUID()
        topics = []; transcript = TranscriptBuffer(); sessionLines = []
        drafting.values.forEach { $0.cancel() }; drafting = [:]; pendingAnswers = [:]; preparationIDs = [:]
        autoAnswers = AutoAnswerPolicy(); answers?.forgetTopics()
        gate.isPaused = false; isPaused = false; speaking = []
        startedAt = Self.uptime; startedDate = Date(); state = .listening
    }

    func receiveRecetteEvent(_ event: ListeningEvent) {
        guard DiagnosticRecette.isRequested else { return }
        handle(event)
    }

    /// Opt-in recipe input: real decoding/VAD/ASR/events, fed from a controlled fixture;
    /// no microphone, screen capture or permission prompts. Production never enters this path.
    @available(macOS 26, *)
    func beginRecetteAudio(speaker: Speaker = .them) async throws {
        guard DiagnosticRecette.isRequested else { return }
        generation = UUID()
        let run = generation
        state = .starting("Audio de recette…")
        let transcriber = try await SpeechAnalyzerTranscriber()
        recetteSpeaker = speaker
        session = ListeningSession(transcribers: [(speaker, transcriber)], segmenter: nil, segmenterName: "lexical") { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { if self?.generation == run { self?.handle(event) } } }
        }
        topics = []; transcript = TranscriptBuffer(); sessionLines = []
        autoAnswers = AutoAnswerPolicy()
        gate.isPaused = false; isPaused = false
        startedAt = Self.uptime; startedDate = Date(); state = .listening
        idle = IdleStop(now: Self.uptime)
    }
    func appendRecetteAudio(_ buffer: AVAudioPCMBuffer) {
        guard DiagnosticRecette.isRequested, isListening, !gate.isPaused else { return }
        session?.append(buffer, from: recetteSpeaker)
    }
    func drainRecetteAudio() async {
        guard DiagnosticRecette.isRequested else { return }
        await session?.finish()
    }

    /// Exercises the same delegate-error path without changing OS permissions or devices.
    func interruptRecetteSystemCapture() {
        guard DiagnosticRecette.isRequested else { return }
        systemAudio.onStop?(NSError(domain: "CopiloteHardwareRecipe", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Interruption contrôlée de validation"]))
    }

    private static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Ten minutes without a phrase, pauses aside (`IdleStop`): listening stops by itself.
    private func armIdleStop() {
        // An explicitly started interview continues until Pause or End session, even in silence.
        idleTimer?.cancel()
        idleTimer = nil
    }

    private func fail(_ message: String) {
        Task {
            await stop()
            state = .failed(message)
        }
    }

    /// ⌘⇧X while not listening: the cases go too.
    func clearIfIdle() {
        base.dismiss()
        guard state != .listening else { return }
        topics = []
        transcript = TranscriptBuffer()
    }

    // MARK: Cases

    /// ⌥1-4 / click / ⌘↩ (index 0).
    /// The answer goes through the actions (`AssistController.answer`): context switches apply.
    func answer(caseIndex index: Int) {
        guard topics.indices.contains(index) else { return }
        onTopicChosen?(topics[index])
    }

    /// "Rédiger une réponse" on the fiche shown.
    func answer(fiche displayed: BaseController.DisplayedFiche) {
        answers?.answer(question: displayed.question, fiche: displayed.fiche, context: transcript.excerpt(last: 120))
    }

    /// ⌥⇧1-4: a pinned case never leaves the board.
    func togglePin(caseIndex index: Int) {
        guard topics.indices.contains(index) else { return }
        // By topic: the case the user saw, even if a decision just moved it.
        let id = topics[index].id
        let pipeline = session?.pipeline
        Task { await pipeline?.togglePin(id: id) }
    }

    // MARK: Events

    private func handle(_ event: ListeningEvent) {
        if DiagnosticRecette.isRequested {
            let key: String
            switch event {
            case .speaking: key = "speaking"
            case .volatile: key = "volatile"
            case .line: key = "line"
            case .turn: key = "turn"
            case .topics: key = "topics"
            case .failure: key = "failure"
            }
            recetteEvents[key, default: 0] += 1
        }
        guard isListening, !isPaused else { return }
        switch event {
        case let .failure(_, message):
            segmenterStatus = message
            fail(message)
        case let .speaking(speaker, isSpeaking):
            if isSpeaking { speaking.insert(speaker) }
            else { speaking.remove(speaker); flushPendingAnswers() }
        case let .volatile(speaker, text):
            volatile[speaker] = text
        case let .line(line, _, _):
            idle.heard(at: Self.uptime)
            armIdleStop()
            transcript.append(line)
            sessionLines.append(line)
            transcript.prune(now: ProcessInfo.processInfo.systemUptime - startedAt)
        case let .turn(turn):
            // The others asked something: a personal question gets its fiche now, before any LLM.
            if turn.speaker == .them { base.route(turn.text) }
        case let .topics(update):
            topics = update.topics
            if update.turn != nil {
                segmenterStatus = String(format: "%@ · last decision in %.0f ms", update.source, update.latency * 1000)
            }
            // The model's correction: the answer and the « Pas dans ta base » card follow their case.
            switch update.change {
            case let .merged(from, into):
                if let target = topics.first(where: { $0.id == into }) {
                    drafting.removeValue(forKey: from)?.cancel()
                    preparationIDs.removeValue(forKey: from)
                    pendingAnswers.removeValue(forKey: from)
                    answers?.follow(merged: from, into: target)
                    if settings.autoAnswer, answers?.hasCachedRequest(for: target) == false { pendingAnswers[target.id] = target }
                    base.follow(target, from: from)
                }
            case let .confirmed(id):
                if let topic = topics.first(where: { $0.id == id }) { base.follow(topic) }
            case let .withdrawn(id):
                base.dropMissingOpinion(of: id)
            default:
                break
            }
            answerAutomatically(update)
        }
    }

    /// Option 3: case 1's answer drafts itself (in its kind's format, from the base only when it
    /// is about the user), one at a time; a withdrawn case cancels it.
    private func answerAutomatically(_ update: TopicUpdate) {
        guard settings.autoAnswer, isListening, !isPaused, answers != nil else { return }
        switch autoAnswers.react(to: update.topics, change: update.change, userIsAnswering: false) {
        case .keep: break
        case .cancel:
            if case let .withdrawn(id) = update.change {
                drafting.removeValue(forKey: id)?.cancel()
                pendingAnswers.removeValue(forKey: id)
                answers?.cancelAutomatic(for: id)
            }
        case let .start(topic):
            drafting.removeValue(forKey: topic.id)?.cancel()
            pendingAnswers[topic.id] = topic
        }
        flushPendingAnswers()
    }

    private func flushPendingAnswers() {
        guard isListening, !isPaused, !speaking.contains(.them), let answers else { return }
        pendingAnswers = pendingAnswers.filter { id, topic in topics.contains { $0.id == id && $0.version == topic.version } }
        for topic in pendingAnswers.values where drafting[topic.id] == nil {
            let run = generation
            let preparation = UUID()
            preparationIDs[topic.id] = preparation
            drafting[topic.id] = Task { [weak self, base] in
                let plan = await base.plan(for: topic, conversation: self?.transcript.lines ?? [])
                guard let self else { return }
                defer {
                    if self.preparationIDs[topic.id] == preparation {
                        self.drafting.removeValue(forKey: topic.id)
                        self.preparationIDs.removeValue(forKey: topic.id)
                    }
                }
                guard !Task.isCancelled, self.generation == run, self.isListening, !self.isPaused,
                      self.topics.contains(where: { $0.id == topic.id && $0.version == topic.version }) else { return }
                guard !self.speaking.contains(.them) else { return }
                self.pendingAnswers.removeValue(forKey: topic.id)
                guard plan.isWorthDrafting, TurnCompletion.requestsAnswer(topic.excerpt.last ?? topic.title) else { return }
                let question = AssistQuestion.draft(for: topic, plan: plan, lines: self.transcript.lines, mode: answers.mode ?? self.settings.mode)
                answers.answerAutomatically(question, label: Copy.Direct.label(topic.title), topic: topic)
                self.onAutomaticAnswer?(topic)
            }
        }
    }

}

extension Topic {
    /// What the base is searched with: the title and what the others said.
    var searchText: String { ([title] + excerpt).joined(separator: "\n") }
}

/// The pause switch the capture callbacks read on their own threads.
private final class PauseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false

    var isPaused: Bool {
        get { lock.withLock { paused } }
        set { lock.withLock { paused = newValue } }
    }
}
