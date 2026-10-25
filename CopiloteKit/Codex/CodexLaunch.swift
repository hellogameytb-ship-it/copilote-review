import Foundation

/// How Copilote starts `codex app-server`: the user's ChatGPT login is reused as is,
/// but nothing that could act on the Mac is available to the model.
public enum CodexLaunch {
    /// Shell, browser, computer use, plugins, apps, image generation, sub-agents, hooks…
    public static let disabledFeatures = [
        "shell_tool", "unified_exec", "shell_snapshot", "code_mode_host",
        "browser_use", "browser_use_external", "browser_use_full_cdp_access", "in_app_browser", "computer_use",
        "apps", "plugins", "remote_plugin", "image_generation", "multi_agent", "hooks", "goals", "tool_suggest",
        "workspace_dependencies", "skill_mcp_dependency_install",
    ]

    /// `userConfig` is the user's `~/.codex/config.toml`: its MCP servers are switched off by name.
    /// `privateDirectory` receives Codex's logs and databases (see `environment`).
    public static func arguments(userConfig: String?, privateDirectory: String) -> [String] {
        var arguments = ["app-server", "--listen", "stdio://"]
        for feature in disabledFeatures { arguments += ["--disable", feature] }
        arguments += ["-c", #"web_search="disabled""#, "-c", "notify=[]", "-c", #"log_dir="\#(privateDirectory)/log""#]
        // Servers provided by plugins are covered by `--disable plugins`; overriding them by name
        // would create invalid entries ("invalid transport"), so only declared ones are listed.
        for name in mcpServerNames(in: userConfig ?? "") {
            arguments += ["-c", "mcp_servers.\(name).enabled=false"]
        }
        return arguments
    }

    /// Codex records every request's text in `logs_2.sqlite`, ephemeral threads included:
    /// its databases go to `privateDirectory` (wiped by Copilote), not to ~/.codex, where the
    /// ChatGPT login stays untouched (CODEX_HOME is not changed). `codex` is a Node script
    /// (`#!/usr/bin/env node`): its folder and Homebrew's go first in PATH, which apps
    /// launched from the Finder don't inherit.
    public static func environment(base: [String: String], executable: URL, privateDirectory: String) -> [String: String] {
        var environment = base
        environment["CODEX_SQLITE_HOME"] = privateDirectory
        let folders = [executable.resolvingSymlinksInPath().deletingLastPathComponent().path, executable.deletingLastPathComponent().path,
                       "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        var path: [String] = []
        for folder in folders + (base["PATH"]?.split(separator: ":").map(String.init) ?? []) where !path.contains(folder) {
            path.append(folder)
        }
        environment["PATH"] = path.joined(separator: ":")
        return environment
    }

    /// Why Codex must not be started with this config, if any. Fails closed: any mention of
    /// `mcp_servers` other than a `[mcp_servers.<name>]` table (or its sub-tables) cannot be
    /// switched off by name, and a selected profile could turn features back on.
    public static func problem(inUserConfig config: String) -> String? {
        for line in lines(of: config) where !line.hasPrefix("#") {
            if line.contains("mcp_servers"), line.wholeMatch(of: serverTable) == nil {
                return "MCP server configuration cannot be disabled safely in ~/.codex/config.toml: \(line)"
            }
            if line.wholeMatch(of: /profile\s*=.*/) != nil {
                return "A Codex profile is selected in ~/.codex/config.toml (« \(line) ») : it could re-enable tools."
            }
        }
        return nil
    }

    /// `service_tier = "priority"` before any table: the user runs Codex in "Fast" mode.
    public static func prefersFastTier(userConfig config: String?) -> Bool {
        for line in lines(of: config ?? "") where !line.hasPrefix("#") {
            if line.hasPrefix("[") { return false }
            if line.wholeMatch(of: /service_tier\s*=\s*"priority"/) != nil { return true }
        }
        return false
    }

    /// `[mcp_servers.<name>]` tables (not their `.env` sub-tables), bare TOML keys only.
    static func mcpServerNames(in config: String) -> [String] {
        var names: [String] = []
        for line in lines(of: config) {
            if let match = line.wholeMatch(of: serverTable), match.2.isEmpty, !names.contains(String(match.1)) {
                names.append(String(match.1))
            }
        }
        return names
    }

    /// `[mcp_servers.<name>]` or a sub-table such as `[mcp_servers.<name>.env]`.
    private static let serverTable = /\[mcp_servers\.([A-Za-z0-9_-]+)((?:\.[A-Za-z0-9_-]+)*)\]/

    /// Trimmed lines; `\r\n` counts as one line break.
    private static func lines(of config: String) -> [String] {
        config.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
