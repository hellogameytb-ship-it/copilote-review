import XCTest
@testable import CopiloteKit

final class ProviderChoiceTests: XCTestCase {
    /// the user's rule: Codex by default when it is installed and logged in, Anthropic otherwise.
    func test_automaticPrefersCodexWhenItIsReady_andAnExplicitChoiceIsKept() {
        XCTAssertEqual(ProviderChoice.automatic.resolved(codexReady: true), .codex)
        XCTAssertEqual(ProviderChoice.automatic.resolved(codexReady: false), .anthropic)
        XCTAssertEqual(ProviderChoice.anthropic.resolved(codexReady: true), .anthropic)
        XCTAssertEqual(ProviderChoice.codex.resolved(codexReady: false), .codex)
    }

    /// GUI apps don't get the shell's PATH: the usual install places are searched too.
    func test_findsCodexInThePathOrTheUsualInstallPlaces_andKnowsWhenItIsLoggedIn() {
        XCTAssertEqual(
            CodexAvailability.candidates(path: "/usr/bin:/custom/bin", home: "/Users/example"),
            ["/usr/bin/codex", "/custom/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Users/example/.local/bin/codex"]
        )
        XCTAssertTrue(CodexAvailability.isLoggedIn(statusOutput: "Logged in using ChatGPT\n"))
        XCTAssertFalse(CodexAvailability.isLoggedIn(statusOutput: "Not logged in\n"))
        // An API key would bill the API, not the ChatGPT subscription the user asked for.
        XCTAssertFalse(CodexAvailability.isLoggedIn(statusOutput: "Logged in using an API key - sk-…\n"))
    }
}
