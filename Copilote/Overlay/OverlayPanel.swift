import AppKit

/// The floating panels (the pill and the panel under it). Non-activating: Copilote never comes
/// forward. The panel takes the keyboard only while the user types in "Demander"
/// (`allowsKey`, the user's step 4 brief), then gives it back to the call app.
class OverlayPanel: ProtectedPanel {
    /// Narrow and short enough to leave the middle of the screen (the call) visible.
    static let defaultSize = NSSize(width: 600, height: 640)
    /// True only while typing.
    var allowsKey = false

    init(size: NSSize = OverlayPanel.defaultSize, resizable: Bool = true) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: resizable ? [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView] : [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        // On every Space, over full-screen apps, still while Spaces change: opening Copilote never
        // takes the user to another Space.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Locked decision: hiding from screen sharing is this flag (+ .accessory mode), nothing more.
        sharingType = WindowPrivacy.sharing
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isRestorable = false
        canBecomeVisibleWithoutLogin = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = NSSize(width: 340, height: 180)
        appearance = NSAppearance(named: .darkAqua)
    }

    weak var workspaceRoot: OverlayPanel?
    var onWorkspaceDragBegan: (() -> Void)?
    var onWorkspaceDragEnded: (() -> Void)?

    func performWorkspaceDrag(with event: NSEvent) {
        let root = workspaceRoot ?? self
        let global = convertPoint(toScreen: event.locationInWindow)
        guard let translated = NSEvent.mouseEvent(with: .leftMouseDown,
            location: root.convertPoint(fromScreen: global), modifierFlags: event.modifierFlags,
            timestamp: event.timestamp, windowNumber: root.windowNumber, context: nil,
            eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure) else { return }
        root.onWorkspaceDragBegan?()
        root.performDrag(with: translated)
        root.onWorkspaceDragEnded?()
    }

    override func sendEvent(_ event: NSEvent) {
        // Context menus and Control-click menus are system windows outside panel protection.
        if event.type == .rightMouseDown || event.type == .rightMouseUp ||
            (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if (firstResponder as? NSView)?.identifier?.rawValue == "CopiloteShortcutRecorder" { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command || flags == [.command, .shift], let key = event.charactersIgnoringModifiers?.lowercased() else { return super.performKeyEquivalent(with: event) }
        let command: String?
        switch key {
        case "a": command = "selectAll:"
        case "c": command = "copy:"
        case "v": command = "paste:"
        case "x": command = "cut:"
        case "z": command = flags.contains(.shift) ? "redo:" : "undo:"
        case "q": NSApp.terminate(nil); return true
        default: command = nil
        }
        if let command { return NSApp.sendAction(Selector(command), to: nil, from: self) }
        return super.performKeyEquivalent(with: event)
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted {
            if let text = responder as? NSTextView {
                text.isContinuousSpellCheckingEnabled = false
                text.isGrammarCheckingEnabled = false
                text.isAutomaticSpellingCorrectionEnabled = false
                text.isAutomaticTextCompletionEnabled = false
                text.isAutomaticTextReplacementEnabled = false
                text.displaysLinkToolTips = false
                text.inlinePredictionType = .no
                if #available(macOS 15.0, *) { text.writingToolsBehavior = .none }
            }
            NotificationCenter.default.post(name: .copiloteFirstResponderChanged, object: self)
        }
        return accepted
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    private lazy var quietEditor = QuietFieldEditor.make()

    /// "Demander" types into this editor: nothing it shows may be a system window. A secure field
    /// keeps the system's own editor. SwiftUI fields must also retain their private editor.
    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        guard object is OverlayAskTextField else { return super.fieldEditor(createFlag, for: object) }
        return quietEditor
    }
}

/// A field editor that opens no system window (they are not covered by `sharingType = .none`, so
/// they would show in a screen share): no context menu, no spelling or correction bubble, no
/// completion or inline prediction, no Writing Tools, no Look Up, no Emoji & Symbols palette.
/// The checks are refused in the getters too: NSTextField pushes its own settings onto its editor.
private final class QuietFieldEditor: NSTextView {
    static func make() -> QuietFieldEditor {
        let editor = fieldEditor()
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.displaysLinkToolTips = false
        editor.inlinePredictionType = .no
        if #available(macOS 15.0, *) { editor.writingToolsBehavior = .none }
        return editor
    }

    override var isContinuousSpellCheckingEnabled: Bool { get { false } set {} }
    override var isGrammarCheckingEnabled: Bool { get { false } set {} }
    override var isAutomaticSpellingCorrectionEnabled: Bool { get { false } set {} }
    override var isAutomaticTextCompletionEnabled: Bool { get { false } set {} }
    override var isAutomaticTextReplacementEnabled: Bool { get { false } set {} }

    override func menu(for event: NSEvent) -> NSMenu? { nil }
    override func quickLook(with event: NSEvent) {}
    override func complete(_ sender: Any?) {}
    /// ⌃⌘Space reaches the first responder before NSApp; the Globe key's picker stays the system's.
    @objc func orderFrontCharacterPalette(_ sender: Any?) {}
}

/// The pill: dragged by its grip only (a click on a control never moves it), never key.
final class PillPanel: OverlayPanel {
    /// Just wider than the panel under it (440): one block, like Cluely's bar and card.
    static let size = NSSize(width: 600, height: 40)

    init() {
        super.init(size: Self.size, resizable: false)
        appearance = NSAppearance(named: .darkAqua)
        isMovableByWindowBackground = false
        hasShadow = true
    }
}

extension Notification.Name {
    static let copiloteFirstResponderChanged = Notification.Name("CopiloteFirstResponderChanged")
}
