import AppKit
import CopiloteKit

/// Faults affect only this isolated fixture process. No desktop capture, hardware or real provider.
@MainActor
enum DiagnosticPresentation {
    static func run(settings: SettingsStore, session: SessionController, listening: ListeningController,
                    overlay: OverlayController, mainWindow: MainWindowController,
                    welcome: OnboardingController, menu: PillMenuController, fake: RecetteProvider,
                    folder: URL, record: (String, Bool) -> Void) async {
        func pause(_ ms: Int = 150) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func hidden() -> Bool { NSApp.windows.allSatisfy { !$0.isVisible } }
        let panel = OverlayPanel(size: NSSize(width: 320, height: 200))
        panel.contentView = NSTextField(labelWithString: "Own protected fixture")
        record("fresh fixture is hidden and listening stopped", hidden() && !listening.isListening && !WindowPrivacy.presentationAuthorized)
        for iteration in 1...3 {
            panel.order(.above, relativeTo: 0); panel.orderFront(nil); panel.orderFrontRegardless(); panel.makeKeyAndOrderFront(nil)
            mainWindow.show(); welcome.start(); session.stickyNotes.add()
            menu.toggle(PillMenuContent.menu(for: PillState()), anchor: overlay.pillFrame) { _ in }
            overlay.reveal(); overlay.showAutomatic(); overlay.startTyping()
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            await pause()
            record("unrequested ordering blocks all surfaces and layout restoration \(iteration)", hidden())
            menu.close(restoringKeyboard: false); welcome.finish()
        }
        // Selection uses generated pixels only, exercising the real region panel without capture.
        if let screen = NSScreen.main {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let selector = RegionSelector()
            let result = await selector.select(from: bitmap.cgImage!, on: screen)
            record("blocked region selector returns without a window or stuck continuation", result == nil && !selector.isSelecting && hidden())
        }
        for iteration in 1...3 {
            AppDelegate.reopen(overlay: overlay); await pause()
            record("explicit reopen shows expanded native group \(iteration)", overlay.isVisible && overlay.model.isUnfolded && NSApp.windows.filter { $0 is ProtectedPanel && $0.isVisible }.allSatisfy { $0.sharingType == .none })
            record("reopen never starts listening \(iteration)", !listening.isListening)
            overlay.hide()
            overlay.reveal(); overlay.showAutomatic(); panel.orderFrontRegardless()
            NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            await pause()
            record("late work wake and screen callbacks stay hidden \(iteration)", hidden() && !WindowPrivacy.presentationAuthorized)
        }
        AppDelegate.reopen(overlay: overlay)
        panel.sharingType = .readOnly
        panel.orderFrontRegardless()
        record("sharing request applied before order even after local drift", panel.isVisible && panel.sharingType == .none)
        WindowPrivacy.diagnosticFailure = true
        panel.orderFrontRegardless(); await pause()
        record("injected local policy failure closes every app surface", hidden() && !WindowPrivacy.presentationAuthorized && settings.stealth)
        record("failed local protection cannot authorize presentation", !WindowPrivacy.authorizeFromUserGesture() && hidden())
        WindowPrivacy.diagnosticFailure = false
        panel.orderFrontRegardless()
        record("fault recovery does not display automatically or turn Stealth off", hidden() && settings.stealth)
        AppDelegate.reopen(overlay: overlay)
        NSApp.setActivationPolicy(.regular)
        panel.orderFrontRegardless(); await pause()
        record("inconsistent activation policy fails closed", hidden() && settings.stealth && !WindowPrivacy.presentationAuthorized)
        AppDelegate.reopen(overlay: overlay)
        let question = AssistQuestion(action: .answer, mode: .meeting, question: "Describe a fictional queue", heard: [], context: AssistContext(), typed: true)
        await fake.delayNext()
        session.assist(question, label: "delayed fixture", topic: nil)
        overlay.hide(); await pause(1400)
        record("late provider completion cannot reopen a hidden workspace", hidden() && !WindowPrivacy.presentationAuthorized)
        await fake.failNext()
        session.assist(question, label: "failure while hidden", topic: nil); await pause(500)
        record("provider error stays hidden without dialogs", hidden())
        AppDelegate.reopen(overlay: overlay)
        listening.beginRecetteConversation()
        AppDelegate.suspendForSleep(overlay: overlay, listening: listening); await pause()
        record("sleep handler hides workspace and pauses a controlled session", hidden() && listening.isPaused)
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil); await pause()
        record("wake does not show or resume", hidden() && listening.isPaused)
        await listening.stop()
        settings.stealth = false
        record("explicit Stealth OFF persists without presenting hidden windows", !WindowPrivacy.enabled && hidden() && !SettingsStore(defaults: settings.defaults, loadCredentials: false).stealth)
        AppDelegate.reopen(overlay: overlay); mainWindow.show(); await pause()
        record("explicit OFF presentation uses shareable panels", overlay.isVisible && NSApp.windows.filter { $0 is ProtectedPanel && $0.isVisible }.allSatisfy { $0.sharingType == .readOnly } && NSApp.activationPolicy() == .regular)
        settings.stealth = true; await pause()
        record("explicit ON updates every existing panel", NSApp.windows.filter { $0 is ProtectedPanel }.allSatisfy { $0.sharingType == .none } && NSApp.activationPolicy() == .accessory)
        record("all overlay surfaces opt out of state restoration", NSApp.windows.filter { $0 is OverlayPanel }.allSatisfy { !$0.isRestorable })
        DiagnosticSnapshot.write(to: folder.appendingPathComponent("explicit-reopen"), spaceChanges: 0)
        mainWindow.close(); welcome.finish(); menu.close(restoringKeyboard: false); session.clear(); overlay.hide()
        record("presentation audit finished hidden and idle", hidden() && !listening.isListening)
    }
}
