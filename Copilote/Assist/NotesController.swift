import AppKit
import CopiloteKit

/// After the meeting (listening stops, or ⌘⇧N): the notes in five sections, the follow-up
/// email, and the optional self-review, through the active provider.
@MainActor
final class NotesController: ObservableObject {
    enum State: Equatable {
        case idle
        case writing
        case ready(MeetingReport)
        /// Notes switched off, self-review on.
        case reviewOnly(SelfReview)
        case tooShort
        case failed(String)
    }

    @Published private(set) var state = State.idle

    private let settings: SettingsStore
    private let providers: ProviderController

    init(settings: SettingsStore, providers: ProviderController) {
        self.settings = settings
        self.providers = providers
    }

    /// Long fictional notes for the opt-in layout regression recipe only.
    func loadRecetteReport() {
        guard DiagnosticRecette.isRequested else { return }
        let item = ["text": "A retained session detail with decisions, context and follow-up actions.", "evidence": "fixture"]
        let data: [String: Any] = ["title": "Retained session notes", "keyPoints": Array(repeating: item, count: 12), "decisions": [], "actions": [], "openQuestions": [], "nextSteps": []]
        guard let json = try? JSONSerialization.data(withJSONObject: data), let notes = try? JSONDecoder().decode(MeetingNotes.self, from: json) else { return }
        state = .ready(MeetingReport(notes: notes, email: notes.email(mode: .meeting), review: nil))
    }

    /// nil when there are no notes (too short, no provider, failure: the state says why).
    @discardableResult
    func write(transcript: [TranscriptLine], mode: MeetingMode) async -> MeetingReport? {
        guard let provider = ready(for: transcript) else { return nil }
        state = .writing
        do {
            let notes = try await provider.meetingNotes(transcript: transcript, mode: mode)
            let review = settings.selfReview ? await review(transcript, provider: provider) : nil
            let report = MeetingReport(notes: notes, email: notes.email(mode: mode), review: review, stats: SpeechStats(transcript: transcript))
            state = .ready(report)
            return report
        } catch {
            state = .failed(ProviderController.describe(error))
            return nil
        }
    }

    /// The self-review on its own (end-of-meeting notes switched off).
    func reviewOnly(transcript: [TranscriptLine]) async {
        guard let provider = ready(for: transcript) else { return }
        state = .writing
        if let review = await review(transcript, provider: provider) {
            state = .reviewOnly(review)
        } else {
            state = .failed("No statements from you to review")
        }
    }

    private func ready(for transcript: [TranscriptLine]) -> (any LLMProvider)? {
        guard transcript.count >= 3 else {
            state = .tooShort
            return nil
        }
        guard let provider = providers.current() else {
            state = .failed(providers.unavailableReason)
            return nil
        }
        return provider
    }

    /// Only when the user spoke (the "Moi" channel).
    private func review(_ transcript: [TranscriptLine], provider: any LLMProvider) async -> SelfReview? {
        guard transcript.contains(where: { $0.speaker == .me }) else { return nil }
        return try? await provider.selfReview(transcript: transcript)
    }

    func dismiss() {
        state = .idle
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
