import XCTest
@testable import CopiloteKit

final class RepoSnapshotTests: XCTestCase {
    private var repo: URL!

    override func setUpWithError() throws {
        repo = FileManager.default.temporaryDirectory.appendingPathComponent("repo-\(UUID().uuidString)")
        try write("README.md", "# Revisio\nQuiz à partir de notes.")
        try write("package.json", #"{"name": "revisio"}"#)
        try write("apps/web/app/page.tsx", "export default function Page() {}")
        try write(".git/HEAD", "ref: refs/heads/main")
        try write("node_modules/react/index.js", "module.exports = {}")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repo)
    }

    func test_readsTheReadmeTheTreeAndKeyFiles_butNotDependenciesOrGit() throws {
        let snapshot = try RepoSnapshot(at: repo)

        XCTAssertEqual(snapshot.readme, "# Revisio\nQuiz à partir de notes.")
        XCTAssertEqual(snapshot.tree, ["README.md", "apps/", "apps/web/", "apps/web/app/", "apps/web/app/page.tsx", "package.json"])
        XCTAssertEqual(snapshot.keyFiles.map(\.path), ["package.json"])
    }

    func test_theHashChangesWithTheReadmeOrTheTree_notWithDependencies() throws {
        let before = try RepoSnapshot(at: repo).hash

        try write("node_modules/left-pad/index.js", "module.exports = 1")
        XCTAssertEqual(try RepoSnapshot(at: repo).hash, before)

        try write("services/quiz/main.py", "app = FastAPI()")
        let withService = try RepoSnapshot(at: repo).hash
        XCTAssertNotEqual(withService, before)

        try write("README.md", "# Revisio\nQuiz et fiches à partir de notes.")
        XCTAssertNotEqual(try RepoSnapshot(at: repo).hash, withService)
    }

    /// What goes to the LLM must not carry secrets a README or a compose file may hold.
    func test_secretsAreMaskedBeforeAnythingLeaves() throws {
        try write("docker-compose.yml", "services:\n  db:\n    environment:\n      POSTGRES_PASSWORD: hunter2\n      API_KEY=sk-live-123\n")
        try write("README.md", "# Revisio\nexport OPENAI_API_KEY=sk-abc\nToken: ghp_secret\n")

        let snapshot = try RepoSnapshot(at: repo)
        let sent = DiagramCache.prompt(project: "Revisio", snapshot: snapshot)

        for secret in ["hunter2", "sk-live-123", "sk-abc", "ghp_secret"] {
            XCTAssertFalse(sent.contains(secret), secret)
        }
        XCTAssertTrue(sent.contains("POSTGRES_PASSWORD: [masqué]"))
    }

    private func write(_ path: String, _ content: String) throws {
        let url = repo.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

final class DiagramCacheTests: XCTestCase {
    func test_aDiagramIsMadeOnce_andAgainOnlyWhenTheRepoChanges() {
        let made = DiagramRecord(repoHash: "aaa", mermaid: "flowchart LR\n  A --> B", status: .ok)

        XCTAssertEqual(DiagramCache.plan(existing: nil, repoHash: "aaa"), .generate)
        XCTAssertEqual(DiagramCache.plan(existing: made, repoHash: "aaa"), .reuse)
        XCTAssertEqual(DiagramCache.plan(existing: made, repoHash: "bbb"), .generate)
    }

    /// An invalid diagram is not asked for again until the repo changes (the fiche shows without
    /// one); a failed call (Codex unreachable) is retried at the next indexing.
    func test_invalidIsFinalForThisRepoState_failedIsRetried() {
        let invalid = DiagramRecord(repoHash: "aaa", mermaid: nil, status: .invalid)
        let failed = DiagramRecord(repoHash: "aaa", mermaid: nil, status: .failed)

        XCTAssertEqual(DiagramCache.plan(existing: invalid, repoHash: "aaa"), .reuse)
        XCTAssertEqual(DiagramCache.plan(existing: invalid, repoHash: "bbb"), .generate)
        XCTAssertEqual(DiagramCache.plan(existing: failed, repoHash: "aaa"), .generate)
    }
}

final class MermaidCheckTests: XCTestCase {
    func test_takesTheDiagramOutOfTheAnswer() {
        let answer = """
        Voici l'architecture :
        ```mermaid
        flowchart LR
          web[Next.js] --> api(FastAPI)
          api --> db[(Supabase)]
        ```
        """

        XCTAssertEqual(MermaidCheck.diagram(in: answer), "flowchart LR\n  web[Next.js] --> api(FastAPI)\n  api --> db[(Supabase)]")
        XCTAssertEqual(MermaidCheck.diagram(in: "graph TD\n  A --> B"), "graph TD\n  A --> B")
    }

    func test_refusesWhatIsNotADiagram_orCouldActOnClick() {
        XCTAssertNil(MermaidCheck.diagram(in: "Je n'ai pas assez d'informations."))
        XCTAssertNil(MermaidCheck.diagram(in: "flowchart LR\n  A --> B\n  click A \"https://example.com\""))
        XCTAssertNil(MermaidCheck.diagram(in: "%%{init: {'securityLevel': 'loose'}}%%\nflowchart LR\n  A --> B"))
        XCTAssertNil(MermaidCheck.diagram(in: "flowchart LR\n  A[<img src=x onerror=alert(1)>] --> B"))
        XCTAssertNil(MermaidCheck.diagram(in: "flowchart LR\n  A[Web --> B"), "unbalanced brackets")
    }
}
