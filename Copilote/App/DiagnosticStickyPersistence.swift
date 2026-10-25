import AppKit

/// Two separate app launches share one isolated suite; no production notes or preferences.
@MainActor
enum DiagnosticStickyPersistence {
    static func startIfAsked() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-RecetteStickyPersistence"), args.indices.contains(flag + 2),
              let output = args.firstIndex(of: "-CopiloteRecette"), args.indices.contains(output + 1) else { return false }
        let phase = args[flag + 1], suite = args[flag + 2]
        guard ["write", "read"].contains(phase), suite.hasPrefix("org.example.copilote.recette.persistence.") else { return false }
        let folder = URL(fileURLWithPath: args[output + 1], isDirectory: true)
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults, loadCredentials: false)
        WindowPrivacy.observe(settings)
        WindowPrivacy.authorizeFromUserGesture()
        let notes = StickyNotesController(settings: settings)
        var checks: [[String: Any]] = []
        func record(_ name: String, _ passed: Bool) { checks.append(["name": name, "passed": passed]) }
        if phase == "write" {
            notes.add(); notes.add()
            let first = notes.notes[0].id, second = notes.notes[1].id
            notes.setText("Prepared pitch: Orion uses Swift and SQLite.", for: first)
            notes.togglePin(first)
            notes.setText("Question to ask: how is success measured?", for: second)
            notes.setIncluded(true, for: second)
            notes.delete(second)
            record("two notes saved with pin, consent and recoverable deletion", notes.notes.count == 2 && notes.hasDeleted)
            record("isolated preferences synchronized before process exit", defaults.synchronize())
        } else {
            record("notes loaded in a separate app process", notes.notes.count == 2)
            record("prepared text and pin survived quit", notes.notes.first?.text.contains("Orion uses Swift") == true && notes.notes.first?.isPinned == true)
            record("private default and deletion survived quit", notes.notes.first?.includeInAI == false && notes.hasDeleted && notes.includedContext.isEmpty)
            notes.restoreLastDeleted()
            record("deleted note restored after relaunch with its explicit consent", notes.notes.last?.text.contains("how is success measured") == true && notes.includedContext.count == 1)
            record("note windows restored on available screens", notes.notes.allSatisfy { notes.isWindowVisible($0.id) })
            notes.closeAll()
            defaults.removePersistentDomain(forName: suite); defaults.synchronize()
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let report: [String: Any] = ["phase": phase, "pid": ProcessInfo.processInfo.processIdentifier, "bundle": Bundle.main.bundleURL.path, "checks": checks, "globalAccessibilitySettingsChanged": false]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("sticky-persistence-\(phase).json"))
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }
}
