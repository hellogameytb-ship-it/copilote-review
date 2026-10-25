import XCTest
@testable import CopiloteKit

/// Option 3: case 1 gets a drafted answer by itself, one generation at a time.
final class AutoAnswerPolicyTests: XCTestCase {
    private var policy = AutoAnswerPolicy()

    func test_aNewCaseStartsItsAnswer_andTheModelsBetterTitleKeepsIt() {
        let instant = topic("t1", "Comment fonctionne le ramasse-miettes", provisional: true)
        XCTAssertEqual(policy.react(to: [instant], change: .created(id: "t1"), userIsAnswering: false), .start(instant))

        let settled = topic("t1", "Ramasse-miettes en Java")
        XCTAssertEqual(policy.react(to: [settled], change: .confirmed(id: "t1"), userIsAnswering: false), .keep)
    }

    func test_aNewCaseReplacesTheAnswerInFlight_aTurnMoreOnCaseOneToo() {
        _ = policy.react(to: [topic("t1", "Mémoire en Java")], change: .created(id: "t1"), userIsAnswering: false)

        let second = topic("t2", "Arbre binaire")
        XCTAssertEqual(policy.react(to: [second, topic("t1", "Mémoire en Java")], change: .created(id: "t2"), userIsAnswering: false), .start(second))

        let continued = topic("t2", "Arbre binaire", version: 2)
        XCTAssertEqual(policy.react(to: [continued], change: .updated(id: "t2"), userIsAnswering: false), .start(continued))
    }

    func test_aMergeOfTheSameTurnKeepsTheAnswer_aWithdrawalCancelsIt() {
        _ = policy.react(to: [topic("t1", "Mémoire en Java")], change: .created(id: "t1"), userIsAnswering: false)
        _ = policy.react(to: [topic("t2", "Et le ramasse-miettes", provisional: true), topic("t1", "Mémoire en Java")], change: .created(id: "t2"), userIsAnswering: false)

        let merged = topic("t1", "Mémoire et ramasse-miettes", version: 2)
        XCTAssertEqual(policy.react(to: [merged], change: .merged(from: "t2", into: "t1"), userIsAnswering: false), .keep)

        _ = policy.react(to: [topic("t3", "On a bien avancé", provisional: true), merged], change: .created(id: "t3"), userIsAnswering: false)
        XCTAssertEqual(policy.react(to: [merged], change: .withdrawn(id: "t3"), userIsAnswering: false), .cancel,
                       "case 1 is an older question again: nothing new to answer")
    }

    /// ⌥1-4 / ⌘↩ win: no automatic answer over the one the user asked for.
    func test_neverOverTheUsersOwnAnswer() {
        XCTAssertEqual(policy.react(to: [topic("t1", "Mémoire en Java")], change: .created(id: "t1"), userIsAnswering: true), .keep)
    }

    func test_anOlderCardReceivesItsOwnUpdatedAnswer() {
        let first = topic("t2", "Arbre binaire")
        _ = policy.react(to: [first, topic("t1", "Mémoire en Java")], change: .created(id: "t2"), userIsAnswering: false)

        XCTAssertEqual(policy.react(to: [first, topic("t1", "Mémoire en Java", version: 2)], change: .updated(id: "t1"), userIsAnswering: false), .start(topic("t1", "Mémoire en Java", version: 2)))
        XCTAssertEqual(policy.react(to: [first], change: .pinned(id: "t2"), userIsAnswering: false), .keep)
    }

    private func topic(_ id: String, _ title: String, version: Int = 1, provisional: Bool = false) -> Topic {
        Topic(id: id, title: title, excerpt: [title], createdAt: .t(0), updatedAt: .t(0), version: version, isProvisional: provisional)
    }
}
