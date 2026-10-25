import XCTest
@testable import CopiloteKit

final class VaultPolicyTests: XCTestCase {
    func test_numberedProjectFoldersRetainProjectKindWithoutOverridingCV() {
        XCTAssertEqual(VaultPolicy.documentKind(for: "02 Projects/Orion/overview.md"), .project)
        XCTAssertEqual(VaultPolicy.documentKind(for: "Career/03 - Projets/Orion.md"), .project)
        XCTAssertEqual(VaultPolicy.documentKind(for: "Projects/Personal/CV.md"), .cv)
        XCTAssertEqual(VaultPolicy.documentKind(for: "Projects/Personal/avis.md"), .opinion)
    }

    func test_nestedCVRemainsRetrievableByGenericCareerQuestionAfterPolicyMigration() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = temp.appendingPathComponent("Brain")
        defer { try? FileManager.default.removeItem(at: temp) }
        let path = "Personnel/Carrière/CV.md"
        let cv = "# CV\n## Expériences\n### Ingénieure — 2022–2025\nAda développe des outils de cartographie.\n## Formation\nMaster en informatique."
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try cv.write(to: url, atomically: true, encoding: .utf8)
        try "# Conseils\nPréparer son parcours professionnel pour un entretien.".write(to: root.appendingPathComponent("conseils.md"), atomically: true, encoding: .utf8)
        let index = try BaseIndex(url: temp.appendingPathComponent("cache/index.sqlite"))
        let indexer = BaseIndexer(index: index, embedder: NoEmbedder(), store: temp.appendingPathComponent("cache"))
        _ = try await indexer.run(BaseSource(root: root))
        // A previous policy's unchanged files must be read again, not retained as plain notes.
        try index.setMeta("inputPolicy", "vault-readonly-v2")
        let migrated = try await indexer.run(BaseSource(root: root))
        XCTAssertEqual(migrated.changedFiles, 2)
        XCTAssertEqual(index.meta("inputPolicy"), VaultPolicy.indexPolicy)
        let items = try index.items().map(\.item).filter { $0.source == path }
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { $0.kind == .cv })
        let base = PersonalBase(search: BaseSearch(index: index, embedder: NoEmbedder()), index: index, root: root)
        let snippets = await base.snippets(for: "Résume mon CV et mon parcours professionnel")
        XCTAssertFalse(snippets.isEmpty)
        XCTAssertTrue(snippets.allSatisfy { $0.source.contains(path) })
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), cv)
    }

    func test_readsNestedObsidianNotesWithoutWritingSourceOrIndexingSecrets() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = temp.appendingPathComponent("Brain")
        defer { try? FileManager.default.removeItem(at: temp) }
        let files = ["Career/Projects/orion.md": "# Orion\n\nMon projet Orion utilise Swift pour analyser des étoiles.",
                     "secrets.md": "confidentiel", ".obsidian/config.json": "configuration",
                     "notes.md": "api_key: sk-abcdefghijklmnopqrstuvwxyz123456",
                     "public.md": "# Voyage\n\nJ'ai visité Porto.",
                     "Personal/avis.md": "# Avis\n## Langage préféré\nJe préfère Swift pour les apps natives."]
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let outside = temp.appendingPathComponent("outside.md")
        try "must not read outside".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.md"), withDestinationURL: outside)
        let index = try BaseIndex(url: temp.appendingPathComponent("index.sqlite"))
        let indexer = BaseIndexer(index: index, embedder: NoEmbedder(), store: temp.appendingPathComponent("cache"))
        _ = try await indexer.run(BaseSource(root: root))
        let items = try index.items().map(\.item)
        XCTAssertEqual(Set(items.map(\.source)), ["Career/Projects/orion.md", "public.md", "Personal/avis.md"])
        let search = BaseSearch(index: index, embedder: NoEmbedder())
        let result = try await search.search("Mon projet Orion", today: .today())
        XCTAssertEqual(result.hits.first?.item.source, "Career/Projects/orion.md")
        let personal = PersonalBase(search: search, index: index, root: root)
        let extracts = await personal.snippets(for: "Mon projet Orion")
        XCTAssertFalse(extracts.isEmpty)
        XCTAssertTrue(extracts.allSatisfy { $0.source.contains("orion.md") })
        let opinions = await personal.opinions(for: "Quel est ton langage préféré ?")
        XCTAssertTrue(opinions.first?.source.contains("Personal/avis.md") == true)
        let disabled = await personal.snippets(for: "Mon projet Orion", router: PersonalRouter(mode: .off))
        XCTAssertTrue(disabled.isEmpty)
        for (path, text) in files { XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8), text) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.sqlite").path))
    }
    func test_sensitivePathsAndCredentialContentAreExcluded() {
        XCTAssertFalse(VaultPolicy.allows(path: "Work/API keys.md"))
        XCTAssertFalse(VaultPolicy.allows(path: ".obsidian/plugins/settings.json"))
        XCTAssertTrue(VaultPolicy.containsSecrets("password: fictitious-example"))
        XCTAssertFalse(VaultPolicy.containsSecrets("Une table de hachage stocke des valeurs."))
    }
}
