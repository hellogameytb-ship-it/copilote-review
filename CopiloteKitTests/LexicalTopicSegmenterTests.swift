import XCTest
@testable import CopiloteKit

/// Offline fallback (no API key, network down, `make replay` without a key).
final class LexicalTopicSegmenterTests: XCTestCase {
    let segmenter = LexicalTopicSegmenter()

    func test_aQuestionOnANewSubjectOpensATopicTitledFromTheQuestion() {
        let turn = Turn.them("Est-ce que tu peux m'expliquer comment fonctionne le ramasse-miettes en Java ?")

        XCTAssertEqual(segmenter.decision(for: turn, topics: []), .new(title: "Comment fonctionne le ramasse-miettes en Java"))
    }

    func test_aFollowUpSharingTheSubjectContinuesItsTopic() {
        var board = TopicBoard()
        board.apply(.new(title: "Comment fonctionne le ramasse-miettes en Java"),
                    turn: .them("Est-ce que tu peux m'expliquer comment fonctionne le ramasse-miettes en Java ?"), at: .t(0))
        board.apply(.new(title: "Pourquoi un stage en finance quantitative"),
                    turn: .them("Pourquoi est-ce que tu veux faire un stage en finance quantitative ?"), at: .t(20))

        let relance = Turn.them("Pour revenir au ramasse miettes de Java, comment est-ce qu'il gère les cycles de références ?")

        XCTAssertEqual(segmenter.decision(for: relance, topics: board.topics), .continueTopic(id: board.topics[1].id, title: ""))
    }

    func test_aQuestionOnAnotherSubjectOpensANewTopic() {
        let board = TopicBoard.filled(["Comment fonctionne le ramasse-miettes en Java"])
        let turn = Turn.them("D'accord. Et sinon, quelle est la complexité d'une recherche dans un arbre binaire équilibré ?")

        XCTAssertEqual(
            segmenter.decision(for: turn, topics: board.topics),
            .new(title: "Quelle est la complexité d'une recherche dans un arbre…")
        )
    }

    /// The transcriber often writes commas where the speaker paused: openers can chain.
    func test_chainedOpenersAreRemovedFromTheTitle() {
        let turn = Turn.them("D'accord, et sinon quelle est la complexité d'une recherche dans un arbre binaire équilibré")

        XCTAssertEqual(segmenter.decision(for: turn, topics: []), .new(title: "Quelle est la complexité d'une recherche dans un arbre…"))
    }

    func test_smallTalkIsIgnored() {
        XCTAssertEqual(segmenter.decision(for: .them("D'accord, merci beaucoup."), topics: []), .ignore)
        XCTAssertEqual(segmenter.decision(for: .them("Okay, great, thanks!"), topics: []), .ignore)
    }
}
