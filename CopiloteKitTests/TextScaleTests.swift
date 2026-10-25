import XCTest
@testable import CopiloteKit

/// ⌥⌘= / ⌥⌘-: the answer's text by tenths, between 80 and 160 %.
final class TextScaleTests: XCTestCase {
    func test_stepsByATenthAndStopsAtTheBounds() {
        XCTAssertEqual(TextScale.stepped(from: 1.0, by: 1), 1.1, accuracy: 0.0001)
        XCTAssertEqual(TextScale.stepped(from: 1.1, by: -1), 1.0, accuracy: 0.0001)
        XCTAssertEqual(TextScale.stepped(from: 1.6, by: 1), 1.6, accuracy: 0.0001)
        XCTAssertEqual(TextScale.stepped(from: 0.8, by: -1), 0.8, accuracy: 0.0001)
    }

    func test_aStoredValueOutOfRangeIsBroughtBack() {
        XCTAssertEqual(TextScale.clamped(3), 1.6)
        XCTAssertEqual(TextScale.clamped(0.2), 0.8)
        XCTAssertEqual(TextScale.stepped(from: 1.04, by: 1), 1.1, accuracy: 0.0001, "back on the tenths")
    }
}
