import AppKit
import CopiloteKit

/// Exercises actual browser windows/controllers and real files in the isolated recipe directory.
@MainActor
enum DiagnosticFileBrowser {
    static func run(settings: SettingsStore, listening: ListeningController, folder: URL, record: (String, Bool) -> Void) async {
        let fm = FileManager.default
        let root = folder.appendingPathComponent("fictional-files").resolvingSymlinksInPath()
        let child = root.appendingPathComponent("Project Orion")
        let exported = root.appendingPathComponent("Session.md")
        defer { SystemDialogs.diagnosticBrowser?.cancel(); WindowPrivacy.suspend() }
        func browser() async throws -> ProtectedFileBrowser {
            for _ in 0..<40 {
                if let browser = SystemDialogs.diagnosticBrowser { return browser }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw NSError(domain: "Browser recipe timed out", code: 1)
        }
        func useRoot() throws { settings.defaults.set(try FileBrowserBookmark.create(root), forKey: "protectedFileBrowserFolderBookmark") }
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags, panel: NSWindow) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: panel.windowNumber, context: nil, characters: code == 49 ? " " : "", charactersIgnoringModifiers: code == 49 ? " " : "", isARepeat: false, keyCode: code)!
        }
        do {
            try fm.createDirectory(at: child, withIntermediateDirectories: true)
            try "Fictional source".write(to: root.appendingPathComponent("Orion.md"), atomically: true, encoding: .utf8)
            try useRoot()
            _ = WindowPrivacy.authorizeFromUserGesture()
            let pick = Task { try await SystemDialogs.chooseFolder() }
            let first = try await browser()
            try await Task.sleep(for: .milliseconds(200))
            record("actual application uses palette-guard subclass", NSApp is CopiloteApplication)
            record("browser is visible protected panel with floating level and login visibility disabled", first.panel.isVisible && first.panel.sharingType == .none && first.panel.level == .floating && !first.panel.canBecomeVisibleWithoutLogin)
            record("fixture browser reads only the bookmarked fixture directory", first.directory.path == root.path && first.entries.count == 2)
            do { _ = try await SystemDialogs.chooseFolder(); record("second browser refused", false) }
            catch { record("second browser refused inline", error is SystemDialogs.Refusal && SystemDialogs.diagnosticBrowser === first) }
            if let entry = first.entries.first(where: { $0.url.lastPathComponent == "Project Orion" }) { first.open(entry) }
            record("directory navigation uses real listed entry", first.directory.path == child.path)
            first.navigate(first.directory.deletingLastPathComponent())
            record("parent navigation returns to root", first.directory.path == root.path)
            first.path = child.path; first.go()
            record("typed path navigation reaches child", first.directory.path == child.path)
            first.path = "relative/path"; first.go()
            record("relative path refused inline", first.notice != nil && first.directory.path == child.path)
            first.navigate(root)
            let shortcut = key(49, [.control, .command], panel: first.panel)
            let globe = key(63, [.function], panel: first.panel)
            let arrow = key(123, [.function], panel: first.panel)
            record("palette guard scope excludes absent or other windows", !CharacterPaletteGuard.shouldSuppress(shortcut, window: nil))
            record("Fn arrows remain usable", !CharacterPaletteGuard.shouldSuppress(arrow, window: first.panel))
            let before = CharacterPaletteGuard.diagnosticBlockedEvents
            first.panel.sendEvent(shortcut); NSApp.sendEvent(globe)
            record("window and app dispatch swallow local palette gestures", CharacterPaletteGuard.diagnosticBlockedEvents == before + 2)
            record("palette shortcut key equivalent consumed", first.panel.performKeyEquivalent(with: shortcut))
            let actions = CharacterPaletteGuard.diagnosticBlockedActions
            first.panel.makeKey()
            NSApp.orderFrontCharacterPalette(nil)
            _ = NSApp.sendAction(#selector(NSApplication.orderFrontCharacterPalette(_:)), to: nil, from: first.panel)
            record("public palette action is refused for protected key window", CharacterPaletteGuard.diagnosticBlockedActions == actions + 2)
            DiagnosticSnapshot.write(to: folder.appendingPathComponent("browser"), spaceChanges: 0)
            first.navigate(child); first.accept()
            let chosen = try await pick.value
            record("folder selection returns selected URL and closes panel", chosen == child && !first.panel.isVisible && first.panel.contentView == nil && SystemDialogs.diagnosticBrowser == nil)
            let bookmark = try FileBrowserBookmark.resolve(settings.defaults.data(forKey: "protectedFileBrowserFolderBookmark")!)
            record("successful folder selection persists resolving bookmark", bookmark.path == child.path)

            let cancel = Task { try await SystemDialogs.chooseFolder() }
            let second = try await browser()
            record("next invocation restores bookmarked folder", second.directory.path == child.path)
            second.cancel()
            record("cancel returns nil without changing selection", try await cancel.value == nil)
            let close = Task { try await SystemDialogs.chooseFolder() }
            let closeBrowser = try await browser()
            _ = closeBrowser.windowShouldClose(closeBrowser.panel)
            record("window close completes cancellation", try await close.value == nil && !closeBrowser.panel.isVisible)
            let escape = Task { try await SystemDialogs.chooseFolder() }
            let escapeBrowser = try await browser()
            escapeBrowser.panel.sendEvent(key(53, [], panel: escapeBrowser.panel))
            try await Task.sleep(for: .milliseconds(100))
            let escaped = SystemDialogs.diagnosticBrowser == nil
            if !escaped { escapeBrowser.cancel() }
            let escapeResult = try await escape.value
            record("Escape cancels through actual window dispatch", escaped && escapeResult == nil)

            try useRoot()
            let save = Task { try await SystemDialogs.saveMarkdown("# Fictional notes\nOrion", name: "Session.md") }
            let saver = try await browser()
            saver.name = "../outside"; saver.accept()
            record("invalid export name remains inline without writing", saver.notice != nil && !fm.fileExists(atPath: exported.path))
            saver.name = "Session.md"; saver.accept(); try await save.value
            record("new Markdown export writes exact bytes", try String(contentsOf: exported) == "# Fictional notes\nOrion")
            let replace = Task { try await SystemDialogs.saveMarkdown("Updated", name: "Session.md") }
            let replacing = try await browser(); replacing.accept()
            record("existing destination requires inline confirmation", replacing.replacement != nil && (try String(contentsOf: exported)) == "# Fictional notes\nOrion")
            DiagnosticSnapshot.write(to: folder.appendingPathComponent("overwrite"), spaceChanges: 0)
            replacing.keepExisting()
            record("keep existing clears confirmation without writing", replacing.replacement == nil && replacing.panel.isVisible)
            replacing.accept()
            try "Changed independently".write(to: exported, atomically: true, encoding: .utf8)
            replacing.confirmReplacement()
            record("changed target invalidates confirmation", replacing.replacement == nil && replacing.notice != nil && (try String(contentsOf: exported)) == "Changed independently")
            replacing.accept(); replacing.confirmReplacement(); try await replace.value
            record("fresh confirmation atomically replaces file", try String(contentsOf: exported) == "Updated")

            let link = root.appendingPathComponent("alias.md")
            try fm.createSymbolicLink(at: link, withDestinationURL: exported)
            let symlinkSave = Task { try await SystemDialogs.saveMarkdown("Never", name: "alias.md") }
            let linked = try await browser(); linked.accept()
            record("symlink destination refused inside browser", linked.notice != nil && linked.replacement == nil && (try String(contentsOf: exported)) == "Updated")
            linked.cancel(); try await symlinkSave.value
            let canceledSave = Task { try await SystemDialogs.saveMarkdown("Never", name: "Canceled.md") }
            let canceled = try await browser(); canceled.cancel(); try await canceledSave.value
            record("cancel export creates no file", !fm.fileExists(atPath: root.appendingPathComponent("Canceled.md").path))

            let interrupted = Task { try await SystemDialogs.chooseFolder() }
            let interruptedBrowser = try await browser()
            listening.beginRecetteConversation()
            do { _ = try await interrupted.value; record("session invalidation fails pending browser", false) }
            catch { record("session invalidation closes pending browser", error is SystemDialogs.Refusal && !interruptedBrowser.panel.isVisible) }
            listening.pauseOrResume()
            do { _ = try await SystemDialogs.chooseFolder(); record("paused session still refused", false) }
            catch { record("paused session still refused", error is SystemDialogs.Refusal) }
            await listening.stop()
            record("stop never reopens canceled browser", SystemDialogs.diagnosticBrowser == nil)

            let suspend = Task { try await SystemDialogs.saveMarkdown("Never", name: "Suspended.md") }
            let suspended = try await browser(); WindowPrivacy.suspend()
            do { try await suspend.value; record("suspension fails pending export", false) }
            catch { record("suspension closes pending export without writing", error is SystemDialogs.Refusal && !suspended.panel.isVisible && !fm.fileExists(atPath: root.appendingPathComponent("Suspended.md").path)) }
            do { _ = try await SystemDialogs.chooseFolder(); record("hidden browser refused", false) }
            catch { record("hidden browser refused without creating panel", error is SystemDialogs.Refusal && SystemDialogs.diagnosticBrowser == nil) }
            _ = WindowPrivacy.authorizeFromUserGesture()
            let cancellation = Task { try await SystemDialogs.chooseFolder() }
            let taskBrowser = try await browser(); cancellation.cancel()
            do { _ = try await cancellation.value; record("task cancellation throws", false) }
            catch { record("task cancellation closes panel and completes once", error is CancellationError && !taskBrowser.panel.isVisible) }

            settings.requestStealth(false, from: .settings); if let request = settings.pendingStealthOff { settings.confirmStealthOff(request.id) }
            let off = Task { try await SystemDialogs.chooseFolder() }
            let offBrowser = try await browser()
            record("Stealth OFF browser uses readOnly and regular policy", offBrowser.panel.sharingType == .readOnly && NSApp.activationPolicy() == .regular)
            settings.requestStealth(true, from: .settings)
            record("Stealth ON updates open browser policy", offBrowser.panel.sharingType == .none && NSApp.activationPolicy() == .accessory)
            offBrowser.cancel(); _ = try await off.value
            record("all recipe windows stay in ProtectedPanel hierarchy", NSApp.windows.allSatisfy { $0 is ProtectedPanel || !$0.isVisible })
            record("no temporary export files remain", !(try fm.contentsOfDirectory(atPath: root.path)).contains { $0.hasPrefix(".copilote-export-") })
        } catch { record("browser recipe completed without unexpected error: \(error.localizedDescription)", false) }
    }
}
