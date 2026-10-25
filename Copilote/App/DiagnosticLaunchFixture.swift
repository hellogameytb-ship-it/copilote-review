import AppKit
import CopiloteKit

/// The real AppDelegate launch path, with isolated preferences, a fake provider and an empty base.
/// A previous visible workspace is seeded without killing or inspecting the user's process.
@MainActor
enum DiagnosticLaunchFixture {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-CopiloteLaunchFixture") }
    private static var suite: String?
    static var historyURL: URL? { output?.appendingPathComponent("history.sqlite") }
    private static var output: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-CopiloteLaunchFixture"), args.indices.contains(i + 1) else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }
    static func settings() -> SettingsStore? {
        guard let output else { return nil }
        let name = "org.example.copilote.recette.launch.\(UUID().uuidString)"
        suite = name
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(!ProcessInfo.processInfo.arguments.contains("-FixtureStealthOff"), forKey: "stealth")
        defaults.set(output.appendingPathComponent("empty-base").path, forKey: "baseFolder")
        defaults.set(true, forKey: "stickyNotesVisible")
        defaults.set(false, forKey: "onboardingDone")
        defaults.set("{{0, 0}, {760, 760}}", forKey: "CopiloteMainWindow")
        defaults.set(NSStringFromSize(NSSize(width: 760, height: 760)), forKey: "panelSize")
        let note = StickyNote(text: "Fictional note from a previous run", frame: CGRect(x: 50, y: 50, width: 280, height: 220))
        defaults.set(try? JSONEncoder().encode([note]), forKey: "stickyNotesV1")
        return SettingsStore(defaults: defaults, loadCredentials: false)
    }
    static func schedule(delegate: AppDelegate, overlay: OverlayController, listening: ListeningController, settings: SettingsStore) {
        guard let output, let suite else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1000))
            var checks: [[String: Any]] = []
            func record(_ name: String, _ passed: Bool) { checks.append(["name": name, "passed": passed]) }
            record("real application launch is hidden with saved notes and unfinished onboarding", NSApp.windows.allSatisfy { !$0.isVisible } && !WindowPrivacy.presentationAuthorized)
            record("real application launch never resumes listening", listening.state == .idle && listening.startedDate == nil)
            record("saved Stealth preference is preserved at launch", settings.stealth == !ProcessInfo.processInfo.arguments.contains("-FixtureStealthOff"))
            record("secure restoration is declined", !delegate.applicationShouldRestoreSecureApplicationState(NSApp) && !delegate.applicationShouldSaveSecureApplicationState(NSApp))
            DiagnosticSnapshot.write(to: output.appendingPathComponent("hidden-launch"), spaceChanges: 0)
            for iteration in 1...3 {
                _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
                try? await Task.sleep(for: .milliseconds(200))
                record("real delegate explicit reopen \(iteration)", overlay.isVisible && overlay.model.isUnfolded && !listening.isListening)
                let body = NSApp.windows.first { $0.windowNumber == overlay.windowNumbers[1] }
                record("expanded saved size retained \(iteration)", body?.frame.size == NSSize(width: 760, height: 760))
                overlay.hide()
                NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
                try? await Task.sleep(for: .milliseconds(100))
                record("real callbacks keep hidden workspace hidden \(iteration)", NSApp.windows.allSatisfy { !$0.isVisible })
            }
            record("listening remains stopped through reopen cycles", listening.state == .idle)
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let report: [String: Any] = ["checks": checks, "pid": ProcessInfo.processInfo.processIdentifier, "realAppDelegate": true, "isolatedPreferences": true, "fakeProvider": true, "hardwareCapture": false, "actualOSCrashOrLoginTriggered": false]
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("launch.json"))
            settings.defaults.removePersistentDomain(forName: suite)
            NSApp.terminate(nil)
        }
    }
}
