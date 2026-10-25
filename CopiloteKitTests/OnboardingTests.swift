import XCTest
@testable import CopiloteKit

/// The first-launch welcome (Cluely's and Final Round's first run, the user's retours 5): what Copilote
/// does, the two permissions, Codex, the personal base, the four shortcuts, the stealth mode, then
/// « C'est parti ». Back and Next, skippable, replayable from ⚙.
final class OnboardingTests: XCTestCase {
    func test_theStepsInBensOrder() {
        var onboarding = Onboarding()
        var seen: [Onboarding.Step] = [onboarding.step]
        while !onboarding.isLast {
            onboarding.next()
            seen.append(onboarding.step)
        }
        XCTAssertEqual(seen, [.welcome, .permissions, .codex, .base, .shortcuts, .stealth])
    }

    func test_nextOnTheLastStepFinishes_backStopsAtTheFirst() {
        var onboarding = Onboarding()
        onboarding.back()
        XCTAssertEqual(onboarding.step, .welcome)
        XCTAssertFalse(onboarding.canGoBack)
        for _ in 0..<5 { onboarding.next() }
        XCTAssertTrue(onboarding.isLast)
        XCTAssertFalse(onboarding.isFinished)
        onboarding.next()
        XCTAssertTrue(onboarding.isFinished)
    }

    /// macOS may ask to relaunch Copilote for screen recording: the welcome picks up where it was.
    func test_resumesAtASavedStep_andAnUnknownOneStartsOver() {
        XCTAssertEqual(Onboarding(resumingAt: Onboarding.Step.codex.rawValue).step, .codex)
        XCTAssertEqual(Onboarding(resumingAt: 42).step, .welcome)
    }

    func test_progressAndSkipping() {
        var onboarding = Onboarding()
        onboarding.next()
        XCTAssertEqual(onboarding.number, 2)
        XCTAssertEqual(Onboarding.count, 6)
        onboarding.back()
        XCTAssertEqual(onboarding.number, 1)
        onboarding.finish()
        XCTAssertTrue(onboarding.isFinished)
    }
}
