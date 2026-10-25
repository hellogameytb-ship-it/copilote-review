import AppKit
import Combine
import CopiloteKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var settings = SettingsStore()
    private lazy var providers = ProviderController(settings: settings)
    private lazy var base = BaseController(settings: settings, providers: providers)
    private lazy var overlay = OverlayController(settings: settings)
    private lazy var notes = NotesController(settings: settings, providers: providers)
    private lazy var history = HistoryController(settings: settings)
    private lazy var onboarding = OnboardingController(settings: settings, providers: providers, base: base)
    private let capturer = ScreenCapturer()
    private let pillMenu = PillMenuController()
    private var session: SessionController!
    private var listening: ListeningController!
    private var assist: AssistController!
    private var menuBar: MenuBarController!
    private var mainWindow: MainWindowController!
    private var subscriptions: Set<AnyCancellable> = []
    /// The last session's phrases, for ⌘⇧N after it ended; dropped once its notes are written.
    private var lastSessionLines: [TranscriptLine] = []
    private var isPanelUnfolded = false
    private var movementShortcuts: OverlayMovementShortcuts?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Holding a key in "Demander" opens the accents bubble, a system window seen in screen
        // shares: in Copilote only (its own preferences), a held key repeats instead. AZERTY types
        // é è à ù directly, ê through the ^ dead key.
        if !DiagnosticRecette.isRequested { UserDefaults.standard.set(false, forKey: "ApplePressAndHoldEnabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if DiagnosticRecette.startIfAsked() { return }
        // Copilote's own panels stay out of its captures (the welcome invites ⇧⌘↩ at step 5).
        capturer.excludedWindowNumbers = { [weak self] in
            guard let self else { return [] }
            return overlay.windowNumbers + onboarding.windowNumbers + pillMenu.windowNumbers + (session?.stickyNotes.windowNumbers ?? [])
        }
        providers.detectCodex()
        session = SessionController(settings: settings, overlay: overlay, capturer: capturer, providers: providers)
        listening = ListeningController(settings: settings, providers: providers, base: base)
        listening.answers = session
        // What to say first: the fiche above an answer folds once the answer has words.
        session.$answerPhase.removeDuplicates().sink { [weak self] in self?.base.followAnswer($0) }.store(in: &subscriptions)
        assist = AssistController(settings: settings, session: session, base: base, overlay: overlay)
        assist.observe(listening)
        listening.onTopicChosen = { [weak self] in self?.assist.answer($0) }
        // The actions (Que dire, Notes) apply to the case whose answer drafted itself.
        listening.onAutomaticAnswer = { [weak self] topic in
            guard let self, session.isShowingAutomatic, session.answeringTopicID == topic.id else { return }
            assist.select(topic)
        }
        listening.onSessionEnded = { [weak self] in self?.sessionEnded($0) }
        listening.onNotice = { [overlay] in overlay.setStatus($0, tone: .idle) }
        // A listening failure shows in the overlay too, not only in the main window.
        listening.$state.sink { [overlay] state in
            if case let .failed(message) = state { overlay.setStatus(message, tone: .failed) }
        }.store(in: &subscriptions)
        overlay.onAnswerLatestTopic = { [weak self] in self?.listening.answer(caseIndex: 0) }
        overlay.attach(
            panelBody: OverlayBody(
                listening: listening, session: session, base: base, assist: assist, notes: notes, overlay: overlay.model,
                webView: overlay.readingArea, onStartTyping: { [overlay] in overlay.startTyping() }, onEndTyping: { [overlay] in overlay.endTyping() }
            ),
            pillBody: PillHost(
                listening: listening, assist: assist, providers: providers, overlay: overlay.model,
                onAsk: { [overlay] in overlay.startTyping() }, settings: settings,
                onStealth: { [weak self] in self?.toggleStealth() }, onUnfold: { [overlay] in overlay.pillClicked() },
                onMenu: { [weak self] in self?.togglePillMenu($0, at: $1) }
            )
        )
        base.start()
        history.start()
        menuBar = MenuBarController(
            isVisible: { [overlay] in overlay.isVisible },
            isListening: { [weak self] in self?.listening.isListening ?? false },
            onToggleOverlay: { [overlay] in overlay.toggle() },
            onToggleListening: { [weak self] in self?.listening.toggle() },
            onSettings: { [weak self] in self?.showSettings() }
        )
        menuBar.setEnabled(settings.menuBarIcon)
        mainWindow = MainWindowController(rootView: MainView(
            settings: settings, session: session, listening: listening, providers: providers, base: base, history: history,
            onStealth: { [weak self] in self?.setStealth($0) },
            onMenuBarChange: { [weak self] in
                guard let self else { return }
                menuBar.setEnabled(settings.menuBarIcon)
            },
            onTour: { [weak self] in self?.onboarding.start() }
        ))
        NSApp.mainMenu = MainMenu.make()
        ShortcutSetup.start()
        registerShortcuts()

        // Open the usable workspace immediately; settings remain an explicit action.
        // No activation: activating the app from a full-screen Space took the user to another Space
        // (retours 5); the pill is a floating panel, in front without it.
        applyStealth()
        overlay.start()
        session.stickyNotes.restoreWindows()
        onboarding.anchor = { [overlay] in overlay.pillFrame }
        overlay.onPlaced = { [weak self] in
            self?.onboarding.layout()
            self?.pillMenu.close(restoringKeyboard: false)
        }
        onboarding.startIfFirstLaunch()
        DiagnosticSnapshot.scheduleIfAsked()
    }

    // MARK: The ⚙ menu

    private func togglePillMenu(_ state: PillState, at rectInPill: CGRect) {
        pillMenu.toggle(PillMenuContent.menu(for: state), anchor: overlay.screenRect(fromPill: rectInPill)) { [weak self] in self?.pillMenuChose($0) }
    }

    private func pillMenuChose(_ action: PillMenuAction) {
        switch action {
        case let .mode(mode): assist.mode = mode
        case .openApp: showSettings()
        case .recenter: overlay.recenter()
        case .tour: onboarding.start()
        case .quit: NSApp.terminate(nil)
        }
    }

    /// The pill's menu, ⌘, and the menu bar icon: the main window (settings, history, base). A
    /// normal window shows in screen shares: opening it leaves the stealth mode, and the pill says so.
    private func showSettings() {
        if settings.stealth { setStealth(false) }
        mainWindow.show()
        NSApp.activate()
    }

    // MARK: After the meeting

    /// Kept in the history (setting on), then its notes (setting on) or the self-review alone.
    private func sessionEnded(_ ended: ListeningController.EndedSession) {
        let mode = assist.mode
        var record = SessionRecord.ended(
            started: ended.started, duration: ended.duration, mode: mode, lines: ended.lines, topics: ended.topics,
            answers: session.history.map { (date: $0.date, label: $0.input, text: $0.text) }, keepTranscript: settings.keepHistory
        )
        history.save(record)
        if settings.notesAtEnd {
            lastSessionLines = ended.lines
            Task {
                guard let report = await notes.write(transcript: ended.lines, mode: mode) else { return }
                lastSessionLines = []
                record.attach(report)
                history.save(record)
            }
        } else if settings.selfReview {
            Task { await notes.reviewOnly(transcript: ended.lines) }
        }
    }

    /// ⌘⇧N: notes now, on what was heard so far, or on the last session if its notes failed.
    private func notesNow() {
        let lines = listening.isListening ? (listening.sessionLines.isEmpty ? listening.transcript.lines : listening.sessionLines) : lastSessionLines
        overlay.reveal()
        Task {
            if await notes.write(transcript: lines, mode: assist.mode) != nil, !listening.isListening { lastSessionLines = [] }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        if !DiagnosticRecette.isRequested { overlay.flushPlacement(); providers.stop() }
    }

    /// Opened again while running (Dock, Finder, Spotlight, `open`): the pill, in front, on the
    /// current Space and the cursor's screen; the main window stays as it is. No activation (it
    /// can switch Spaces).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if DiagnosticRecette.isRequested { DiagnosticRecette.onReopen?(); return false }
        Self.reopen(overlay: overlay, mainWindow: mainWindow, stealth: settings.stealth)
        return false
    }

    static func reopen(overlay: OverlayController, mainWindow: MainWindowController, stealth: Bool) {
        _ = NSRunningApplication.current.unhide()
        NSApp.unhideWithoutActivation()
        overlay.present()
        overlay.reveal()
    }

    // MARK: Stealth mode

    /// On: out of the Dock and ⌘Tab (`.accessory`), the main window closed (a normal window shows
    /// in a screen share); the overlay stays, visible to the user, excluded from sharing as always.
    /// Off: Dock and ⌘Tab. Hiding the overlay for oneself is ⌥⌘O, apart.
    private func applyStealth() {
        if settings.stealth {
            mainWindow.close()
            NSApp.setActivationPolicy(.accessory)
            // Turned on from the main window: the keyboard goes back to the app in front before.
            if NSApp.isActive { NSApp.deactivate() }
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func setStealth(_ on: Bool) {
        settings.stealth = on
        applyStealth()
    }

    private func toggleStealth() {
        setStealth(!settings.stealth)
    }

    // MARK: Shortcuts

    private func registerShortcuts() {
        let actions: [(KeyboardShortcuts.Name, () -> Void)] = [
            (.toggleOverlay, { [overlay] in overlay.toggle() }),
            (.toggleMode, { [weak self] in self?.toggleStealth() }),
            (.captureScreen, { [weak self] in self?.session.captureFullScreen() }),
            (.captureRegion, { [weak self] in self?.session.captureRegion() }),
            (.sendCaptures, { [weak self] in self?.session.sendCaptures() }),
            (.sendClipboard, { [weak self] in self?.session.sendClipboard() }),
            (.clearContext, { [weak self] in
                self?.session.clear()
                self?.listening.clearIfIdle()
            }),
            (.scrollUp, { [overlay] in overlay.scroll(-1) }),
            (.scrollDown, { [overlay] in overlay.scroll(1) }),
            (.ask, { [overlay] in overlay.startTyping() }),
            (.textBigger, { [overlay] in overlay.changeTextSize(by: 1) }),
            (.textSmaller, { [overlay] in overlay.changeTextSize(by: -1) }),
            (.meetingNotes, { [weak self] in self?.notesNow() }),
            (.toggleClickThrough, { [overlay] in overlay.toggleClickThrough() }),
            (.toggleListening, { [weak self] in self?.listening.toggle() }),
            // Unfolds the pill, and answers case 1 if there is one.
            (.answerLatestTopic, { [weak self] in
                guard let self else { return }
                overlay.assist(hasTopic: !listening.topics.isEmpty)
            }),
        ]
        let caseActions: [(KeyboardShortcuts.Name, () -> Void)] = (0..<4).flatMap { index in
            [
                (ShortcutCatalog.answerTopic[index], { [weak self] in self?.listening.answer(caseIndex: index) }),
                (ShortcutCatalog.pinTopic[index], { [weak self] in self?.listening.togglePin(caseIndex: index) }),
            ]
        }
        for (name, action) in actions + caseActions {
            KeyboardShortcuts.onKeyDown(for: name, action: action)
        }
        movementShortcuts = OverlayMovementShortcuts(overlay: overlay)
        KeyboardShortcuts.disable(ShortcutCatalog.topicsOnly)
        // Grabbed only while listening: ⌘↩ and ⌥-digits go back to other apps afterwards
        // (the cases left on screen can still be clicked).
        listening.$state
            .map { $0 == .listening }
            .removeDuplicates()
            .sink { active in
                if active { KeyboardShortcuts.enable(ShortcutCatalog.topicsOnly) } else { KeyboardShortcuts.disable(ShortcutCatalog.topicsOnly) }
            }
            .store(in: &subscriptions)
        listening.$state
            .map { $0 == .listening }
            .removeDuplicates()
            .sink { [weak self] listening in
                self?.overlay.setListening(listening)
                self?.updateNotesShortcut(listening: listening)
            }
            .store(in: &subscriptions)
        // Scrolling and text size only while the panel is unfolded; moving and Demander while the
        // overlay is shown; ⌘⇧N while listening or unfolded.
        KeyboardShortcuts.disable(ShortcutCatalog.panelOnly)
        KeyboardShortcuts.disable(ShortcutCatalog.visibleOnly)
        overlay.onPresentationChange = { [weak self] presentation in
            guard let self else { return }
            // Folded, unfolded or hidden: the menu would end up under the panel, keyboard in hand.
            pillMenu.close(restoringKeyboard: true)
            onboarding.setHidden(presentation == .hidden)
            session.stickyNotes.setHiddenWithOverlay(presentation == .hidden)
            isPanelUnfolded = presentation == .panel
            Self.setEnabled(ShortcutCatalog.panelOnly, isPanelUnfolded)
            Self.setEnabled(ShortcutCatalog.visibleOnly, presentation != .hidden)
            updateNotesShortcut(listening: listening.isListening)
        }
    }

    private static func setEnabled(_ names: [KeyboardShortcuts.Name], _ isEnabled: Bool) {
        if isEnabled { KeyboardShortcuts.enable(names) } else { KeyboardShortcuts.disable(names) }
    }

    private func updateNotesShortcut(listening isListening: Bool) {
        if isListening || isPanelUnfolded { KeyboardShortcuts.enable(.meetingNotes) } else { KeyboardShortcuts.disable(.meetingNotes) }
    }
}
