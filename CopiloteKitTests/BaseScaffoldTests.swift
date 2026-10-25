import XCTest
@testable import CopiloteKit

final class BaseScaffoldTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("scaffold-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_createsTheFoldersAndTemplates_withoutTouchingWhatExists() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Mon CV\n## Compétences\n- Swift".write(to: root.appendingPathComponent("cv.md"), atomically: true, encoding: .utf8)

        let created = try BaseScaffold.create(at: root)

        XCTAssertFalse(created.contains("cv.md"))
        XCTAssertTrue(created.contains("bio.md"))
        XCTAssertTrue(created.contains("projets/_modele.md"))
        XCTAssertTrue(created.contains("voyages/_modele.md"))
        for folder in ["notes", "reference", "photos"] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(folder).path, isDirectory: &isDirectory) && isDirectory.boolValue, folder)
        }
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("cv.md"), encoding: .utf8), "# Mon CV\n## Compétences\n- Swift")
        XCTAssertEqual(try BaseScaffold.create(at: root), [], "a second run creates nothing")
    }

    /// A base made by an earlier version gets the new models (stories, avis.md), but a model the
    /// user edited is never touched.
    func test_untouchedModelsFromAnEarlierVersionAreUpdated_editedOnesNever() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("projets"), withIntermediateDirectories: true)
        let earlierProject = try XCTUnwrap(BaseScaffold.earlierVersions["projets/_modele.md"]?.first)
        XCTAssertFalse(earlierProject.contains("## Histoires"))
        try earlierProject.write(to: root.appendingPathComponent("projets/_modele.md"), atomically: true, encoding: .utf8)
        try "# Ma base\nMes propres consignes.".write(to: root.appendingPathComponent("LISEZMOI.md"), atomically: true, encoding: .utf8)

        let changed = try BaseScaffold.create(at: root)

        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("projets/_modele.md"), encoding: .utf8).contains("## Histoires"))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("LISEZMOI.md"), encoding: .utf8), "# Ma base\nMes propres consignes.")
        XCTAssertTrue(changed.contains("projets/_modele.md"))
        XCTAssertTrue(changed.contains("avis.md"))
        XCTAssertFalse(changed.contains("LISEZMOI.md"))
    }

    /// The LISEZMOI of step 4b (shortcuts written for a US keyboard) is updated when untouched.
    func test_anUntouchedReadmeOfStep4bIsUpdated() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let earlier = try XCTUnwrap(BaseScaffold.earlierVersions["LISEZMOI.md"]?.last)
        XCTAssertTrue(earlier.contains("⌥1-4"))
        try earlier.write(to: root.appendingPathComponent("LISEZMOI.md"), atomically: true, encoding: .utf8)

        try BaseScaffold.create(at: root)

        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("LISEZMOI.md"), encoding: .utf8).contains("⌥1-4"))
    }

    /// A template filled with nothing must not put empty fiches in the index.
    func test_theTemplatesIndexToNothing() {
        for (path, content) in BaseScaffold.templates {
            XCTAssertEqual(BaseChunker.items(markdown: content, path: path), [], path)
            XCTAssertEqual(BaseChunker.items(markdown: content, path: path.replacingOccurrences(of: "_modele", with: "copie")), [], path)
        }
    }
}

final class StoriesAndOpinionsTemplateTests: XCTestCase {
    /// The project model invites the four stories; avis.md holds the user's own opinions.
    func test_theModelsAskForStoriesAndOpinions() throws {
        let project = try XCTUnwrap(BaseScaffold.templates.first { $0.path == "projets/_modele.md" }).content
        for heading in ["## Histoires", "### Pression / deadline", "### Échec et ce que j'ai appris", "### Conflit ou désaccord", "### Fierté"] {
            XCTAssertTrue(project.contains(heading), heading)
        }
        XCTAssertNotNil(BaseScaffold.templates.first { $0.path == "avis.md" })
        XCTAssertTrue(BaseScaffold.readme.contains("avis.md"))
    }

    func test_anOpinionIsAnItemOfItsOwnKind() {
        let items = BaseChunker.items(markdown: "# Mes avis\n## Livre préféré\nL'Étranger, pour sa phrase sèche.\n", path: "avis.md")

        XCTAssertEqual(BaseChunker.kind(forPath: "avis.md"), .opinion)
        XCTAssertEqual(items.map(\.section), ["Livre préféré"])
        XCTAssertEqual(items.first?.kind, .opinion)
    }
}

/// « Ajouter à avis.md »: a section to fill in after the meeting, never an opinion written for the user.
final class AddOpinionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("avis-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_addingAnOpinionAppendsAnEmptySectionToFillIn() throws {
        let url = try BaseScaffold.addOpinion("Président américain préféré", at: root)
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(text.hasPrefix("# Mes avis"), "created from the model")
        XCTAssertTrue(text.contains("\n## Président américain préféré\n"), text)
        XCTAssertEqual(BaseChunker.items(markdown: text, path: "avis.md"), [], "nothing to index until the user writes it")

        _ = try BaseScaffold.addOpinion("Président américain préféré", at: root)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).components(separatedBy: "## Président américain préféré").count, 2, "added once")
    }

    func test_theSubjectOfAnOpinionQuestion() {
        XCTAssertEqual(OpinionLookup.subject(ofTitle: "C'est qui ton président des États-Unis préféré ?"), "Président des États-Unis préféré")
        XCTAssertEqual(OpinionLookup.subject(ofTitle: "Ton président américain préféré"), "Président américain préféré")
        XCTAssertEqual(OpinionLookup.subject(ofTitle: "Quel est ton livre préféré"), "Livre préféré")
        XCTAssertEqual(OpinionLookup.subject(ofTitle: "Tu penses quoi du télétravail ?"), "Télétravail")
        XCTAssertEqual(OpinionLookup.subject(ofTitle: "What’s your favourite city?"), "Favourite city")
    }
}
