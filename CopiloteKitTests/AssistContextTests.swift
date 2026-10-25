import XCTest
@testable import CopiloteKit

final class AssistContextTests: XCTestCase {
    private let lines = [
        TranscriptLine(speaker: .them, text: "Tu as vu le budget ?", start: 1, end: 2),
        TranscriptLine(speaker: .me, text: "Pas encore, je regarde.", start: 3, end: 4),
        TranscriptLine(speaker: .them, text: "Et le planning du lancement ?", start: 5, end: 6),
    ]

    /// Everything is in by default, each piece can be switched off, and what is off is not sent.
    func test_anExcludedPieceIsLeftOut() throws {
        var context = AssistContext(lines: lines, captures: [.fake("slide")], extracts: [BaseSnippet(source: "Revisio › Chiffres (projets/revisio.md)", text: "120 utilisateurs.")])
        XCTAssertEqual(context.items.count, 5)
        XCTAssertTrue(context.items.allSatisfy(\.isIncluded))

        let budget = try XCTUnwrap(context.items.first { $0.label.contains("budget") })
        context.toggle(budget.id)
        let capture = try XCTUnwrap(context.items.first { $0.kind == .capture })
        context.toggle(capture.id)

        XCTAssertEqual(context.includedLines.map(\.text), ["Pas encore, je regarde.", "Et le planning du lancement ?"])
        XCTAssertEqual(context.includedCaptures, [])
        XCTAssertEqual(context.includedExtracts.map(\.source), ["Revisio › Chiffres (projets/revisio.md)"])
    }

    /// New phrases arrive while listening: what the user switched off stays off.
    func test_refreshingKeepsTheUsersChoices() throws {
        var context = AssistContext(lines: lines, captures: [], extracts: [])
        let budget = try XCTUnwrap(context.items.first { $0.label.contains("budget") })
        context.toggle(budget.id)

        context.refresh(
            lines: lines + [TranscriptLine(speaker: .them, text: "On décide jeudi.", start: 7, end: 8)],
            captures: [], extracts: []
        )

        XCTAssertEqual(context.items.count, 4)
        XCTAssertFalse(try XCTUnwrap(context.items.first { $0.id == budget.id }).isIncluded)
        XCTAssertTrue(try XCTUnwrap(context.items.last).isIncluded)
    }

    func test_labelsSayWhoSpokeAndWhatEachPieceIs() {
        let context = AssistContext(lines: Array(lines.prefix(2)), captures: [.fake("a"), .fake("b")], extracts: [])

        XCTAssertEqual(context.items.map(\.label), ["Them : Tu as vu le budget ?", "Me : Pas encore, je regarde.", "Screenshot 1", "Screenshot 2"])
    }
}

final class AssistContextCaptureTests: XCTestCase {
    /// A capture switched off stays off when another one arrives before it in the stack.
    func test_aSwitchedOffCaptureKeepsItsChoiceWhenTheStackChanges() throws {
        let slide = CapturedImage.fake("slide")
        var context = AssistContext(lines: [], captures: [slide], extracts: [])
        context.toggle(try XCTUnwrap(context.items.first).id)

        context.refresh(lines: [], captures: [.fake("schéma"), slide], extracts: [])

        XCTAssertEqual(context.includedCaptures, [.fake("schéma")])
    }
}
