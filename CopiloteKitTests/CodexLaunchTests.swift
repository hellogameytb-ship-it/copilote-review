import XCTest
@testable import CopiloteKit

/// Copilote only wants text out of Codex: everything that could act on the Mac is switched off.
final class CodexLaunchTests: XCTestCase {
    func test_runsTheAppServerOnStdio_withEveryToolThatCouldActOnTheMacSwitchedOff() {
        let arguments = CodexLaunch.arguments(userConfig: nil, privateDirectory: "/tmp/copilote-codex-private")

        XCTAssertEqual(Array(arguments.prefix(3)), ["app-server", "--listen", "stdio://"])
        for feature in ["shell_tool", "unified_exec", "computer_use", "browser_use", "in_app_browser", "apps", "plugins",
                        "image_generation", "multi_agent", "hooks", "code_mode_host"] {
            XCTAssertTrue(arguments.contains(pair: "--disable", feature), feature)
        }
        XCTAssertTrue(arguments.contains(pair: "-c", #"web_search="disabled""#))
        XCTAssertTrue(arguments.contains(pair: "-c", "notify=[]"))
    }

    /// Codex logs every request's text in its own databases, ephemeral threads included: they go to
    /// a private folder Copilote wipes, never to ~/.codex (where the ChatGPT login stays).
    func test_codexLogsAndDatabasesGoToAPrivateFolder() {
        let arguments = CodexLaunch.arguments(userConfig: nil, privateDirectory: "/tmp/copilote-codex-private")
        let environment = CodexLaunch.environment(base: ["HOME": "/Users/example", "PATH": "/usr/bin"], executable: URL(fileURLWithPath: "/opt/tools/bin/codex"), privateDirectory: "/tmp/copilote-codex-private")

        XCTAssertTrue(arguments.contains(pair: "-c", #"log_dir="/tmp/copilote-codex-private/log""#))
        XCTAssertEqual(environment["CODEX_SQLITE_HOME"], "/tmp/copilote-codex-private")
        XCTAssertNil(environment["CODEX_HOME"])
        XCTAssertTrue(environment["PATH"]?.hasPrefix("/opt/tools/bin:/opt/homebrew/bin") == true)
    }

    /// `-c mcp_servers={}` merges instead of replacing: each server must be switched off by name.
    func test_switchesOffEachMCPServerDeclaredInTheUsersConfig() {
        let config = """
        model = "gpt-5.6-sol"

        [mcp_servers.playwright]
        command = "npx"

        [mcp_servers.computer-use]
        command = "/Applications/Computer Use.app/run"

        [mcp_servers.computer-use.env]
        MODE = "full"
        """

        let arguments = CodexLaunch.arguments(userConfig: config, privateDirectory: "/tmp/p")

        XCTAssertTrue(arguments.contains(pair: "-c", "mcp_servers.playwright.enabled=false"))
        XCTAssertTrue(arguments.contains(pair: "-c", "mcp_servers.computer-use.enabled=false"))
        XCTAssertEqual(arguments.filter { $0.hasPrefix("mcp_servers.") }.count, 2)
    }

    /// A server Copilote cannot name cannot be switched off: Codex must not start at all then.
    func test_refusesConfigsWithMCPServersItCannotSwitchOff() {
        XCTAssertNil(CodexLaunch.problem(inUserConfig: "[mcp_servers.playwright]\ncommand = \"npx\""))
        XCTAssertNotNil(CodexLaunch.problem(inUserConfig: "[mcp_servers.\"mon serveur\"]\ncommand = \"x\""))
        XCTAssertNotNil(CodexLaunch.problem(inUserConfig: "mcp_servers = { outil = { command = \"x\" } }"))
        XCTAssertNotNil(CodexLaunch.problem(inUserConfig: "mcp_servers.outil.command = \"x\""))
        XCTAssertNotNil(CodexLaunch.problem(inUserConfig: "[mcp_servers]\noutil = { command = \"npx\" }"))
        XCTAssertNotNil(CodexLaunch.problem(inUserConfig: "[ mcp_servers.outil ]\ncommand = \"x\""))
        XCTAssertNotNil(CodexLaunch.problem(inUserConfig: "[\"mcp_servers\".outil]\ncommand = \"x\""))
        XCTAssertNil(CodexLaunch.problem(inUserConfig: "# mcp_servers.x was removed\nmodel = \"m\""))
    }

    /// A selected profile can override features and web search: refused rather than trusted.
    func test_refusesAConfigThatSelectsAProfile() {
        XCTAssertNotNil(CodexLaunch.problem(inUserConfig: "profile = \"fast\"\n[profiles.fast]\nweb_search = \"live\""))
        XCTAssertNil(CodexLaunch.problem(inUserConfig: "[profiles.fast]\nweb_search = \"live\""))
    }

    /// A config saved with Windows line endings must still have every server switched off.
    func test_readsConfigsWithCRLFLineEndings() {
        let arguments = CodexLaunch.arguments(userConfig: "[mcp_servers.playwright]\r\ncommand = \"npx\"\r\n", privateDirectory: "/tmp/p")

        XCTAssertTrue(arguments.contains(pair: "-c", "mcp_servers.playwright.enabled=false"))
    }

    /// The "Fast" setting starts from what the user chose in Codex: a top-level `service_tier`.
    func test_prefersTheFastTierOnlyWhenTheUserConfigAsksForIt() {
        XCTAssertTrue(CodexLaunch.prefersFastTier(userConfig: "model = \"m\"\nservice_tier = \"priority\"\n"))
        XCTAssertFalse(CodexLaunch.prefersFastTier(userConfig: "service_tier = \"flex\""))
        XCTAssertFalse(CodexLaunch.prefersFastTier(userConfig: "[profiles.fast]\nservice_tier = \"priority\""))
        XCTAssertFalse(CodexLaunch.prefersFastTier(userConfig: "# service_tier = \"priority\""))
        XCTAssertFalse(CodexLaunch.prefersFastTier(userConfig: nil))
    }
}

extension Array where Element == String {
    func contains(pair first: String, _ second: String) -> Bool {
        zip(self, dropFirst()).contains { $0 == first && $1 == second }
    }
}
