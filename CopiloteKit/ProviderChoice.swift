import Foundation

/// Which service answers and segments topics.
public enum ProviderKind: String, Sendable {
    /// The `codex` CLI, signed in with the user's ChatGPT subscription (no API key).
    case codex
    /// The Messages API with the key from the Keychain.
    case anthropic
}

/// The setting: automatic (Codex when ready), or forced.
public enum ProviderChoice: String, CaseIterable, Sendable {
    case automatic = "auto"
    case codex
    case anthropic

    public func resolved(codexReady: Bool) -> ProviderKind {
        switch self {
        case .automatic: return codexReady ? .codex : .anthropic
        case .codex: return .codex
        case .anthropic: return .anthropic
        }
    }
}

/// Finding the `codex` executable and its login state.
public enum CodexAvailability {
    public static func candidates(path: String, home: String) -> [String] {
        var places = path.split(separator: ":").map { "\($0)/codex" }
        for fallback in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex"] where !places.contains(fallback) {
            places.append(fallback)
        }
        return places
    }

    /// Output of `codex login status`: only a ChatGPT login (an API key would bill the API).
    public static func isLoggedIn(statusOutput: String) -> Bool {
        statusOutput.hasPrefix("Logged in using ChatGPT")
    }
}

extension CodexAvailability {
    /// The first `codex` executable found, if any.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        candidates(path: environment["PATH"] ?? "", home: NSHomeDirectory())
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    /// Runs `codex login status` (local, no request is made to the model).
    public static func isReady(executable: URL) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["login", "status"]
        process.environment = CodexLaunch.environment(
            base: ProcessInfo.processInfo.environment, executable: executable, privateDirectory: privateDirectory.path
        )
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return process.terminationStatus == 0 && isLoggedIn(statusOutput: text)
    }

    /// The user's Codex config (`$CODEX_HOME/config.toml`, default `~/.codex`), read only to switch
    /// its MCP servers off. nil when there is none; throws when it exists but can't be read
    /// (Codex must then not start: its servers could not be switched off).
    public static func userConfig(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String? {
        let home = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? (NSHomeDirectory() + "/.codex")
        let path = home + "/config.toml"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw CodexFailure(message: "cannot read \(path) : its MCP servers could not be disabled")
        }
    }

    /// A dedicated, empty working directory for Codex threads.
    public static var workingDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("copilote-codex-empty", isDirectory: true)
    }

    /// Codex's logs and databases while Copilote runs it (wiped on start and stop).
    public static var privateDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("copilote-codex-private", isDirectory: true)
    }
}
