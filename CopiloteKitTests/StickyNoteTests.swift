import XCTest
@testable import CopiloteKit

final class StickyNoteTests: XCTestCase {
    func test_persistenceRetainsEditsPositionPinConsentAndRecoverableDeletion() throws {
        var note = StickyNote(text: "Prepared pitch", frame: CGRect(x: -1100, y: 200, width: 280, height: 220))
        XCTAssertFalse(note.includeInAI)
        note.isPinned = true; note.includeInAI = true; note.deletedAt = Date(timeIntervalSince1970: 42)
        let saved = try JSONEncoder().encode([note])
        XCTAssertEqual(try JSONDecoder().decode([StickyNote].self, from: saved), [note])
    }
    func test_disconnectedDisplayAndResizingAlwaysLeaveNotesReachable() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: -1000, y: 300, width: 280, height: 220)
        XCTAssertEqual(StickyNote.fitted(frame, screens: [main, left]), frame)
        XCTAssertTrue(main.contains(StickyNote.fitted(frame, screens: [main])))
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertTrue(tiny.contains(StickyNote.fitted(CGRect(x: 500, y: 800, width: 1900, height: 900), screens: [tiny])))
    }
}
