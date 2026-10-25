import AppKit
import Combine
import CopiloteKit

/// Inline confirmation lifecycle. Only events delivered to our own windows are consumed.
@MainActor
enum StealthConfirmationController {
    private static weak var settings: SettingsStore?
    private static weak var pill: OverlayPanel?
    private static weak var settingsWindow: OverlayPanel?
    private static var subscription: AnyCancellable?
    private static var sessionSubscriptions: Set<AnyCancellable> = []
    private static var observers: [NSObjectProtocol] = []
    private static var workspaceObserver: NSObjectProtocol?

    static func register(_ window: OverlayPanel, source: StealthChoice.Source) {
        switch source { case .pill: pill = window; case .settings: settingsWindow = window }
    }
    private static func owner(_ request: StealthChoice.Request) -> OverlayPanel? {
        request.source == .pill ? pill : settingsWindow
    }

    static func observe(_ settings: SettingsStore) {
        self.settings?.cancelStealthOff()
        self.settings = settings
        subscription = settings.$stealthChoice.map(\.pendingOff).removeDuplicates().sink { request in
            // Published values are delivered before storage changes. Recheck the token next turn.
            DispatchQueue.main.async {
                guard self.settings === settings, settings.pendingStealthOff == request else { return }
                if request?.source != .pill, let pill {
                    pill.allowsKey = false
                    if pill.isKeyWindow { pill.resignKey() }
                }
                guard let request, let window = owner(request) else { return }
                guard WindowPrivacy.presentationAuthorized else { cancel(); return }
                window.allowsKey = true
                window.makeKey()
            }
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification].map { name in
            NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { note in
                MainActor.assumeIsolated {
                    guard let window = note.object as? NSWindow else { return }
                    invalidate(for:window)
                }
            }
        }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { note in
            MainActor.assumeIsolated {
                guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                cancel()
            }
        }
    }

    static func observeSession(_ listening: ListeningController) {
        sessionSubscriptions.removeAll()
        listening.$state.removeDuplicates().dropFirst().sink { _ in cancel() }.store(in:&sessionSubscriptions)
        listening.$isPaused.removeDuplicates().dropFirst().sink { _ in cancel() }.store(in:&sessionSubscriptions)
    }
    static func cancel() { settings?.cancelStealthOff() }
    static func invalidate(for window: NSWindow) {
        guard let request = settings?.pendingStealthOff, owner(request) === window else { return }
        cancel()
    }
    static func consumeEscape(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.type == .keyDown, event.keyCode == 53,
              event.modifierFlags.intersection([.command,.option,.control,.shift]).isEmpty,
              let request = settings?.pendingStealthOff, owner(request) === window else { return false }
        cancel()
        return true
    }
}
