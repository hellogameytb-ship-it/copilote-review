import CopiloteKit
import Foundation

/// The shortcuts as configured, shown with what the keys type in the current layout (⌥& for case 1
/// on AZERTY). Data only, for the views shared with copilote-render; the app fills it.
struct ShortcutLabels: Equatable {
    var toggleOverlay = "⌥⌘O"
    var captureScreen = "⇧⌘S"
    var sendCaptures = "⇧⌘↩"
    var toggleListening = "⇧⌘L"
    var answerLatestTopic = "⌘↩"
    var meetingNotes = "⇧⌘N"
    var toggleMode = "⇧⌘H"
    var ask = "⌃⌘↩"
}

/// Every label of step 4 in one place: the same word for the same thing everywhere, French,
/// short, "tu". Shared with copilote-render.
enum Copy {
    enum Pill {
        static let listen = "Start session"
        static let pause = "Pause"
        static let listenHelp = "Listen to both sides and prepare answers automatically"
        static let pauseHelp = "Pause listening and automatic drafts"
        static let resume = "Resume"
        static let resumeHelp = "Resume the current session"
        static let stop = "End session"
        static let stopHelp = "Stop listening and prepare session notes"
        static let ask = "Ask"
        static let askHelp = "Type a question using the session context"
        static let stealth = "Stealth"
        static let stealthOn = "Stealth on"
        static let stealthOff = "Stealth off"
        static func stealthHint(_ keys: String, hide: String) -> String { "Hide from Dock and app switcher; the overlay stays visible to you (\(keys)). Hide the overlay: \(hide)." }
        static let unfold = "Expand"
        static let fold = "Collapse"
        static let mode = "Mode"
        static func provider(_ label: String) -> String { "Active provider: \(label)" }
        static let more = "Mode, settings and quit"
        static let noProvider = "No provider ready"
        static let recenter = "Recenter the overlay"
        static let drag = "Drag to move"
        static let openApp = "Settings, history and Brain…"
        static let tour = "Show welcome guide"
        static let quit = "Quit Copilote"
    }
    enum Panel {
        static let pin = "Pin"
        static let unpin = "Unpin"
        static let askPlaceholder = "Ask about this conversation or your screenshots…"
        static let askHint = "Return to send · Escape to cancel"
        static func target(_ title: String?) -> String { title.map { "Subject: \($0)" } ?? "Subject: current conversation" }
        static let clearTarget = "Use the current conversation"
        static func context(_ included: Int, of total: Int) -> String { "Context · \(included)/\(total)" }
        static let includeAll = "Include all"
        static let contextEmpty = "Start a session or add a screenshot to provide context."
        static let transcript = "Conversation"
        static let captures = "Screenshots"
        static let base = "Brain sources"
        static let copySentence = "Copy sentence"
        static let copied = "Copied"
        static let followUps = "Likely follow-ups"
        static let say = "Say"
        static func actionHint(_ action: AssistAction) -> String {
            switch action {
            case .answer: return "Refresh the selected answer using the full session context"
            case .whatToSay: return "A shorter ready-to-say version and likely follow-ups"
            case .questions: return "Suggest questions you could ask the interviewer"
            case .notes: return "Summarize the session so far"
            }
        }
    }
    enum Listening { static let idleStopped = "Session ended." }
    enum Notes {
        static let title = "Session notes"
        static let writing = "Preparing session notes…"
        static let tooShort = "At least three phrases are needed for session notes."
        static func failed(_ reason: String, keys: String) -> String { "Could not prepare notes: \(reason). Retry with \(keys)." }
        static let email = "Follow-up email"
        static let copyNotes = "Copy notes"
        static let copyEmail = "Copy email"
        static let review = "Feedback on your answers"
        static let diction = "Your speech"
        static let dictionHelp = "Calculated on this Mac from your microphone transcript. No data is sent."
        static let subject = "Subject:"
        static let quoted = "Each point is supported by a quote from the conversation."
        static let showQuote = "Show quote"
        static let hideQuote = "Hide quote"
    }
    enum Direct {
        static func label(_ title: String) -> String { "Automatic answer · \(title)" }
        static let notInBase = "Not documented in Brain"
        static func notInBaseBody(_ subject: String) -> String { "Your opinion on ‘\(subject)’ is not documented in your opinion notes. These are neutral options, not a preference attributed to you." }
        static let addToOpinions = "Add to opinion notes"
        static let added = "Added — complete after the session"
        static func addFailed(_ reason: String) -> String { "Could not update opinion notes: \(reason)" }
        static let provisional = "Checking the subject title"
        static let answerShown = "Answer displayed"
    }
    enum Session {
        static let replaced = "Replaced by a newer request"
        static let withdrawn = "Automatic draft cancelled"
        static let inventedOpinion = "This draft contains a preference not documented in your sources. Review it before using it."
    }
    enum History {
        static let title = "History"
        static let search = "Search sessions"
        static let off = "History is off. Enable Save history in settings to keep sessions on this Mac."
        static let offKept = "New sessions are not being saved. Previously saved sessions remain available."
        static let empty = "No saved sessions yet."
        static func noResult(_ query: String) -> String { "No session contains ‘\(query)’." }
        static let export = "Export Markdown…"
        static let delete = "Delete"
        static func deleteTitle(_ title: String) -> String { "Delete ‘\(title)’?" }
        static let deleteMessage = "This permanently deletes the session and its saved transcript from this Mac."
        static let keep = "Keep"
        static let cases = "Subjects"
        static let answers = "Answers"
        static let transcript = "Conversation"
        static let thisRun = "Answers in this session (not saved)"
        static func pick() -> String { "Choose a session on the left." }
    }
    enum Settings {
        static let section = "Sessions"
        static let defaultMode = "Default mode"
        static let notesAtEnd = "Prepare notes when the session ends"
        static let notesAtEndHelp = "The full conversation stays in memory during the session. Nothing is saved to disk unless history is enabled."
        static let review = "Feedback on my answers"
        static let reviewHelp = "Advice on your own statements after the session."
        static let keepHistory = "Save history, including transcripts"
        static let keepHistoryHelp = "Tell participants before saving a conversation and obtain any required consent."
        static let retention = "Keep saved sessions"
        static let retentionChoices: [(days: Int, label: String)] = [(7, "7 days"), (30, "30 days"), (365, "1 year"), (0, "Forever")]
        static let autoAnswer = "Prepare answers automatically for each subject"
        static let autoAnswerHelp = "Hands-free during an explicitly started session. Only interviewer requests trigger answers; your voice adds context. Each updated subject uses your provider quota."
        static let menuBar = "Show menu bar icon"
        static let stealth = "Stealth mode"
        static let stealthHelp = "Hide from Dock and app switcher. The overlay remains visible to you. This settings window closes because it is not excluded from screen sharing."
        static let openAtLogin = "Open Copilote at login"
        static let openAtLoginApprove = "Approve in System Settings › General › Login Items"
        static func openAtLoginFailed(_ reason: String) -> String { "Could not change login behavior: \(reason)" }
        static let resetShortcuts = "Reset keyboard shortcuts…"
        static let resetShortcutsQuestion = "Reset all keyboard shortcuts?"
        static let resetShortcutsConfirm = "Reset shortcuts"
        static let resetShortcutsHelp = "Restore defaults for the current keyboard layout, including removed shortcuts."
        static let answersSection = "Answers"
        static let instructions = "Standing instructions"
        static let instructionsHelp = "Included with every request. For example: ‘English software engineering interview. Concise answers grounded in my CV and projects.’"
        static let language = "Answer language"
        static let textSize = "Text size"
        static let overlaySection = "Overlay"
        static let opacity = "Background density"
        static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
        static let tour = "Show welcome guide"
    }
    enum Welcome {
        static func progress(_ step: Int, of count: Int) -> String { "Step \(step) of \(count)" }
        static let skip = "Skip"
        static let back = "Back"
        static let next = "Next"
        static let start = "Get started"
        static let done = "Ready"
        static let toDo = "Required"
        static let allow = "Allow"
        static let retry = "Retry"
        static let openFolder = "Open folder"
        static let welcomeTitle = "Welcome to Copilote"
        static let welcomeBody = "Start a session to listen to both sides, keep the conversation in memory and prepare English answers automatically from your CV and Brain. Check screen-sharing behavior in your meeting app."
        static let permissionsTitle = "Two permissions"
        static let permissionsBody = "Audio is transcribed on this Mac. Captured audio is never saved."
        static let microphone = "Microphone"
        static let microphoneWhy = "Your voice adds context on the Me channel."
        static let screen = "Screen & System Audio Recording"
        static let screenWhy = "For the interviewer’s audio and screenshots you request. macOS may require a restart; this guide resumes here."
        static let codexTitle = "Answer provider"
        static let codexBody = "Use Codex signed into your ChatGPT account, or configure an Anthropic API key in settings."
        static let codexReady = "Codex is ready"
        static let codexMissing = "Codex is not ready"
        static let baseTitle = "Your Brain"
        static let baseBody = "Copilote reads your Brain Markdown notes in iCloud without modifying them. Search is local; only relevant, sourced excerpts accompany an answer. Recognized sensitive notes are excluded."
        static func baseCount(_ items: Int) -> String { items == 0 ? "No notes indexed. Make Brain available on this Mac." : "\(items) indexed items." }
        static let shortcutsTitle = "Four shortcuts"
        static let shortcutsBody = "Every action is also available with the mouse. Customize shortcuts in settings."
        static let keyToggle = "Show or hide overlay"
        static let keyAsk = "Type a question"
        static let keyScreen = "Answer the screenshot stack"
        static let keyListen = "Start or end a session"
        static let stealthTitle = "Stealth mode"
        static func stealthBody(_ keys: String) -> String { "Hide Copilote from Dock and app switcher while keeping the overlay visible. Use Stealth or \(keys) to toggle it. Verify sharing behavior in your meeting app." }
        static let stealthOn = "Stealth enabled"
        static let stealthOff = "Stealth disabled"
        static let stealthWhere = "The overlay requests exclusion from screen sharing in both modes. Meeting apps may handle this differently. Stealth also closes the main window."
    }
    enum MenuBar {
        static let show = "Show Copilote"
        static let hide = "Hide Copilote"
        static let listen = "Start session"
        static let stopListening = "End session"
        static let settings = "Settings…"
        static let quit = "Quit Copilote"
    }
}
