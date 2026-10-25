import XCTest
@testable import CopiloteKit

final class MarkdownFileExportTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    func testExclusiveCreationAndChangedDestinationCannotOverwrite() throws {
        try MarkdownFileExport.write("original", directory: folder, name: "session", replacing: nil)
        let url = folder.appendingPathComponent("session.md")
        XCTAssertEqual(try String(contentsOf: url), "original")
        let old = try XCTUnwrap(MarkdownFileExport.revision(at: url))
        XCTAssertThrowsError(try MarkdownFileExport.write("unexpected", directory: folder, name: "session.md", replacing: nil))
        try "changed elsewhere".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try MarkdownFileExport.write("stale confirmation", directory: folder, name: "session.md", replacing: old))
        XCTAssertEqual(try String(contentsOf: url), "changed elsewhere")
        try MarkdownFileExport.write("confirmed", directory: folder, name: "session.md", replacing: MarkdownFileExport.revision(at: url))
        XCTAssertEqual(try String(contentsOf: url), "confirmed")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["session.md"])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testRefusesTraversalLinksAndDirectoryDestinations() throws {
        for name in ["", ".", "..", "../escape", "a/b", "a\\b", "a\0b"] {
            XCTAssertThrowsError(try MarkdownFileExport.filename(name))
        }
        let target = folder.appendingPathComponent("target.md")
        try "keep".write(to: target, atomically: true, encoding: .utf8)
        let link = folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try MarkdownFileExport.revision(at: link))
        XCTAssertThrowsError(try MarkdownFileExport.write("bad", directory: folder, name: "link.md", replacing: nil))
        XCTAssertEqual(try String(contentsOf: target), "keep")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("directory.md"), withIntermediateDirectories: false)
        XCTAssertThrowsError(try MarkdownFileExport.write("bad", directory: folder, name: "directory.md", replacing: nil))
    }
    func testBookmarkRestoresFolderAndInvalidDataFailsWithoutUI() throws {
        let bookmark = try FileBrowserBookmark.create(folder)
        XCTAssertEqual(try FileBrowserBookmark.resolve(bookmark).resolvingSymlinksInPath(), folder.resolvingSymlinksInPath())
        XCTAssertThrowsError(try FileBrowserBookmark.resolve(Data("invalid".utf8)))
        XCTAssertEqual(MarkdownFileExport.suggestedName("Meeting / notes\n2026"), "Meeting - notes-2026.md")
    }
}
