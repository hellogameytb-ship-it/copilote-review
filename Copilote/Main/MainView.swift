import AVFoundation
import CopiloteKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Main window (normal mode only): settings on the left, the session's answers on the right.
struct MainView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var session: SessionController
    @ObservedObject var listening: ListeningController
    @ObservedObject var providers: ProviderController
    @ObservedObject var base: BaseController
    @ObservedObject var history: HistoryController
    let onStealth: (Bool) -> Void
    var onMenuBarChange: () -> Void = {}
    var onTour: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            SettingsForm(
                settings: settings, listening: listening, providers: providers, base: base, history: history,
                onStealth: onStealth, onShortcutChange: session.refreshShortcutHints, onMenuBarChange: onMenuBarChange, onTour: onTour
            )
                .frame(width: 420)
            Divider()
            VStack(spacing: 0) {
                HistoryBrowser(
                    isRecording: history.isRecording, sessions: history.sessions, query: $history.query, selection: $history.selection,
                    opened: history.opened, onExport: history.export, onDelete: history.delete
                )
                if !history.isRecording, !session.history.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Copy.History.thisRun).font(.headline).padding([.top, .horizontal], 12)
                        HistoryList(entries: session.history)
                    }
                    .frame(maxHeight: 280)
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 600)
    }
}

private struct SettingsForm: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var listening: ListeningController
    @ObservedObject var providers: ProviderController
    @ObservedObject var base: BaseController
    @ObservedObject var history: HistoryController
    let onStealth: (Bool) -> Void
    let onShortcutChange: () -> Void
    let onMenuBarChange: () -> Void
    let onTour: () -> Void

    @State private var keyDraft = ""
    @State private var confirmsShortcutReset = false
    @State private var keyMessage: String?
    @State private var hasScreenPermission = ScreenCapturer.hasPermission

    var body: some View {
        Form {
            Section {
                Text("Copilote").font(.title3.weight(.semibold))
                Toggle(isOn: Binding(get: { settings.stealth }, set: onStealth)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.Settings.stealth)
                        Text(Copy.Settings.stealthHelp).font(.caption).foregroundStyle(.secondary)
                    }
                }
                LoginItemToggle()
            }

            ProviderSection(settings: settings, providers: providers)

            ListeningSection(settings: settings, listening: listening)

            MeetingSettingsSection(settings: settings, onHistoryChange: history.start, onMenuBarChange: onMenuBarChange, onTour: onTour)

            AnswerSettingsSection(settings: settings)

            BaseSection(settings: settings, base: base)

            Section("Anthropic API key") {
                if settings.hasAPIKey {
                    LabeledContent("Status") {
                        Label("Saved in Keychain", systemImage: "checkmark.seal")
                            .foregroundStyle(.secondary)
                    }
                }
                SecureField(settings.hasAPIKey ? "Replace API key" : "sk-ant-…", text: $keyDraft)
                    .onSubmit(saveKey)
                HStack {
                    if let keyMessage {
                        Text(keyMessage).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if settings.hasAPIKey {
                        Button("Delete", role: .destructive) {
                            settings.deleteAPIKey()
                            keyMessage = "API key deleted."
                        }
                    }
                    Button("Save", action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Anthropic") {
                TextField("Model ID", text: $settings.model, prompt: Text(ModelSettings.defaultModel))
                    .font(.body.monospaced())
                Picker("Effort", selection: $settings.effort) {
                    ForEach(SettingsStore.effortChoices, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
            }

            Section("Global shortcuts") {
                ForEach(ShortcutCatalog.all, id: \.name.rawValue) { shortcut in
                    KeyboardShortcuts.Recorder(shortcut.label, name: shortcut.name) { _ in onShortcutChange() }
                }
                Button(Copy.Settings.resetShortcuts) { confirmsShortcutReset = true }
                    .confirmationDialog(Copy.Settings.resetShortcutsQuestion, isPresented: $confirmsShortcutReset) {
                        Button(Copy.Settings.resetShortcutsConfirm, role: .destructive) {
                            ShortcutSetup.resetToDefaults()
                            onShortcutChange()
                        }
                    } message: {
                        Text(Copy.Settings.resetShortcutsHelp)
                    }
            }

            Section("Screen Recording") {
                if hasScreenPermission {
                    Label("Allowed", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    Text("Required for screenshots and system audio. Reopen Copilote after granting permission.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Request access") { hasScreenPermission = ScreenCapturer.requestPermission() }
                        Button("Open System Settings") { ScreenCapturer.openPrivacySettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasScreenPermission = ScreenCapturer.hasPermission
        }
    }

    private func saveKey() {
        guard !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        keyMessage = settings.saveAPIKey(keyDraft) ? "API key saved." : "Could not save the API key in Keychain."
        keyDraft = ""
    }
}

/// Who answers and segments topics: Codex (ChatGPT subscription) or Anthropic (API key).
private struct ProviderSection: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var providers: ProviderController

    var body: some View {
        Section("Provider") {
            LabeledContent("Active") {
                Text(providers.activeDescription).fontWeight(.medium)
            }
            Picker("Choice", selection: $settings.provider) {
                Text("Automatic (Codex when signed in)").tag(ProviderChoice.automatic.rawValue)
                Text("Codex · ChatGPT subscription").tag(ProviderChoice.codex.rawValue)
                Text("Anthropic · API key").tag(ProviderChoice.anthropic.rawValue)
            }
            LabeledContent("Codex") {
                Text(codexStatus).foregroundStyle(.secondary)
            }
            Picker("Codex model", selection: $settings.codexModel) {
                Text("gpt-5.6-luna (fastest)").tag("gpt-5.6-luna")
                Text("gpt-5.6-sol").tag("gpt-5.6-sol")
                Text("gpt-5.6-terra").tag("gpt-5.6-terra")
            }
            Toggle("Codex Fast mode (uses more quota)", isOn: $settings.codexFast)
            Text("Codex uses your existing CLI sign-in. No key is copied. Commands, file writes, "
                + "browsing and MCP tools are disabled. The first response may take longer "
                + "on a cold start.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var codexStatus: String {
        switch providers.codexState {
        case .checking: return "Detecting…"
        case .ready: return "Installed and signed in"
        case .notInstalled: return "Not found"
        case .notLoggedIn: return "Installed; sign in with codex login"
        case let .blocked(reason): return "Blocked: \(reason)"
        }
    }
}

/// Step 2: the listening session (transcription on the device, topic cases).
private struct ListeningSection: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var listening: ListeningController
    @State private var microphone = MicrophoneCapture.permission

    var body: some View {
        Section("Session") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status).foregroundStyle(statusIsError ? AnyShapeStyle(FicheStyle.danger) : AnyShapeStyle(.primary))
                    if !listening.segmenterStatus.isEmpty {
                        Text("Subjects: \(listening.segmenterStatus)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(listening.isListening ? "End session" : "Start session") { listening.toggle() }
                    .disabled(isStarting)
                    .help(ShortcutCatalog.keys(for: .toggleListening))
            }
            LabeledContent("Microphone (Me)") {
                switch microphone {
                case .authorized:
                    Text("Allowed").foregroundStyle(.secondary)
                case .denied, .restricted:
                    Button("Open System Settings") { MicrophoneCapture.openPrivacySettings() }
                default:
                    Text("Requested when starting a session").foregroundStyle(.secondary)
                }
            }
            Toggle(Copy.Settings.autoAnswer, isOn: $settings.autoAnswer)
            Text(Copy.Settings.autoAnswerHelp).font(.caption).foregroundStyle(.secondary)
            Text("On-device French and English transcription. Both sides stay in memory for the entire session; "
                + "there is no five-minute expiry. Interviewer turns are sent to the selected provider for subject grouping; "
                + "offline grouping uses keywords when no provider is available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphone = MicrophoneCapture.permission
        }
    }

    private var status: String {
        switch listening.state {
        case .idle: return "Idle"
        case let .starting(message): return message
        case .listening: return "Session active"
        case let .failed(message): return message
        }
    }

    private var statusIsError: Bool {
        if case .failed = listening.state { return true }
        return false
    }

    private var isStarting: Bool {
        if case .starting = listening.state { return true }
        return false
    }
}

private struct HistoryList: View {
    let entries: [HistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Session answers")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)
            if entries.isEmpty {
                Text("Nothing yet. \(ShortcutCatalog.keys(for: .captureScreen)) captures the screen; \(ShortcutCatalog.keys(for: .sendCaptures)) answers the screenshot stack.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                Spacer()
            } else {
                List(entries) { entry in
                    HistoryRow(entry: entry)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(entry.text.isEmpty ? "…" : entry.text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            Button("Copy answer") { Clipboard.copy(entry.text) }
                .disabled(entry.text.isEmpty)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.input).fontWeight(.medium)
                    Spacer()
                    Text(entry.date, style: .time).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(entry.note ?? "Working…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// « Open au démarrage du Mac » (off by default): the app as a login item, which macOS may ask
/// to approve in Settings Système.
private struct LoginItemToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?

    var body: some View {
        Toggle(isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: setOpensAtLogin)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.Settings.openAtLogin)
                if status == .requiresApproval {
                    Button(Copy.Settings.openAtLoginApprove) { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link)
                        .font(.caption)
                } else if let failure {
                    Text(failure).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failure = nil
        } catch {
            failure = Copy.Settings.openAtLoginFailed(error.localizedDescription)
        }
        status = SMAppService.mainApp.status
    }
}
