import AppKit
import CopiloteKit

/// One answer of the session, listed in the main window.
struct HistoryEntry: Identifiable {
    let id: Int
    let date: Date
    let input: String
    var text: String
    var note: String?
}

/// An answer that ended well: its label, its text, and the action that asked for it.
struct FinishedAnswer: Equatable {
    let label: String
    let text: String
    let action: AssistAction?
}

/// The session: capture stack, conversation context, the answers (asked for, or drafted by
/// themselves for case 1), history.
@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var history: [HistoryEntry] = []
    /// The topic whose answer is on screen, highlighted in its case.
    @Published private(set) var answeringTopicID: String?
    /// An answer is streaming in the panel.
    @Published private(set) var isAnswering = false
    @Published private(set) var lastFinished: FinishedAnswer?
    /// The answer on screen was drafted by itself.
    @Published private(set) var isShowingAutomatic = false
    /// None, asked (no words yet), or words to read: the fiche above folds once there are words.
    @Published private(set) var answerPhase: AnswerPhase = .none

    /// The meeting mode: tone and format of every new request.
    var mode: MeetingMode? {
        get { conversation.mode }
        set { conversation.mode = newValue }
    }

    /// The captures waiting to be sent (offered as context to the actions).
    var stackImages: [CapturedImage] { stack.images }
    var conversationLines: () -> [TranscriptLine] = { [] }

    let stickyNotes: StickyNotesController
    private let settings: SettingsStore
    private let overlay: OverlayController
    private let capturer: ScreenCapturer
    private let regionSelector = RegionSelector()
    private let providers: ProviderController

    @Published private var stack = CaptureStack()
    @Published private(set) var cardAnswers: [String: String] = [:]
    private var requests: [Int: AnswerRequest] = [:]
    private var conversation = Conversation()
    private var lastWarmUp = Date.distantPast
    private var nextRequestID = 0
    private var contextStartRequestID = 0
    private var typedRequests: [String] = []
    private var notesByRequest: [Int: Set<UUID>] = [:]
    /// The answer in the overlay.
    private var shown: AnswerRequest?
    private var renderScheduled = false

    /// One call to the model. Its turn joins the conversation only once it is shown and complete.
    private final class AnswerRequest {
        struct Notice {
            let kind: String
            let text: String
            /// « Réessayer » under a failure with nothing put back on the stack.
            var canRetry = false
        }

        let id: Int
        let input: UserInput
        let label: String
        /// Captures to put back on the stack if the request fails.
        let restoring: [CapturedImage]
        /// The case it answers, as it was asked (a merge moves it to the case it went into).
        var topic: TopicVersion?
        /// Drafted by itself for case 1: never over an answer the user asked for.
        let isAutomatic: Bool
        /// "Codex · gpt-5.6-luna", "Anthropic · claude-sonnet-5-5": shown when the answer ends.
        let providerLabel: String
        let started = Date()
        var text = ""
        var isFinal = false
        var content: [JSONValue] = []
        var notice: Notice?
        var firstTokenLatency: TimeInterval?
        var failure: String?
        var task: Task<Void, Never>?
        var capturesReturned = false

        init(
            id: Int, input: UserInput, label: String, restoring: [CapturedImage], topic: TopicVersion?,
            isAutomatic: Bool, providerLabel: String
        ) {
            self.id = id
            self.providerLabel = providerLabel
            self.input = input
            self.label = label
            self.restoring = restoring
            self.topic = topic
            self.isAutomatic = isAutomatic
        }
    }

    init(settings: SettingsStore, overlay: OverlayController, capturer: ScreenCapturer, providers: ProviderController) {
        self.settings = settings
        stickyNotes = StickyNotesController(settings: settings)
        self.providers = providers
        self.overlay = overlay
        self.capturer = capturer
        overlay.setCounter(stack.summary)
        refreshShortcutHints()
        overlay.onRetry = { [weak self] in self?.retry() }
    }

    // MARK: Captures (⌘⇧S, ⌘⇧A)

    func captureFullScreen() {
        guard let screen = ScreenCapturer.screenUnderMouse() else { return }
        Task {
            do {
                try await add(capturer.capture(screen))
            } catch {
                report(error)
            }
        }
    }

    func captureRegion() {
        guard !regionSelector.isSelecting, let screen = ScreenCapturer.screenUnderMouse() else { return }
        Task {
            do {
                let frozen = try await capturer.capture(screen)
                guard let region = await regionSelector.select(from: frozen, on: screen) else { return }
                try await add(region)
            } catch {
                report(error)
            }
        }
    }

    func add(_ image: CGImage) async throws {
        let encoded = try await Self.encodeOrFail(image)
        switch stack.push(encoded) {
        case .added:
            overlay.setCounter(stack.summary)
            overlay.setStatus("Screenshot added · \(ShortcutCatalog.keys(for: .sendCaptures)) to send", tone: .idle)
            warmUpConnection()
        case .full:
            overlay.setStatus("Screenshot stack full (\(stack.capacity) screenshots max)", tone: .failed)
        }
    }

    func removeCapture(at index: Int) { stack.remove(at: index); overlay.setCounter(stack.summary) }
    func moveCapture(from index: Int, to destination: Int) { stack.move(from: index, to: destination); overlay.setCounter(stack.summary) }

    // MARK: Sending (⌘⇧↩, ⌘⇧V, ⌥1-4)

    func sendCaptures() {
        // Captures are always added explicitly and submitted in their displayed order.
        guard !stack.isEmpty else { overlay.setStatus("Add a screenshot first", tone: .idle); return }
        let images = stack.drain()
        overlay.setCounter(stack.summary)
        let context = AssistContext(lines: conversationLines(), captures: images)
        let question = AssistQuestion(action: .answer, mode: mode ?? .technical, question: "Solve the task across all attached screenshots in their displayed order. Combine overlapping sections; do not omit constraints from earlier images.", heard: [], context: context)
        send(.assist(question), label: "\(images.count) screenshots", restoring: images)
    }

    /// « Réessayer » under a failed answer: the same request again (captures go back to the stack
    /// instead, and ⇧⌘↩ resends them).
    func retry() {
        guard let failed = shown, failed.failure != nil, failed.restoring.isEmpty, !isBusy else { return }
        guard let provider = providers.current() else {
            overlay.setStatus(providers.unavailableReason, tone: .failed)
            return
        }
        show(start(failed.input, label: failed.label, restoring: [], topic: failed.topic, isAutomatic: false, provider: provider))
    }

    func sendClipboard() {
        switch Clipboard.read() {
        case let .text(text):
            send(.clipboardText(text), label: "Clipboard text", restoring: [])
        case let .image(image):
            Task {
                guard let encoded = await Self.encode(image) else {
                    overlay.setStatus("Clipboard image could not be read", tone: .failed)
                    return
                }
                send(.clipboardImage(encoded), label: "Clipboard image", restoring: [])
            }
        case .unsupportedFile:
            overlay.setStatus("Unsupported file: use text or an image", tone: .failed)
        case .empty:
            overlay.setStatus("Clipboard is empty", tone: .idle)
        }
    }

    /// Répondre on this case, as it is now, is already on screen (drafted by itself or asked for),
    /// and no capture waits to go with a new one.
    func isShowingAnswer(for topic: Topic) -> Bool {
        guard let shown, shown.failure == nil, stack.isEmpty,
              case let .assist(question) = shown.input, question.action == .answer else { return false }
        return shown.topic == TopicVersion(topic)
    }

    /// A new listening session numbers its cases from t1 again: the answer on screen belongs to none.
    func forgetTopics() {
        contextStartRequestID = nextRequestID + 1
        typedRequests = []
        notesByRequest = [:]
        cancelAutomatic()
        requests = requests.filter { !$0.value.isAutomatic }
        cardAnswers = [:]
        shown?.topic = nil
        answeringTopicID = nil
    }

    /// An automatic answer is streaming: an answer the user asks for replaces it.
    var isDraftingAutomatically: Bool { shown.map { $0.isAutomatic && !$0.isFinal } ?? false }

    /// Répondre / Que dire / Notes / Demander. Included captures leave the stack with the request
    /// (and come back if it fails); switched-off ones stay on it.
    func assist(_ question: AssistQuestion, label: String, topic: Topic?) {
        if question.typed, isBusy {
            cancelCurrent()
        }
        guard !isBusy else { return reportBusy() }
        let included = question.context.includedCaptures
        if !included.isEmpty {
            let all = stack.drain()
            _ = stack.restore(all.filter { !included.contains($0) })
            overlay.setCounter(stack.summary)
        }
        send(.assist(question), label: label, restoring: included, topic: topic)
    }

    /// "Rédiger une réponse" on a fiche: the question heard, answered from the fiche's extracts.
    func answer(question: String, fiche: Fiche, context: String) {
        guard !isBusy else { return reportBusy() }
        let input = TopicQuestion(
            title: question, excerpt: [question], context: context, screenshots: [],
            personal: BaseContext.snippets(from: fiche.items)
        )
        send(.topic(input), label: "Source card: \(fiche.title)", restoring: [])
    }

    // MARK: Automatic answer to case 1 (option 3)

    /// Drafted by itself and shown like any answer, without taking the overlay out of ⌘\.
    /// Never over an answer the user asked for; a newer automatic one replaces it.
    func answerAutomatically(_ question: AssistQuestion, label: String, topic: Topic) {
        guard let provider = providers.current() else { return }
        for old in requests.values.filter({ $0.isAutomatic && $0.topic?.id == topic.id }) {
            if old.topic == TopicVersion(topic), old.failure == nil { return }
            old.task?.cancel()
            requests.removeValue(forKey: old.id)
        }
        let keepManual = isBusy
        let request = start(.assist(question), label: label, restoring: [], topic: TopicVersion(topic), isAutomatic: true, provider: provider)
        cardAnswers[topic.id] = "Preparing…"
        if !keepManual { show(request) }
    }

    func hasCachedRequest(for topic: Topic) -> Bool {
        requests.values.contains { $0.topic == TopicVersion(topic) && $0.failure == nil }
    }

    /// Switching cards restores its request immediately; it does not start another paid call.
    func showCachedAnswer(for topic: Topic) -> Bool {
        guard stack.isEmpty, let cached = requests.values.filter({ $0.topic == TopicVersion(topic) && $0.failure == nil }).max(by: { $0.id < $1.id }) else { return false }
        show(cached)
        return true
    }

    func cancelAutomatic() {
        for id in Set(requests.values.filter { $0.isAutomatic && !$0.isFinal }.compactMap { $0.topic?.id }) { cancelAutomatic(for: id) }
    }

    func cancelAutomatic(for topicID: String) {
        for request in requests.values.filter({ $0.isAutomatic && !$0.isFinal && $0.topic?.id == topicID }) {
            request.task?.cancel()
            updateHistory(request, note: "Automatic draft paused")
            requests.removeValue(forKey: request.id)
            cardAnswers[topicID] = "Paused — refresh to answer"
            if request === shown {
                shown = nil
                answeringTopicID = nil
                isAnswering = false
                isShowingAutomatic = false
                answerPhase = .none
                overlay.resetAnswer()
            }
        }
    }

    /// The model merged the answered case into another one: the answer follows it.
    func follow(merged id: String, into topic: Topic) {
        let incoming = requests.values.filter { $0.topic?.id == id }
        if !incoming.isEmpty {
            for old in requests.values.filter({ $0.topic?.id == topic.id && $0.topic != TopicVersion(topic) }) {
                old.task?.cancel(); requests.removeValue(forKey: old.id)
            }
        }
        for request in incoming { request.topic = TopicVersion(topic) }
        if let text = cardAnswers.removeValue(forKey: id) { cardAnswers[topic.id] = text }
        if answeringTopicID == id { answeringTopicID = topic.id }
    }

    /// An answer the user asked for streams (an automatic one gives way instead).
    private var isBusy: Bool { shown.map { !$0.isFinal && !$0.isAutomatic } ?? false }

    private func reportBusy() {
        overlay.setStatus("Answer in progress · \(ShortcutCatalog.keys(for: .clearContext)) to cancel", tone: .working)
    }

    private func send(_ input: UserInput, label: String, restoring images: [CapturedImage], topic: Topic? = nil) {
        guard !isBusy else {
            restore(images)
            return reportBusy()
        }
        guard let provider = providers.current() else {
            restore(images)
            overlay.setStatus(providers.unavailableReason, tone: .failed)
            overlay.reveal()
            return
        }
        show(start(input, label: label, restoring: images, topic: topic.map(TopicVersion.init), isAutomatic: false, provider: provider))
    }

    /// Starts streaming; the request is rendered only while it is the shown one.
    private func start(
        _ input: UserInput, label: String, restoring: [CapturedImage], topic: TopicVersion?, isAutomatic: Bool,
        provider: any LLMProvider
    ) -> AnswerRequest {
        nextRequestID += 1
        let request = AnswerRequest(
            id: nextRequestID, input: input, label: label, restoring: restoring, topic: topic,
            isAutomatic: isAutomatic, providerLabel: provider.label
        )
        requests[request.id] = request
        history.insert(HistoryEntry(id: request.id, date: request.started, input: request.label, text: ""), at: 0)
        conversation.preferences = settings.answerPreferences
        var draft = Conversation()
        draft.mode = conversation.mode
        draft.preferences = settings.answerPreferences
        let allowedNotes = Set(stickyNotes.notes.filter { $0.deletedAt == nil && $0.includeInAI }.map(\.id))
        notesByRequest[request.id] = allowedNotes
        let earlier = history.filter { $0.id >= contextStartRequestID && $0.id != request.id && !$0.text.isEmpty && (notesByRequest[$0.id] ?? []).isSubset(of: allowedNotes) }.reversed().map {
            "Earlier assistant draft (not evidence of personal facts): \($0.input)\n\($0.text)"
        }.joined(separator: "\n\n")
        let personalNotes = stickyNotes.includedContext
        let priorTyped = typedRequests
        if case let .assist(question) = input, question.typed, let text = question.question { typedRequests.append(text) }
        let requestID = request.id
        request.task = Task { [weak self] in
            do {
                var prepared = input
                if case var .assist(question) = prepared {
                    question.earlierAnswers = earlier
                    question.priorTypedRequests = priorTyped
                    question.personalNotes = personalNotes
                    prepared = .assist(question)
                }
                if case var .assist(question) = prepared, question.action == .answer,
                   let asked = question.question, WebResearch.needsSearch(asked) {
                    question.webAttempted = true
                    question.webSources = (try? await WebResearch.search(asked)) ?? []
                    prepared = .assist(question)
                }
                try Task.checkCancellation()
                draft.appendUser(prepared)
                let completed = try await provider.streamAnswer(to: draft) { [weak self] text in
                    await self?.receive(text, requestID: requestID)
                }
                self?.complete(requestID, with: completed)
            } catch {
                self?.fail(requestID, with: error)
            }
        }
        return request
    }

    /// Late callbacks of a cancelled or replaced request find nothing and are dropped.
    private func request(_ id: Int) -> AnswerRequest? {
        requests[id]
    }

    private func show(_ request: AnswerRequest) {
        // Only an automatic answer can still be streaming here: the newer request replaces it.
        if let previous = shown, previous !== request, !previous.isFinal, !previous.isAutomatic {
            previous.task?.cancel()
            requests.removeValue(forKey: previous.id)
            returnCaptures(previous)
            updateHistory(previous, note: Copy.Session.replaced)
        }
        shown = request
        answeringTopicID = request.topic?.id
        isShowingAutomatic = request.isAutomatic
        answerPhase = AnswerPhase(text: request.text, failed: request.failure != nil)
        if !history.contains(where: { $0.id == request.id }) {
            history.insert(HistoryEntry(id: request.id, date: request.started, input: request.label, text: request.text), at: 0)
        }
        isAnswering = !request.isFinal
        // Asked for: shown even after ⌘\. Automatic: the panel unfolds, unless the user hid it.
        if request.isAutomatic { overlay.showAutomatic() } else { overlay.reveal() }
        if request.isFinal {
            finish(request)
        } else {
            overlay.setStatus(request.text.isEmpty ? "Sending \(request.label.lowercased())…" : "Answering…",
                              tone: request.text.isEmpty ? .working : .streaming)
            render()
        }
    }

    private func receive(_ text: String, requestID: Int) {
        guard let request = request(requestID) else { return }
        if request.text.isEmpty { request.firstTokenLatency = Date().timeIntervalSince(request.started) }
        request.text += text
        if let topic = request.topic { cardAnswers[topic.id] = request.text }
        guard request === shown else { return }
        if answerPhase != .reading { answerPhase = .reading }
        if request.text == text { overlay.setStatus("Answering…", tone: .streaming) }
        scheduleRender()
    }

    private func complete(_ requestID: Int, with message: CompletedMessage) {
        guard let request = request(requestID) else { return }
        request.isFinal = true
        request.content = message.content
        switch message.stopReason {
        case "max_tokens": request.notice = .init(kind: "warning", text: "Answer truncated: token limit reached.")
        case "refusal": request.notice = .init(kind: "warning", text: "The provider declined this request.")
        default: break
        }
        // An opinion question with nothing in avis.md: no opinion may come back in the user's mouth.
        if case let .assist(question) = request.input, question.isOpinionMissing, question.action.speaksForTheUser,
           OpinionGuard.firstPersonOpinion(in: request.text) != nil {
            request.notice = .init(kind: "warning", text: Copy.Session.inventedOpinion)
        }
        finish(request)
    }

    private func fail(_ requestID: Int, with error: Error) {
        guard let request = request(requestID) else { return }
        request.isFinal = true
        request.failure = Self.describe(error)
        finish(request)
    }

    /// The shown request is done: commit it to the conversation (or restore its captures).
    private func finish(_ request: AnswerRequest) {
        if let topic = request.topic { cardAnswers[topic.id] = request.failure ?? request.text }
        if request !== shown {
            updateHistory(request, note: request.failure)
            return
        }
        if let failure = request.failure {
            answerPhase = AnswerPhase(text: request.text, failed: true)
            returnCaptures(request)
            let retry = " Screenshots returned to the stack (\(ShortcutCatalog.keys(for: .sendCaptures)) to retry)."
            request.notice = request.restoring.isEmpty
                ? .init(kind: "error", text: failure, canRetry: true)
                : .init(kind: "error", text: failure + retry)
            overlay.setStatus("Failed", tone: .failed)
            updateHistory(request, note: failure)
        } else {
            // Future requests use text-only answer history; old screenshots are never reattached.
            let total = Date().timeIntervalSince(request.started)
            let timing = [request.firstTokenLatency.map { "first word \(Self.seconds($0))" }, "total \(Self.seconds(total))"]
                .compactMap { $0 }.joined(separator: " · ")
            overlay.setStatus("Done · \(request.providerLabel) · \(timing)", tone: .idle)
            updateHistory(request, note: request.notice?.text ?? timing)
            if case let .assist(question) = request.input {
                lastFinished = FinishedAnswer(label: request.label, text: request.text, action: question.action)
            } else {
                lastFinished = FinishedAnswer(label: request.label, text: request.text, action: nil)
            }
        }
        isAnswering = false
        render()
    }

    private func updateHistory(_ request: AnswerRequest, note: String?) {
        guard let index = history.firstIndex(where: { $0.id == request.id }) else { return }
        history[index].text = request.text
        history[index].note = note
    }

    /// Puts captures back on top of the stack after a failure, in their original order.
    private func restore(_ images: [CapturedImage]) {
        guard !images.isEmpty else { return }
        let dropped = stack.restore(images)
        overlay.setCounter(stack.summary + (dropped > 0 ? " (\(dropped) extra screenshots omitted)" : ""))
    }

    private func returnCaptures(_ request: AnswerRequest) {
        guard !request.capturesReturned else { return }
        request.capturesReturned = true
        restore(request.restoring)
    }

    /// Cancel only this response. Screenshots remain available for editing or retry.
    func cancelCurrent() {
        guard let request = shown, !request.isFinal else { return }
        request.task?.cancel()
        requests.removeValue(forKey: request.id)
        request.isFinal = true
        returnCaptures(request)
        updateHistory(request, note: "Cancelled")
        if let topic = request.topic { cardAnswers[topic.id] = "Cancelled — refresh to answer" }
        shown = nil
        answeringTopicID = nil
        isAnswering = false
        isShowingAutomatic = false
        answerPhase = .none
        overlay.resetAnswer()
        overlay.setStatus("Cancelled · screenshots kept for retry", tone: .idle)
    }

    // MARK: ⌘⇧X

    func clear() {
        contextStartRequestID = nextRequestID + 1
        typedRequests = []
        notesByRequest = [:]
        if let shown, !shown.isFinal {
            updateHistory(shown, note: "Cancelled (\(ShortcutCatalog.keys(for: .clearContext)))")
        }
        for request in requests.values { request.task?.cancel() }
        requests = [:]
        cardAnswers = [:]
        shown = nil
        isShowingAutomatic = false
        answerPhase = .none
        answeringTopicID = nil
        isAnswering = false
        lastFinished = nil
        stack = CaptureStack()
        conversation.clear()
        overlay.setCounter(stack.summary)
        overlay.setStatus("Screenshots and answer history cleared", tone: .idle)
        overlay.resetAnswer()
    }

    /// The empty state lists the shortcuts as currently configured.
    func refreshShortcutHints() {
        let hints: [JSONValue] = ShortcutCatalog.emptyStateHints.map { name, label in
            ["keys": .string(ShortcutCatalog.keys(for: name)), "label": .string(label)]
        }
        guard let data = try? JSONEncoder().encode(JSONValue.array(hints)),
              let json = String(data: data, encoding: .utf8) else { return }
        overlay.setHints(json: json)
    }

    // MARK: Rendering

    /// Coalesces deltas: at most one render every ~30 ms, the first ones immediately.
    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        let delay = (shown?.text.count ?? 0) < 80 ? 0 : 0.03
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.renderScheduled = false
            self?.render()
        }
    }

    private func render() {
        // After ⌘⇧X nothing is shown: a pending render must not bring a blank answer back.
        guard let request = shown else { return }
        let segments: [JSONValue] = ResponseSegmenter.segments(of: request.text, isFinal: request.isFinal).map { segment in
            switch segment {
            case let .markdown(text):
                return ["kind": "markdown", "text": .string(text)]
            case let .diagram(source, isComplete):
                return ["kind": "diagram", "source": .string(source), "complete": .bool(isComplete)]
            }
        }
        var payload: [String: JSONValue] = ["answerId": .int(request.id), "segments": .array(segments)]
        // "Copy answer" once it is complete (not at every streamed frame).
        if request.isFinal, request.failure == nil { payload["copy"] = .string(request.text) }
        if let notice = request.notice {
            payload["notice"] = ["kind": .string(notice.kind), "text": .string(notice.text), "retry": .bool(notice.canRetry)]
        }
        guard let data = try? JSONEncoder().encode(JSONValue.object(payload)),
              let json = String(data: data, encoding: .utf8) else { return }
        overlay.render(payloadJSON: json)
    }

    // MARK: Helpers

    private static func encode(_ image: CGImage) async -> CapturedImage? {
        await Task.detached(priority: .userInitiated) { ImageEncoder.encodeForModel(image) }.value
    }

    private static func encodeOrFail(_ image: CGImage) async throws -> CapturedImage {
        guard let encoded = await encode(image) else { throw CaptureError.failed("JPEG encoding failed") }
        return encoded
    }

    private func report(_ error: Error) {
        overlay.setStatus(Self.describe(error), tone: .failed)
        if case CaptureError.permissionDenied = error { overlay.reveal() }
    }

    /// Opens the connection (or starts Codex) while the user is still capturing, so the send starts faster.
    private func warmUpConnection() {
        guard Date().timeIntervalSince(lastWarmUp) > 60, let provider = providers.current() else { return }
        lastWarmUp = Date()
        Task { await provider.warmUp() }
    }

    private static func describe(_ error: Error) -> String {
        if let capture = error as? CaptureError { return capture.errorDescription ?? "Capture failed." }
        return ProviderController.describe(error)
    }

    private static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.1f s", interval)
    }
}
