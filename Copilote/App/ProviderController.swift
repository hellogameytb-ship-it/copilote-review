import AppKit
import CopiloteKit

/// Which service answers right now, from the setting and what is installed. One Codex process
/// is kept warm for the whole app when Codex is the active provider.
@MainActor
final class ProviderController: ObservableObject {
    enum CodexState: Equatable {
        case checking
        case ready
        case notInstalled
        case notLoggedIn
        /// Installed and logged in, but its config can't be locked down (see `CodexLaunch.problem`).
        case blocked(String)
    }

    @Published private(set) var codexState: CodexState = .checking

    private let settings: SettingsStore
    /// One client for the app: it keeps the HTTP connection warm between requests.
    private let anthropicClient = AnthropicClient()
    private var codexServer: CodexAppServer?
    private var codexExecutable: URL?
    private var isDetecting = false
    private var activation: NSObjectProtocol?

    private let injectedProvider: (any LLMProvider)?
    private let observesEnvironment: Bool

    init(settings: SettingsStore, injectedProvider: (any LLMProvider)? = nil, observesEnvironment: Bool = true) {
        self.settings = settings
        self.injectedProvider = injectedProvider
        self.observesEnvironment = observesEnvironment
        guard observesEnvironment else { codexState = .notInstalled; return }
        // Leftovers of a run that crashed: Codex's private logs hold request text.
        try? FileManager.default.removeItem(at: CodexAvailability.privateDirectory)
        // Back from `codex login` in a terminal (or an uninstall): look again.
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.detectCodex() }
        }
    }

    /// Looks for `codex`, its login and its config (in the background), then warms it up if active.
    func detectCodex() {
        guard observesEnvironment, !isDetecting else { return }
        isDetecting = true
        Task.detached(priority: .utility) {
            let executable = CodexAvailability.locate()
            let loggedIn = executable.map(CodexAvailability.isReady) ?? false
            let problem = Self.configProblem()
            await MainActor.run { self.apply(executable: executable, loggedIn: loggedIn, problem: problem) }
        }
    }

    private func apply(executable: URL?, loggedIn: Bool, problem: String?) {
        isDetecting = false
        if let executable, loggedIn, problem == nil {
            // Same CLI: the warm process stays.
            if codexServer == nil || codexExecutable != executable {
                codexServer?.terminateNow()
                codexServer = CodexAppServer(
                    executable: executable, workingDirectory: CodexAvailability.workingDirectory,
                    privateDirectory: CodexAvailability.privateDirectory, loadUserConfig: { try CodexAvailability.userConfig() }
                )
                codexExecutable = executable
            }
            codexState = .ready
        } else {
            codexServer?.terminateNow()
            codexServer = nil
            codexExecutable = nil
            if executable == nil {
                codexState = .notInstalled
            } else if !loggedIn {
                codexState = .notLoggedIn
            } else {
                codexState = .blocked(problem ?? "")
            }
        }
        if activeKind == .codex { Task { await current()?.warmUp() } }
    }

    private nonisolated static func configProblem() -> String? {
        do {
            return CodexLaunch.problem(inUserConfig: try CodexAvailability.userConfig() ?? "")
        } catch {
            return (error as? CodexFailure)?.message ?? error.localizedDescription
        }
    }

    private var choice: ProviderChoice { ProviderChoice(rawValue: settings.provider) ?? .automatic }

    /// Automatic waits for the detection (a fraction of a second) rather than spending the API key.
    private var isWaitingForDetection: Bool { choice == .automatic && codexState == .checking }

    var activeKind: ProviderKind { choice.resolved(codexReady: codexState == .ready) }

    /// The provider to use now, or nil with the reason in `unavailableReason`.
    func current() -> (any LLMProvider)? {
        if !observesEnvironment { return injectedProvider }
        guard !isWaitingForDetection else { return nil }
        switch activeKind {
        case .codex:
            guard let codexServer else { return nil }
            return CodexProvider(
                server: codexServer, answerModel: settings.codexModel,
                // Topic decisions stay on the fastest model whatever answers.
                topicModel: CodexProvider.defaultModel,
                serviceTier: settings.codexFast ? "priority" : nil
            )
        case .anthropic:
            return settings.apiKey.map { AnthropicProvider(client: anthropicClient, apiKey: $0, settings: settings.modelSettings) }
        }
    }

    /// Why `current()` is nil, in French, for the overlay.
    var unavailableReason: String {
        if isWaitingForDetection { return "Detecting Codex…" }
        switch activeKind {
        case .codex: return codexProblem ?? "Codex unavailable"
        case .anthropic: return "No Anthropic API key: ⚙ › Settings"
        }
    }

    /// The welcome's line: Codex ready, or why not, and whether an Anthropic key answers instead.
    /// No Keychain read (`hasAPIKey` is cached): the welcome asks every second.
    var welcomeLine: (isCodexReady: Bool, detail: String) {
        guard let problem = codexProblem else { return (true, activeDescription) }
        return (false, settings.hasAPIKey ? problem + " · " + activeDescription : problem)
    }

    /// Why Codex can't answer, or nil when it is ready.
    var codexProblem: String? {
        switch codexState {
        case .checking: return "Detecting Codex…"
        case .ready: return nil
        case .notInstalled: return "Codex not found: install the CLI or choose Anthropic"
        case .notLoggedIn: return "Codex is not signed in: run codex login"
        case let .blocked(reason): return "Codex blocked: \(reason)"
        }
    }

    /// Shown in the settings, e.g. "Codex · gpt-5.6-luna (ChatGPT subscription)".
    var activeDescription: String {
        if isWaitingForDetection { return "Detecting Codex…" }
        switch activeKind {
        case .codex:
            if let codexProblem { return "None (\(codexProblem))" }
            return "Codex · \(settings.codexModel) (ChatGPT subscription)"
        case .anthropic:
            let source = settings.hasAPIKey ? "API key" : "no API key saved"
            return "Anthropic · \(settings.modelSettings.model) (\(source))"
        }
    }

    /// A provider's failure in French, for the overlay and the notes.
    static func describe(_ error: Error) -> String {
        switch error {
        case let failure as APIFailure: return failure.userMessage
        case let failure as CodexFailure: return failure.userMessage
        case let urlError as URLError where urlError.code == .notConnectedToInternet: return "No internet connection."
        case let urlError as URLError where urlError.code == .timedOut: return "Timed out waiting for the provider."
        default: return "Error: \(error.localizedDescription)"
        }
    }

    /// At quit: synchronous, the app won't wait for a task.
    func stop() {
        codexServer?.terminateNow()
    }
}
