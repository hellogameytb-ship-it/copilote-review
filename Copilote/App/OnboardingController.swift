import AppKit
import AVFoundation
import CopiloteKit
import SwiftUI

/// The first-launch welcome (retours 5), in a small panel hung under the pill like the answers,
/// never a window in the middle of the screen nor on another Space: what Copilote does, the two
/// permissions, Codex, the personal base, the four shortcuts, the stealth mode. The states turn
/// green as they are granted. Replayable from ⚙.
@MainActor
final class OnboardingController: ObservableObject {
    @Published private(set) var onboarding = Onboarding()
    @Published private(set) var status = OnboardingStatus()
    /// The pill's frame: the welcome hangs under it.
    var anchor: (() -> NSRect)?
    private let settings: SettingsStore
    private let providers: ProviderController
    private let base: BaseController
    private var window: OverlayPanel?
    private var host: NSView?
    /// Permissions are granted in System Settings, another app: read again every second.
    private var poll: Timer?

    init(settings: SettingsStore, providers: ProviderController, base: BaseController) {
        self.settings = settings
        self.providers = providers
        self.base = base
    }

    var isRunning: Bool { window?.isVisible == true }

    func startIfFirstLaunch() {
        if !settings.onboardingDone { start(Onboarding(resumingAt: settings.onboardingStep)) }
    }

    /// From ⚙: from the start.
    func start() {
        start(Onboarding())
    }

    private func start(_ onboarding: Onboarding) {
        self.onboarding = onboarding
        refresh()
        let window = window ?? makeWindow()
        self.window = window
        layout()
        window.orderFrontRegardless()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func next() {
        onboarding.next()
        onboarding.isFinished ? finish() : relayout()
    }

    func back() {
        onboarding.back()
        relayout()
    }

    func finish() {
        onboarding.finish()
        settings.onboardingDone = true
        settings.onboardingStep = 0
        poll?.invalidate()
        poll = nil
        window?.orderOut(nil)
    }

    /// Under the pill, wherever it goes.
    func layout() {
        guard let window, let host else { return }
        let size = host.fittingSize
        let pill = anchor?() ?? NSScreen.main.map { NSRect(x: $0.visibleFrame.midX, y: $0.visibleFrame.maxY, width: 0, height: 0) } ?? .zero
        window.setFrame(
            NSRect(x: pill.midX - size.width / 2, y: pill.minY - OverlayPlacement.gap - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    /// The next step may be taller: the panel grows downwards, its top under the pill.
    private func relayout() {
        if !settings.onboardingDone { settings.onboardingStep = onboarding.step.rawValue }
        refresh()
        DispatchQueue.main.async { [weak self] in self?.layout() }
    }

    func refresh() {
        let codex = providers.welcomeLine
        let next = OnboardingStatus(
            permissions: PermissionState(screen: ScreenCapturer.hasPermission, microphone: MicrophoneCapture.permission == .authorized),
            codexReady: codex.isCodexReady,
            codexDetail: codex.detail,
            basePath: (settings.baseFolder as NSString).abbreviatingWithTildeInPath,
            baseItems: base.status.items,
            isStealth: settings.stealth,
            labels: ShortcutLabels.current
        )
        guard next != status else { return }
        status = next
        // A button gone or a longer line: the panel is re-hung under the pill.
        DispatchQueue.main.async { [weak self] in self?.layout() }
    }

    /// Its window, for captures to leave out like the overlay's.
    var windowNumbers: [Int] { window.map { [$0.windowNumber] } ?? [] }

    /// ⌥⌘O hid the pill: the welcome goes with it, and comes back with it.
    func setHidden(_ hidden: Bool) {
        guard let window, !onboarding.isFinished, poll != nil else { return }
        if hidden { window.orderOut(nil) } else { layout(); window.orderFrontRegardless() }
    }

    private var askedForScreen = false

    /// The first press: macOS's own prompt (it has its button to System Settings); after that, the
    /// System Settings pane. Never both at once.
    fileprivate func openScreenSettings() {
        if askedForScreen { return ScreenCapturer.openPrivacySettings() }
        askedForScreen = true
        _ = ScreenCapturer.requestPermission()
    }

    /// Not asked yet: macOS asks now. Refused before: only System Settings can change it.
    fileprivate func openMicrophoneSettings() {
        guard MicrophoneCapture.permission == .notDetermined else { return MicrophoneCapture.openPrivacySettings() }
        Task {
            _ = await MicrophoneCapture.requestPermission()
            refresh()
        }
    }

    fileprivate func retryCodex() {
        providers.detectCodex()
        refresh()
    }

    fileprivate func openBase() {
        let folder = URL(fileURLWithPath: settings.baseFolder, isDirectory: true)
        NSWorkspace.shared.open(folder)
    }

    /// A floating panel like the overlay's (non-activating, hidden from screen sharing): its
    /// buttons take the first click without taking the keyboard from the call.
    private func makeWindow() -> OverlayPanel {
        let window = OverlayPanel(size: NSSize(width: 440, height: 300), resizable: false)
        let host = FirstMouseHostingView(rootView: OnboardingHost(controller: self))
        window.contentView = OverlayController.surface(hosting: host, cornerRadius: 12)
        self.host = host
        return window
    }
}

private struct OnboardingHost: View {
    @ObservedObject var controller: OnboardingController

    var body: some View {
        OnboardingStepView(
            onboarding: controller.onboarding, status: controller.status,
            onOpenScreenSettings: controller.openScreenSettings, onOpenMicrophoneSettings: controller.openMicrophoneSettings,
            onRetryCodex: controller.retryCodex, onOpenBase: controller.openBase,
            onBack: controller.back, onNext: controller.next, onSkip: controller.finish
        )
    }
}
