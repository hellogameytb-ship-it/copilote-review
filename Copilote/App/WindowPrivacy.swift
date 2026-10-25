import AppKit
import Combine

/// Only public AppKit sharing and activation policies; never a capture guarantee.
@MainActor
enum WindowPrivacy {
    private static var subscription: AnyCancellable?
    private static var environmentObservers: [NSObjectProtocol] = []
    private static var sessionAvailable = true
    private static var screensAwake = true
    private static var computerAwake = true
    static var environmentAvailable: Bool { sessionAvailable && screensAwake && computerAwake }
    static private(set) var enabled = true
    static private(set) var presentationAuthorized = false
    static private(set) var policyReady = false
    static private(set) var lastBlockReason: String?
    /// Own-process fault injection only; never an exclusion/capture detector.
    static var diagnosticFailure = false
    static var sharing: NSWindow.SharingType { enabled ? .none : .readOnly }
    static func observe(_ settings: SettingsStore) {
        subscription = settings.$stealth.sink { apply($0) }
    }
    /// Public workspace events only. Becoming available never restores presentation by itself.
    static func observeSystemEnvironment(onSuspend: @escaping () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        environmentObservers.forEach(center.removeObserver)
        environmentObservers = [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    switch name {
                    case NSWorkspace.sessionDidResignActiveNotification: sessionAvailable = false
                    case NSWorkspace.sessionDidBecomeActiveNotification: sessionAvailable = true
                    case NSWorkspace.screensDidSleepNotification: screensAwake = false
                    case NSWorkspace.screensDidWakeNotification: screensAwake = true
                    case NSWorkspace.willSleepNotification: computerAwake = false
                    case NSWorkspace.didWakeNotification: computerAwake = true
                    default: break
                    }
                    if !environmentAvailable { suspend(); onSuspend() }
                }
            }
        }
    }
    static func apply(_ enabled: Bool) {
        self.enabled = enabled
        for window in NSApp.windows where window is ProtectedPanel {
            window.sharingType = sharing
        }
        let target: NSApplication.ActivationPolicy = enabled ? .accessory : .regular
        // AppKit can report no change when the requested policy is already active.
        policyReady = NSApp.activationPolicy() == target || NSApp.setActivationPolicy(target)
        policyReady = policyReady && NSApp.activationPolicy() == target
        if !policyReady { suspend() }
    }

    /// Call only at an actual UI action/reopen/shortcut boundary. Never from a provider callback.
    @discardableResult static func authorizeFromUserGesture() -> Bool {
        guard environmentAvailable else { suspend(); return false }
        apply(enabled)
        guard policyReady && !(DiagnosticRecette.isRequested && diagnosticFailure) else {
            suspend(); return false
        }
        presentationAuthorized = true
        return true
    }

    /// Applied immediately before every native ordering operation, including child windows.
    static func canPresent(_ window: NSWindow) -> Bool {
        guard presentationAuthorized, environmentAvailable else { return false }
        window.canBecomeVisibleWithoutLogin = false
        window.sharingType = sharing
        guard policyReady, NSApp.activationPolicy() == (enabled ? .accessory : .regular),
              window.sharingType == sharing, !(DiagnosticRecette.isRequested && diagnosticFailure) else {
            lastBlockReason = "Display paused: local window protection could not be applied. Explicit reopening retries it."
            suspend()
            return false
        }
        return true
    }

    static func takeBlockReason() -> String? {
        defer { lastBlockReason = nil }
        return lastBlockReason
    }

    /// Hiding revokes presentation until another explicit gesture. Async work cannot reopen it.
    static func suspend() {
        let wasAuthorized = presentationAuthorized
        presentationAuthorized = false
        for window in NSApp.windows where window is ProtectedPanel { window.orderOut(nil) }
        if wasAuthorized { NotificationCenter.default.post(name: .copilotePresentationSuspended, object: nil) }
    }
}

extension Notification.Name {
    static let copilotePresentationSuspended = Notification.Name("CopilotePresentationSuspended")
}
