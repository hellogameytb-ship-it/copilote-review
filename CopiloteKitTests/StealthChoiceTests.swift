import XCTest
@testable import CopiloteKit

final class StealthChoiceTests: XCTestCase {
    func test_bothEntryPointsRequireAnExplicitMatchingConfirmation() throws {
        for source in [StealthChoice.Source.pill,.settings] {
            var choice = StealthChoice(isEnabled:true)
            choice.request(false,from:source)
            let pending = try XCTUnwrap(choice.pendingOff)
            XCTAssertTrue(choice.isEnabled)
            XCTAssertEqual(pending.source,source)
            choice.confirmOff(UUID())
            XCTAssertTrue(choice.isEnabled)
            choice.confirmOff(pending.id)
            XCTAssertFalse(choice.isEnabled)
            XCTAssertNil(choice.pendingOff)
            choice.confirmOff(pending.id)
            XCTAssertFalse(choice.isEnabled)
        }
    }
    func test_cancelAndStaleConfirmationCannotDisableStealth() throws {
        var choice = StealthChoice(isEnabled:true)
        choice.request(false,from:.pill)
        let stale = try XCTUnwrap(choice.pendingOff).id
        choice.cancel(); choice.confirmOff(stale)
        XCTAssertTrue(choice.isEnabled)
        XCTAssertNil(choice.pendingOff)
        choice.request(false,from:.pill)
        XCTAssertNotEqual(choice.pendingOff?.id,stale)
        choice.confirmOff(stale)
        XCTAssertTrue(choice.isEnabled)
    }
    func test_duplicateRequestIsIdempotentAndChangingOwnerInvalidatesOldToken() throws {
        var choice = StealthChoice(isEnabled:true)
        choice.request(false,from:.pill)
        let pill = try XCTUnwrap(choice.pendingOff)
        choice.request(false,from:.pill)
        XCTAssertEqual(choice.pendingOff,pill)
        choice.request(false,from:.settings)
        XCTAssertNotEqual(choice.pendingOff?.id,pill.id)
        choice.confirmOff(pill.id)
        XCTAssertTrue(choice.isEnabled)
    }
    func test_onIsImmediateAndRestoredOffIsNeverSilentlyChanged() {
        var choice = StealthChoice(isEnabled:false)
        XCTAssertFalse(choice.isEnabled)
        XCTAssertNil(choice.pendingOff)
        choice.cancel(); choice.request(false,from:.settings)
        XCTAssertFalse(choice.isEnabled)
        choice.request(true,from:.pill)
        XCTAssertTrue(choice.isEnabled)
        XCTAssertNil(choice.pendingOff)
    }
    func test_turningOnInvalidatesAnyPendingOffRequest() throws {
        var choice = StealthChoice(isEnabled:true)
        choice.request(false,from:.settings)
        let stale = try XCTUnwrap(choice.pendingOff).id
        choice.request(true,from:.pill)
        choice.confirmOff(stale)
        XCTAssertTrue(choice.isEnabled)
        XCTAssertNil(choice.pendingOff)
    }
}
