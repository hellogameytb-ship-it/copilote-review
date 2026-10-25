import KeyboardShortcuts

/// Global shortcuts, by physical key: their defaults depend on the keyboard layout and are set at
/// launch by `ShortcutSetup` (ShortcutDefaults in the Kit); all are editable in the main window.
extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay")
    static let togglePanel = Self("togglePanel")
    /// The stealth mode (its name kept from the first « mode caché »: renaming would reset it).
    static let captureScreen = Self("captureScreen")
    static let captureRegion = Self("captureRegion")
    static let sendCaptures = Self("sendCaptures")
    static let sendClipboard = Self("sendClipboard")
    static let clearContext = Self("clearContext")
    // Step 4: ⌘ + arrows move the overlay (Cluely), so scrolling moves to ⌘⇧ + arrows.
    static let scrollUp = Self("scrollAnswerUp")
    static let scrollDown = Self("scrollAnswerDown")
    static let moveUp = Self("moveOverlayUp")
    static let moveDown = Self("moveOverlayDown")
    static let moveLeft = Self("moveOverlayLeft")
    static let moveRight = Self("moveOverlayRight")
    static let ask = Self("ask")
    static let textBigger = Self("textBigger")
    static let textSmaller = Self("textSmaller")
    static let meetingNotes = Self("meetingNotes")
    static let toggleClickThrough = Self("toggleClickThrough")

    // Step 2: listening and topic cases.
    static let toggleListening = Self("toggleListening")
    static let answerLatestTopic = Self("answerLatestTopic")
    static let answerTopic1 = Self("answerTopic1")
    static let answerTopic2 = Self("answerTopic2")
    static let answerTopic3 = Self("answerTopic3")
    static let answerTopic4 = Self("answerTopic4")
    static let pinTopic1 = Self("pinTopic1")
    static let pinTopic2 = Self("pinTopic2")
    static let pinTopic3 = Self("pinTopic3")
    static let pinTopic4 = Self("pinTopic4")
}

extension ShortcutLabels {
    /// As configured now, with the current layout's characters.
    @MainActor static var current: ShortcutLabels {
        ShortcutLabels(
            toggleOverlay: ShortcutCatalog.keys(for: .toggleOverlay), captureScreen: ShortcutCatalog.keys(for: .captureScreen),
            sendCaptures: ShortcutCatalog.keys(for: .sendCaptures), toggleListening: ShortcutCatalog.keys(for: .toggleListening),
            answerLatestTopic: ShortcutCatalog.keys(for: .answerLatestTopic), meetingNotes: ShortcutCatalog.keys(for: .meetingNotes),
            ask: ShortcutCatalog.keys(for: .ask), togglePanel: ShortcutCatalog.keys(for: .togglePanel)
        )
    }
}

enum ShortcutCatalog {
    /// Order and English labels shown in settings.
    static let all: [(name: KeyboardShortcuts.Name, label: String)] = [
        (.toggleOverlay, "Show / hide overlay"),
        (.togglePanel, "Expand/collapse panel"),
        (.captureScreen, "Capture screen"),
        (.captureRegion, "Add screen region"),
        (.ask, "Ask a typed question"),
        (.sendCaptures, "Answer the screenshot stack"),
        (.sendClipboard, "Send clipboard"),
        (.clearContext, "Clear screenshots and answer history"),
        (.scrollUp, "Scroll up"),
        (.scrollDown, "Scroll down"),
        (.moveUp, "Move overlay up"),
        (.moveDown, "Move overlay down"),
        (.moveLeft, "Move overlay left"),
        (.moveRight, "Move overlay right"),
        (.textBigger, "Increase answer text size"),
        (.textSmaller, "Decrease answer text size"),
        (.meetingNotes, "Session notes"),
        (.toggleClickThrough, "Click through overlay"),
        (.toggleListening, "Start / end session"),
        (.answerLatestTopic, "Answer latest speech"),
        (.answerTopic1, "Open subject 1"),
        (.answerTopic2, "Open subject 2"),
        (.answerTopic3, "Open subject 3"),
        (.answerTopic4, "Open subject 4"),
        (.pinTopic1, "Pin subject 1"),
        (.pinTopic2, "Pin subject 2"),
        (.pinTopic3, "Pin subject 3"),
        (.pinTopic4, "Pin subject 4"),
    ]

    static let answerTopic: [KeyboardShortcuts.Name] = [.answerTopic1, .answerTopic2, .answerTopic3, .answerTopic4]
    static let pinTopic: [KeyboardShortcuts.Name] = [.pinTopic1, .pinTopic2, .pinTopic3, .pinTopic4]

    /// ⌘↩, ⌥1-4 and ⌥⇧1-4 are only grabbed while listening: otherwise Command-Return
    /// and Option-digits keep working in other apps.
    static let topicsOnly: [KeyboardShortcuts.Name] = [.answerLatestTopic] + answerTopic + pinTopic

    /// Scrolling and the text size are only grabbed while the panel is unfolded: ⌘⇧↑ / ⌘⇧↓ select
    /// text everywhere else.
    static let panelOnly: [KeyboardShortcuts.Name] = [.scrollUp, .scrollDown, .textBigger, .textSmaller]

    /// Ask and panel folding are available while visible. Movement has its own editor-aware registration.
    static let visibleOnly: [KeyboardShortcuts.Name] = [.ask, .togglePanel]

    /// Shown in the overlay's empty state.
    static let emptyStateHints: [(name: KeyboardShortcuts.Name, label: String)] = [
        (.captureScreen, "capture screen"),
        (.captureRegion, "add screen region"),
        (.sendCaptures, "answer screenshots"),
        (.sendClipboard, "send clipboard"),
        (.toggleOverlay, "hide"),
    ]

    /// The shortcut as currently configured (e.g. "⌘⇧↩"), for status lines and hints.
    @MainActor
    static func keys(for name: KeyboardShortcuts.Name) -> String {
        KeyboardShortcuts.getShortcut(for: name)?.description ?? "(unassigned)"
    }
}
