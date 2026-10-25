import AppKit
import CopiloteKit

/// Headless production-entry checks: no OS file panels, audio, capture or user app interaction.
@MainActor
enum DiagnosticDialogGuard {
    static func run(settings: SettingsStore, listening: ListeningController, overlay: OverlayController,
                    folder: URL, record: (String, Bool) -> Void) async {
        var invocations = 0
        SystemDialogs.diagnosticInvocation = { invocations += 1 }
        defer { SystemDialogs.diagnosticInvocation = nil; WindowPrivacy.suspend() }
        WindowPrivacy.observeSystemEnvironment { AppDelegate.suspendForSleep(overlay: overlay, listening: listening) }
        let center = NSWorkspace.shared.notificationCenter
        let history = HistoryController(settings: settings, storeURL: folder.appendingPathComponent("unused-history.sqlite"))
        let entry = SessionRecord.ended(started: Date(), duration: 30, mode: .meeting, lines: [], topics: [], answers: [], keepTranscript: false)
        func denied(_ label: String) async {
            let count = invocations
            do { _ = try await SystemDialogs.chooseFolder(); record(label + " folder refused", false) }
            catch { record(label + " folder refused inline", error.localizedDescription.contains("session") || error.localizedDescription.contains("explicitly")) }
            await history.export(entry)
            record(label + " export refused inline before native UI", history.exportNotice != nil && invocations == count)
        }
        await denied("hidden idle")
        for iteration in 1...3 {
            _ = WindowPrivacy.authorizeFromUserGesture()
            listening.beginRecetteStartup()
            await denied("starting \(iteration)")
            listening.suspendForPrivacy()
            for _ in 0..<40 {
                if listening.state == .idle { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            record("suspended startup returns to idle \(iteration)", listening.state == .idle)
            guard listening.state == .idle else { return }
            listening.beginRecetteConversation()
            await denied("listening \(iteration)")
            listening.pauseOrResume()
            await denied("paused \(iteration)")
            let before = invocations
            await listening.stop()
            record("ending a session never opens a deferred dialog \(iteration)", invocations == before)
            do { _ = try await SystemDialogs.chooseFolder(); await history.export(entry) }
            catch { record("idle explicit actions accepted \(iteration)", false) }
            record("idle explicit folder and export reach adapter \(iteration)", invocations == before + 2 && history.exportNotice == nil)
        }
        for (name, unavailable, available) in [
            ("console session", NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification),
            ("screens", NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification),
            ("computer", NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification)
        ] {
            _ = WindowPrivacy.authorizeFromUserGesture()
            listening.beginRecetteConversation()
            center.post(name: unavailable, object: nil)
            record("\(name) deactivation revokes display and pauses", !WindowPrivacy.presentationAuthorized && listening.isPaused)
            record("\(name) blocks even an attempted reveal gesture", !WindowPrivacy.authorizeFromUserGesture())
            center.post(name: available, object: nil)
            record("\(name) return never shows or resumes automatically", WindowPrivacy.environmentAvailable && !WindowPrivacy.presentationAuthorized && listening.isPaused)
            await listening.stop()
            await denied("\(name) returned but not explicitly shown")
        }
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        record("screen wake cannot override an inactive console session", !WindowPrivacy.authorizeFromUserGesture())
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        record("explicit gesture works after all availability gates clear", WindowPrivacy.authorizeFromUserGesture())
        record("no production panel can appear before login", NSApp.windows.filter { $0 is ProtectedPanel }.allSatisfy { !$0.canBecomeVisibleWithoutLogin })
        record("headless guard recipe shows no windows", NSApp.windows.allSatisfy { !$0.isVisible })
        record("headless guard recipe finishes with listening stopped", listening.state == .idle)
    }
}
