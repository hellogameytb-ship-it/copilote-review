import AppKit
import Combine
import CopiloteKit
import KeyboardShortcuts

/// Movement is global only while the workspace is visible and no Copilote editor owns input.
/// The library's repeating stream follows macOS delay/rate and stops on release or disable.
@MainActor
final class OverlayMovementShortcuts {
    static let bindings: [(KeyboardShortcuts.Name, OverlayPlacement.Direction)] = [
        (.moveUp, .up), (.moveDown, .down), (.moveLeft, .left), (.moveRight, .right)
    ]
    private let overlay: OverlayController
    private let controlsRegistration: Bool
    private var tasks: [Task<Void, Never>] = []
    private var observers: [NSObjectProtocol] = []
    private var subscription: AnyCancellable?
    private(set) var enabled = false

    init(overlay: OverlayController, register: Bool = true) {
        self.overlay = overlay
        controlsRegistration = register
        if register {
            for (name, direction) in Self.bindings {
                tasks.append(Task { [weak self] in
                    for await _ in KeyboardShortcuts.repeatingKeyDownEvents(for: name) {
                        guard !Task.isCancelled else { return }
                        self?.moveIfAllowed(direction)
                    }
                })
            }
        }
        for name in [Notification.Name.copiloteFirstResponderChanged, NSWindow.didBecomeKeyNotification,
                     NSWindow.didResignKeyNotification, NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                    DispatchQueue.main.async { [weak self] in self?.refresh() }
                }
            })
        }
        subscription = overlay.model.$machine.sink { [weak self] machine in
            self?.refresh(presentation: machine.presentation, typing: machine.isTyping)
        }
        refresh()
    }

    func refresh(presentation: OverlayMachine.Presentation? = nil, typing: Bool? = nil) {
        let key = NSApp.keyWindow.flatMap { $0.isKeyWindow ? $0 : nil }
        let responder = key?.firstResponder
        let editing = (responder as? NSTextView)?.isEditable == true || responder is NSTextField
        // Settings and shortcut recorders keep their normal keyboard commands too.
        let otherWindow = key != nil && (!(key is OverlayPanel) || key?.title == "Copilote Settings")
        enabled = (presentation ?? overlay.model.machine.presentation) != .hidden
            && !(typing ?? overlay.model.isTyping) && !editing && !otherWindow && !NSApp.isHidden
        let names = Self.bindings.map(\.0)
        if controlsRegistration {
            if enabled { KeyboardShortcuts.enable(names) } else { KeyboardShortcuts.disable(names) }
        }
    }

    func moveIfAllowed(_ direction: OverlayPlacement.Direction) {
        refresh()
        guard enabled else { return }
        overlay.move(direction)
    }

    func stop() {
        tasks.forEach { $0.cancel() }; tasks = []
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        subscription = nil
        if controlsRegistration { KeyboardShortcuts.disable(Self.bindings.map(\.0)) }
    }
}
