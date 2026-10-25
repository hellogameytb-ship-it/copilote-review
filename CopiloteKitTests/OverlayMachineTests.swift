import XCTest
@testable import CopiloteKit

final class OverlayMachineTests: XCTestCase {
    func test_startsAsTheCompactPill_andAClickUnfoldsAndFoldsThePanel() {
        var machine = OverlayMachine()
        XCTAssertEqual(machine.presentation, .pill)

        machine.handle(.pillClicked)
        XCTAssertEqual(machine.presentation, .panel)
        machine.handle(.pillClicked)
        XCTAssertEqual(machine.presentation, .pill)
    }

    /// ⌘\ hides at once and brings back what was there, folded or unfolded.
    func test_hidingComesBackToTheSameState() {
        var machine = OverlayMachine()
        machine.handle(.pillClicked)

        machine.handle(.toggleVisibility)
        XCTAssertEqual(machine.presentation, .hidden)
        machine.handle(.toggleVisibility)
        XCTAssertEqual(machine.presentation, .panel)
    }

    /// ⌘↩ "help me now": unfolds wherever it is and answers the latest case if there is one.
    func test_assistUnfoldsAndAnswersTheLatestCase() {
        var machine = OverlayMachine()
        XCTAssertEqual(machine.handle(.assist(hasTopic: true)), [.answerLatestTopic])
        XCTAssertEqual(machine.presentation, .panel)

        machine.handle(.toggleVisibility)
        XCTAssertEqual(machine.handle(.assist(hasTopic: false)), [])
        XCTAssertEqual(machine.presentation, .panel)
    }

    /// "Demander": the panel takes the keyboard only while typing, then gives it back.
    func test_typingTakesTheKeyboardOnlyWhileTyping() {
        var machine = OverlayMachine()

        XCTAssertEqual(machine.handle(.startTyping), [.takeKeyboard])
        XCTAssertEqual(machine.presentation, .panel)
        XCTAssertTrue(machine.isTyping)

        XCTAssertEqual(machine.handle(.endTyping), [.giveKeyboardBack])
        XCTAssertFalse(machine.isTyping)
        XCTAssertEqual(machine.handle(.endTyping), [], "nothing to give back twice")
    }

    func test_hidingOrFoldingWhileTypingGivesTheKeyboardBackFirst() {
        var machine = OverlayMachine()
        machine.handle(.startTyping)
        XCTAssertEqual(machine.handle(.toggleVisibility), [.giveKeyboardBack])
        XCTAssertFalse(machine.isTyping)

        machine.handle(.toggleVisibility)
        machine.handle(.startTyping)
        XCTAssertEqual(machine.handle(.pillClicked), [.giveKeyboardBack])
        XCTAssertEqual(machine.presentation, .pill)
    }

    func test_repeatedPanelToggleNeverAnswersOrTakesKeyboard() {
        var machine = OverlayMachine()
        for _ in 0..<20 {
            XCTAssertEqual(machine.handle(.pillClicked), [])
            XCTAssertEqual(machine.presentation, .panel)
            XCTAssertEqual(machine.handle(.pillClicked), [])
            XCTAssertEqual(machine.presentation, .pill)
            XCTAssertFalse(machine.isTyping)
        }
    }

    func test_panelToggleWhileHiddenIsNoOpAndPreservesRevealState() {
        for expanded in [false, true] {
            var machine = OverlayMachine()
            if expanded { machine.handle(.pillClicked) }
            machine.handle(.toggleVisibility)
            let hidden = machine
            for _ in 0..<5 {
                XCTAssertEqual(machine.handle(.pillClicked), [])
                XCTAssertEqual(machine, hidden)
            }
            machine.handle(.toggleVisibility)
            XCTAssertEqual(machine.presentation, expanded ? .panel : .pill)
        }
    }

    /// An answer started from elsewhere (⌥1, ⌘⇧↩) needs the panel to be seen.
    func test_anAnswerUnfoldsThePill_butNotAHiddenOverlay() {
        var machine = OverlayMachine()
        machine.handle(.answerStarted)
        XCTAssertEqual(machine.presentation, .panel)

        machine.handle(.toggleVisibility)
        machine.handle(.answerStarted)
        XCTAssertEqual(machine.presentation, .hidden, "⌘\\ hid it on purpose: it stays hidden")
    }
}
