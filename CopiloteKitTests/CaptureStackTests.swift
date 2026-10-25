import XCTest
@testable import CopiloteKit

final class CaptureStackTests: XCTestCase {
    func test_drain_returnsImagesInCaptureOrder_andEmptiesTheStack() {
        var stack = CaptureStack()
        stack.push(.fake("page 1"))
        stack.push(.fake("page 2"))
        stack.push(.fake("page 3"))

        let drained = stack.drain()

        XCTAssertEqual(drained.map(\.fakeLabel), ["page 1", "page 2", "page 3"])
        XCTAssertTrue(stack.isEmpty)
    }
}

extension CapturedImage {
    static func fake(_ label: String) -> CapturedImage {
        CapturedImage(data: Data(label.utf8), mediaType: "image/jpeg", pixelWidth: 10, pixelHeight: 10)
    }

    var fakeLabel: String { String(decoding: data, as: UTF8.self) }
}

final class CaptureStackSummaryTests: XCTestCase {
    func test_summary_countsScreenshotsInEnglish() {
        var stack = CaptureStack()
        XCTAssertEqual(stack.summary, "No screenshots")

        stack.push(.fake("a"))
        XCTAssertEqual(stack.summary, "1 screenshot")

        stack.push(.fake("b"))
        stack.push(.fake("c"))
        XCTAssertEqual(stack.summary, "3 screenshots")
    }
}

final class CaptureStackCapacityTests: XCTestCase {
    func test_push_refusesCapturesBeyondCapacity_andKeepsTheExistingOnes() {
        var stack = CaptureStack(capacity: 2)

        XCTAssertEqual(stack.push(.fake("a")), .added)
        XCTAssertEqual(stack.push(.fake("b")), .added)
        XCTAssertEqual(stack.push(.fake("c")), .full)

        XCTAssertEqual(stack.drain().map(\.fakeLabel), ["a", "b"])
    }
}

/// After a failed send, its captures go back on top of the stack so ⌘⇧↩ retries them.
final class CaptureStackRestoreTests: XCTestCase {
    func test_restore_putsTheFailedCapturesBackFirst_beforeOnesTakenSince() {
        var stack = CaptureStack()
        stack.push(.fake("taken during the request"))

        let dropped = stack.restore([.fake("page 1"), .fake("page 2")])

        XCTAssertEqual(dropped, 0)
        XCTAssertEqual(stack.drain().map(\.fakeLabel), ["page 1", "page 2", "taken during the request"])
    }

    func test_restore_reportsCapturesThatNoLongerFit() {
        var stack = CaptureStack(capacity: 3)
        stack.push(.fake("new 1"))
        stack.push(.fake("new 2"))

        let dropped = stack.restore([.fake("page 1"), .fake("page 2")])

        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(stack.drain().map(\.fakeLabel), ["page 1", "page 2", "new 1"])
    }
}
