import XCTest
@testable import CopiloteKit

/// The pill's ⚙ menu, drawn in an excluded panel (an NSMenu is a system window, visible in a
/// screen share), with an NSMenu's keyboard: ↑ ↓ skip what can't be chosen and wrap, Home / End,
/// Return or Space choose.
final class OverlayMenuTests: XCTestCase {
    private let menu = OverlayMenu(entries: [
        .info("Codex · gpt-5.6-luna"),
        .separator,
        .header("Mode"),
        .choice(id: "mode.meeting", title: "Réunion", isChecked: true),
        .choice(id: "mode.technical", title: "Technique", isChecked: false),
        .separator,
        .action(id: "openApp", title: "Réglages, historique et base…"),
        .action(id: "recenter", title: "Remettre la pilule au centre"),
        .separator,
        .action(id: "quit", title: "Quitter Copilote"),
    ])

    func test_nothingIsSelectedUntilAnArrow_thenTheFirstOrLastChoosableEntry() {
        var down = menu
        XCTAssertNil(down.selectedID)
        down.moveDown()
        XCTAssertEqual(down.selectedID, "mode.meeting")

        var up = menu
        up.moveUp()
        XCTAssertEqual(up.selectedID, "quit")
    }

    func test_arrowsSkipInfoHeadersAndSeparators_andWrap() {
        var menu = menu
        menu.moveDown()
        menu.moveDown()
        menu.moveDown()
        XCTAssertEqual(menu.selectedID, "openApp", "the separator is skipped")
        menu.moveDown()
        menu.moveDown()
        XCTAssertEqual(menu.selectedID, "quit")
        menu.moveDown()
        XCTAssertEqual(menu.selectedID, "mode.meeting", "wraps to the top")
        menu.moveUp()
        XCTAssertEqual(menu.selectedID, "quit", "and to the bottom")
    }

    func test_homeEndAndTheMouse() {
        var menu = menu
        menu.selectLast()
        XCTAssertEqual(menu.selectedID, "quit")
        menu.selectFirst()
        XCTAssertEqual(menu.selectedID, "mode.meeting")
        menu.select(index: 7)
        XCTAssertEqual(menu.selectedID, "recenter")
        menu.select(index: 2)
        XCTAssertEqual(menu.selectedID, "recenter", "a header can't be selected: the selection stays")
    }
}

extension OverlayMenuTests {
    /// The keys an NSMenu answers to (AZERTY or not: they are physical keys).
    func test_keysOfAnNSMenu() {
        XCTAssertEqual(OverlayMenu.command(forKeyCode: 125), .down)
        XCTAssertEqual(OverlayMenu.command(forKeyCode: 126), .up)
        XCTAssertEqual(OverlayMenu.command(forKeyCode: 115), .first, "Home")
        XCTAssertEqual(OverlayMenu.command(forKeyCode: 116), .first, "Page Up")
        XCTAssertEqual(OverlayMenu.command(forKeyCode: 119), .last, "End")
        XCTAssertEqual(OverlayMenu.command(forKeyCode: 121), .last, "Page Down")
        for key in [36, 76, 49] { XCTAssertEqual(OverlayMenu.command(forKeyCode: key), .choose, "Return, Enter, Space") }
        XCTAssertEqual(OverlayMenu.command(forKeyCode: 53), .close, "Échap")
        XCTAssertNil(OverlayMenu.command(forKeyCode: 0), "a letter does nothing")
    }
}

/// What the ⚙ menu does, as an entry's id and back: every mode, the main window, recentring, the
/// tour, quitting; an unknown id is nothing.
final class PillMenuActionTests: XCTestCase {
    func test_eachActionComesBackFromItsID() {
        let actions: [PillMenuAction] = MeetingMode.allCases.map(PillMenuAction.mode) + [.openApp, .recenter, .tour, .quit]
        for action in actions { XCTAssertEqual(PillMenuAction(id: action.id), action, action.id) }
        XCTAssertEqual(Set(actions.map(\.id)).count, actions.count, "ids are distinct")
        XCTAssertNil(PillMenuAction(id: "mode.unknown"))
    }
}

/// The menu opens under ⚙, right-aligned with it, above it when there is no room below, always
/// whole on the screen.
final class PopoverPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 870)
    private let size = CGSize(width: 260, height: 220)

    func test_underTheButtonRightAligned() {
        let gear = CGRect(x: 1000, y: 800, width: 28, height: 28)
        XCTAssertEqual(PopoverPlacement.frame(size: size, anchor: gear, on: screen), CGRect(x: 768, y: 576, width: 260, height: 220))
    }

    func test_aboveWhenNoRoomBelow() {
        let gear = CGRect(x: 1000, y: 100, width: 28, height: 28)
        XCTAssertEqual(PopoverPlacement.frame(size: size, anchor: gear, on: screen).minY, 132)
    }

    func test_keptOnTheScreenSideways() {
        let gear = CGRect(x: 100, y: 800, width: 28, height: 28)
        XCTAssertEqual(PopoverPlacement.frame(size: size, anchor: gear, on: screen).minX, 0)
    }
}
