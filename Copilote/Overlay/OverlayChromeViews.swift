import CopiloteKit
import KeyboardShortcuts
import SwiftUI

/// SwiftUI inside the never-key panel: without this the first click on a case would be swallowed.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        // The overlay's panels have a hidden title bar: without this SwiftUI keeps the bar's safe
        // area and pushes the content 28 pt down, out of the 40 pt pill (the user's first real launch:
        // an empty dark bar, the controls cut off at the bottom).
        safeAreaRegions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private let accent = FicheStyle.accent

/// Everything below the header: cases, fiche, actions, "Demander", notes, the answer, the transcript.
struct OverlayBody: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var listening: ListeningController
    @ObservedObject var session: SessionController
    @ObservedObject var base: BaseController
    @ObservedObject var assist: AssistController
    @ObservedObject var notes: NotesController
    @ObservedObject var overlay: OverlayModel
    let webView: NSView
    let onStartTyping: () -> Void
    let onEndTyping: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if overlay.showsPrivacyHelp {
                HStack(alignment: .top) {
                    Text(Copy.Settings.stealthHelp).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Button("Close") { overlay.showsPrivacyHelp = false }.buttonStyle(.plain).font(.system(size: 11))
                }.padding(10).background(Color.black.opacity(0.2))
            }
            HStack {
                Text(settings.infosysInterviewActive ? "Infosys — Technical interview" : "Profile · Normal").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(settings.infosysInterviewActive ? "Return to Normal" : "Infosys — Technical interview") { settings.infosysInterviewActive.toggle() }.buttonStyle(.plain)
            }.padding(.horizontal, 12).padding(.vertical, 5)
            if let event=session.latestProviderDiagnostic {
                VStack(alignment:.leading,spacing:3) {
                    HStack {
                        Text(event.timestamp,style:.time)
                        Text(event.action + " · " + (event.statusCode.map { "HTTP \($0)" } ?? event.category ?? "Provider error"))
                        Spacer()
                        Button("Copy details",action:session.copyProviderDiagnostics)
                        Button("Dismiss") { session.latestProviderDiagnostic=nil }
                    }
                    Text(event.category == "rateLimit" ? "Requests paused. Retry after the indicated wait; the service did not confirm the precise limit." : "Request interrupted. Details are available in Settings → Request diagnostics.")
                    if let seconds=event.retryAfterSeconds { Text("Wait at least \(String(format:"%.0f",ceil(seconds))) seconds from this timestamp. This request will not be resent automatically.") }
                }.font(.system(size:10)).buttonStyle(.plain).padding(.horizontal,10).padding(.vertical,5)
                    .background(FicheStyle.danger.opacity(0.12))
            }
            TopicCasesView(listening: listening, session: session, selectedID: session.answeringTopicID)
            ScreenshotStackView(session: session)
            ReadingArea(view: webView)
                .frame(minHeight: 120, maxHeight: .infinity)
                .layoutPriority(1)
                .padding(.horizontal, 6)
            StickyNotesBar(notes: session.stickyNotes)
            VStack(alignment: .leading, spacing: 6) {
                ActionBar(
                    target: assist.target?.title, included: assist.context.items.filter(\.isIncluded).count,
                    total: assist.context.items.count, isContextOpen: assist.isContextOpen,
                    onAction: assist.run, answerKeys: ShortcutCatalog.keys(for: .answerLatestTopic), onClearTarget: { assist.select(nil) }, onContext: { assist.isContextOpen.toggle() }
                )
                if assist.isContextOpen {
                    ScrollView {
                        FicheArea(base: base, listening: listening, session: session)
                        ContextDrawer(items: assist.context.items, onToggle: assist.toggle, onIncludeAll: assist.includeAll)
                    }
                    .frame(maxHeight: 220)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                if overlay.isTyping {
                    AskField(text: $assist.askText, onPasteImages: session.pasteImages, wantsFocus: overlay.isTyping, onCancel: onEndTyping, onSubmit: assist.submitAsk)
                        .onExitCommand(perform: onEndTyping)
                } else {
                    AskPrompt(onStart: onStartTyping)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            TranscriptStripView(listening: listening)
        }
        .animation(FicheStyle.motion(reduceMotion), value: assist.isContextOpen)
        .animation(FicheStyle.motion(reduceMotion), value: overlay.isTyping)
    }
}

/// The answer's WKWebView (owned by the overlay controller), placed in the SwiftUI layout.
private struct ReadingArea: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view.identifier = NSUserInterfaceItemIdentifier("CopiloteAnswerReader"); return view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The end-of-meeting notes, while they are written and once they are.
struct NotesArea: View {
    @ObservedObject var notes: NotesController

    var body: some View {
        Group {
            switch notes.state {
            case .idle:
                EmptyView()
            case .writing:
                NotesStatusView(text: Copy.Notes.writing, isWorking: true)
            case .tooShort:
                NotesStatusView(text: Copy.Notes.tooShort)
            case let .failed(reason):
                NotesStatusView(text: Copy.Notes.failed(reason, keys: ShortcutCatalog.keys(for: .meetingNotes)))
            case let .ready(report):
                ScrollView {
                    MeetingNotesCard(
                        report: report,
                        onCopyNotes: { notes.copy(report.notes.markdown) },
                        onCopyEmail: { notes.copy(report.email.text) }
                    )
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
            case let .reviewOnly(review):
                ScrollView { SelfReviewSection(review: review).ficheCard() }
                    .frame(maxHeight: 240)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, notes.state == .idle ? 0 : 6)
    }
}

// MARK: Personal fiche

/// The fiche found for a personal question, between the cases and the answer. Open until the
/// answer has words, then folded to one line so what to say comes first (a click opens it again).
/// An opinion not in avis.md shows « Pas dans ta base » in its place.
private struct FicheArea: View {
    @ObservedObject var base: BaseController
    @ObservedObject var listening: ListeningController
    @ObservedObject var session: SessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let missing = base.missingOpinion {
                MissingOpinionCard(
                    subject: missing.subject, readOnly: base.isReadOnly, isAdded: missing.isAdded, failure: missing.failure,
                    onAdd: base.addMissingOpinion, onClose: base.dismiss
                )
                    .transition(transition)
            } else if let displayed = base.displayed {
                if displayed.action == .show && !base.fold.isFolded {
                    ScrollView {
                        FicheView(
                            fiche: displayed.fiche, onAnswer: { listening.answer(fiche: displayed) }, onClose: base.dismiss,
                            onFold: foldAction
                        )
                    }
                    // While listening an answer comes under it: the same height before and after, no jump.
                    .frame(maxHeight: listening.isListening || session.isShowingAutomatic ? 240 : 400)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(transition)
                } else if displayed.action == .show {
                    // Collapses upward into its line, the answer rising under the cases.
                    FicheFoldedLine(fiche: displayed.fiche, onOpen: base.toggleFold, onClose: base.dismiss)
                        .transition(.opacity)
                } else {
                    FicheSuggestion(fiche: displayed.fiche, onShow: base.expand, onClose: base.dismiss)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, base.displayed == nil && base.missingOpinion == nil ? 0 : 6)
        .animation(FicheStyle.motion(reduceMotion), value: base.displayed)
        .animation(FicheStyle.motion(reduceMotion), value: base.missingOpinion)
        .animation(FicheStyle.motion(reduceMotion), value: base.fold)
        .animation(FicheStyle.motion(reduceMotion), value: session.isShowingAutomatic)
    }

    /// With words to read under it, the open fiche can fold back to its line.
    private var foldAction: (() -> Void)? {
        guard session.answerPhase == .reading else { return nil }
        return { [base] in base.toggleFold() }
    }

    /// Comes down from under the cases, leaves the same way.
    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }
}

// MARK: Topic cases

/// The 4 topic cases, newest first, above the reading area.
struct TopicCasesView: View {
    @ObservedObject var listening: ListeningController
    @ObservedObject var session: SessionController
    var selectedID: String?

    var body: some View {
        VStack(spacing: 4) {
            if listening.topics.isEmpty, listening.isListening {
                Text("Listening to both sides · interviewer requests appear here automatically")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            CasesList(
                topics: listening.topics, keys: ShortcutCatalog.answerTopic.map { ShortcutCatalog.keys(for: $0) },
                answeringID: session.answeringTopicID, selectedID: selectedID, answers: session.cardAnswers, updatedIDs: session.updatedTopicIDs,
                onAnswer: { listening.answer(caseIndex: $0) }, onPin: { listening.togglePin(caseIndex: $0) }
            )
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, listening.topics.isEmpty && !listening.isListening ? 0 : 6)
    }
}

// MARK: Conversation strip

/// The live transcription, folded to one line by default. "Moi" / "Eux" come from the audio channel.
struct TranscriptStripView: View {
    @ObservedObject var listening: ListeningController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if listening.isListening || !listening.transcript.lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) { listening.transcriptExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(listening.transcriptExpanded ? 180 : 0))
                        Text("Conversation")
                            .font(.system(size: 10.5, weight: .semibold))
                        Spacer()
                        SpeakingDot(label: "Them", isOn: listening.speaking.contains(.them))
                        SpeakingDot(label: "Me", isOn: listening.speaking.contains(.me))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach(listening.rows(limit: listening.transcriptExpanded ? 6 : 1)) { row in
                    ConversationRow(row: row, lineLimit: listening.transcriptExpanded ? 3 : 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
    }
}

private struct ConversationRow: View {
    let row: ListeningController.LiveRow
    let lineLimit: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.speaker.name)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(row.speaker == .me ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                .frame(width: 36, alignment: .leading)
            Text(row.text)
                .font(.system(size: 11.5))
                .foregroundStyle(row.isVolatile ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(lineLimit)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SpeakingDot: View {
    let label: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(isOn ? Color.green : Color.white.opacity(0.2))
                .frame(width: 5, height: 5)
            Text(label).font(.system(size: 10))
        }
        .accessibilityLabel("\(label) \(isOn ? "parle" : "silencieux")")
    }
}
