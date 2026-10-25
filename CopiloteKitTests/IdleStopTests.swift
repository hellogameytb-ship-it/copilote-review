import XCTest
@testable import CopiloteKit

/// Listening forgotten after the call stops by itself after 10 min without a phrase; paused time
/// does not count (Cluely ends a session after 10 min without audio).
final class IdleStopTests: XCTestCase {
    func test_dueTenMinutesAfterTheLastPhrase() {
        var idle = IdleStop(now: 0)
        idle.heard(at: 120)

        XCTAssertEqual(idle.remaining(at: 120), 600)
        XCTAssertEqual(idle.remaining(at: 700), 20)
        XCTAssertEqual(idle.remaining(at: 800), 0)
    }

    func test_pausedTimeDoesNotCount() {
        var idle = IdleStop(now: 0)
        idle.pause(at: 300)
        XCTAssertNil(idle.remaining(at: 900), "never due while paused")
        idle.resume(at: 1_500)

        XCTAssertEqual(idle.remaining(at: 1_500), 300, "the 5 quiet minutes before the pause still count, the 20 paused ones don't")
    }

    func test_aPhraseDuringAPauseStartsAfresh() {
        var idle = IdleStop(now: 0)
        idle.pause(at: 300)
        idle.heard(at: 400)
        idle.resume(at: 1_000)

        XCTAssertEqual(idle.remaining(at: 1_000), 600)
    }
}
