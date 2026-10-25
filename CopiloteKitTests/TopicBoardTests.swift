import XCTest
@testable import CopiloteKit

final class TopicBoardTests: XCTestCase {
    func test_aNewTopicEntersCaseOne_andPushesTheOthersDown() {
        var board = TopicBoard()

        board.apply(.new(title: "Ramasse-miettes en Java"), turn: .them("Comment marche le GC ?"), at: .t(0))
        board.apply(.new(title: "Recherche dans un arbre binaire"), turn: .them("Et un arbre binaire ?"), at: .t(10))

        XCTAssertEqual(board.topics.map(\.title), ["Recherche dans un arbre binaire", "Ramasse-miettes en Java"])
    }
}

final class TopicBoardEvictionTests: XCTestCase {
    func test_aFifthTopicPushesTheOldestOut() {
        var board = TopicBoard()

        for (index, title) in ["A", "B", "C", "D", "E"].enumerated() {
            board.apply(.new(title: title), turn: .them(title), at: .t(Double(index)))
        }

        XCTAssertEqual(board.topics.map(\.title), ["E", "D", "C", "B"])
    }
}

final class TopicBoardContinuationTests: XCTestCase {
    func test_aTopicThatContinuesUpdatesItsCaseInPlace() throws {
        var board = TopicBoard()
        board.apply(.new(title: "Ramasse-miettes en Java"), turn: .them("Comment marche le GC en Java ?"), at: .t(0))
        board.apply(.new(title: "Arbre binaire équilibré"), turn: .them("Et un arbre binaire ?"), at: .t(10))
        let gc = try XCTUnwrap(board.topics.last)

        board.apply(
            .continueTopic(id: gc.id, title: "Cycles et ramasse-miettes Java"),
            turn: .them("Pour revenir au GC, et les cycles ?"), at: .t(20)
        )

        XCTAssertEqual(board.topics.map(\.title), ["Arbre binaire équilibré", "Cycles et ramasse-miettes Java"])
        let updated = try XCTUnwrap(board.topics.last)
        XCTAssertEqual(updated.id, gc.id)
        XCTAssertEqual(updated.excerpt, ["Comment marche le GC en Java ?", "Pour revenir au GC, et les cycles ?"])
        XCTAssertEqual(updated.createdAt, .t(0))
        XCTAssertEqual(updated.updatedAt, .t(20))
        XCTAssertEqual(updated.version, 2)
    }
}

final class TopicBoardEdgeCaseTests: XCTestCase {
    /// The segmenter may point at a topic that has already left the board.
    func test_continuingATopicNoLongerOnTheBoardStartsANewOne() {
        var board = TopicBoard()
        board.apply(.new(title: "A"), turn: .them("a"), at: .t(0))

        board.apply(.continueTopic(id: "t99", title: "Retour sur un vieux sujet"), turn: .them("…"), at: .t(5))

        XCTAssertEqual(board.topics.map(\.title), ["Retour sur un vieux sujet", "A"])
    }

    /// The model sends "" as title with "continue": if that topic has left, the case still needs a title.
    func test_continuingAGoneTopicWithoutTitleTitlesTheNewCaseFromWhatWasSaid() {
        var board = TopicBoard()

        board.apply(.continueTopic(id: "t7", title: ""), turn: .them("Et pour la latence réseau, tu ferais comment ?"), at: .t(0))

        XCTAssertEqual(board.topics.map(\.title), ["Pour la latence réseau, tu ferais comment"])
    }

    func test_aContinuationWithoutTitleKeepsTheCurrentOne() {
        var board = TopicBoard.filled(["Ramasse-miettes en Java"])

        board.apply(.continueTopic(id: board.topics[0].id, title: ""), turn: .them("et les cycles ?"), at: .t(5))

        XCTAssertEqual(board.topics[0].title, "Ramasse-miettes en Java")
        XCTAssertEqual(board.topics[0].version, 2)
    }

    func test_smallTalkLeavesTheBoardUnchanged() {
        var board = TopicBoard()
        board.apply(.new(title: "A"), turn: .them("a"), at: .t(0))
        let before = board.topics

        board.apply(.ignore, turn: .them("D'accord, merci."), at: .t(5))

        XCTAssertEqual(board.topics, before)
    }
}

final class TopicBoardPinningTests: XCTestCase {
    func test_aPinnedCaseNeverLeaves_theOldestUnpinnedOneGoesInstead() {
        var board = TopicBoard.filled(["A", "B", "C", "D"]) // D is case 1, A case 4
        board.togglePin(id: board.topics[3].id) // pin A

        board.apply(.new(title: "E"), turn: .them("e"), at: .t(10))

        XCTAssertEqual(board.topics.map(\.title), ["E", "D", "C", "A"])
        XCTAssertEqual(board.topics.map(\.isPinned), [false, false, false, true])
    }

    /// With every case pinned there is no room: the new topic is reported, not shown.
    func test_whenAllFourCasesArePinnedANewTopicIsDropped() {
        var board = TopicBoard.filled(["A", "B", "C", "D"])
        board.topics.map(\.id).forEach { board.togglePin(id: $0) }

        let change = board.apply(.new(title: "E"), turn: .them("e"), at: .t(10))

        XCTAssertEqual(change, .dropped)
        XCTAssertEqual(board.topics.map(\.title), ["D", "C", "B", "A"])
    }

    /// The key press targets the case the user saw: pin by topic, even if a decision moved it.
    func test_pinningByTopicFollowsTheTopicWhereverItMoved() {
        var board = TopicBoard.filled(["A", "B"])
        let seen = board.topics[0] // "B", case 1 on screen
        board.apply(.new(title: "C"), turn: .them("c"), at: .t(5)) // lands just before the key press

        board.togglePin(id: seen.id)

        XCTAssertEqual(board.topics.map(\.isPinned), [false, true, false])
    }

    func test_togglingTwiceUnpins_andAnUnknownTopicDoesNothing() {
        var board = TopicBoard.filled(["A"])

        board.togglePin(id: board.topics[0].id)
        board.togglePin(id: board.topics[0].id)
        board.togglePin(id: "t99")

        XCTAssertEqual(board.topics.map(\.isPinned), [false])
    }
}

extension TopicBoard {
    static func filled(_ titles: [String]) -> TopicBoard {
        var board = TopicBoard()
        for (index, title) in titles.enumerated() {
            board.apply(.new(title: title), turn: .them(title), at: .t(Double(index)))
        }
        return board
    }
}

extension Turn {
    static func them(_ text: String, at start: TimeInterval = 0) -> Turn {
        Turn(speaker: .them, text: text, start: start, end: start + 2)
    }
}

extension Date {
    static func t(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }
}
