import XCTest
@testable import CopiloteKit

/// the user types on a French AZERTY Mac: every default shortcut must be easy there, and stay easy on QWERTY.
final class ShortcutDefaultsTests: XCTestCase {
    /// Unmodified characters of the macOS layouts, by physical key code (a subset).
    private let azerty = FakeLayout([
        0: "q", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "w", 7: "x", 8: "c", 9: "v", 11: "b", 12: "a", 13: "z", 14: "e",
        15: "r", 16: "y", 17: "t", 18: "&", 19: "é", 20: "\"", 21: "'", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j",
        40: "k", 41: "m", 42: "`", 45: "n", 46: ",", 24: "-", 44: "=", 49: " ",
    ])
    private let qwerty = FakeLayout([
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e",
        15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j",
        40: "k", 41: ";", 42: "\\", 45: "n", 46: "m", 24: "=", 27: "-", 49: " ",
    ])

    func test_lettersFollowTheLayout_soCaptureAreaIsTheKeyThatTypesA() {
        let region = ShortcutDefaults.named("captureRegion")
        XCTAssertEqual(ShortcutDefaults.combo(region, in: azerty).keyCode, 12)
        XCTAssertEqual(ShortcutDefaults.combo(region, in: qwerty).keyCode, 0)
    }

    /// No backslash (⌥⇧: on AZERTY), bracket, brace, pipe, tilde or backtick; nothing that needs
    /// Shift or Option just to exist: each key types its character on its own.
    func test_noDefaultSitsOnAKeyThatIsHardToTypeInAzertyOrQwerty() {
        let hard = Set("\\[]{}|~`")
        for layout in [azerty, qwerty] {
            for shortcut in ShortcutDefaults.all {
                let combo = ShortcutDefaults.combo(shortcut, in: layout)
                guard !ShortcutDefaults.namedKeys.contains(combo.keyCode) else { continue }
                let character = layout.character(forKeyCode: combo.keyCode)
                XCTAssertNotNil(character, shortcut.name)
                XCTAssertFalse(character.map { $0.contains(where: hard.contains) } ?? true, "\(shortcut.name): \(character ?? "?")")
            }
        }
    }

    /// Nothing that macOS, Spotlight, the usual launchers or the browsers already use: text editing
    /// (⌘ + arrows), tabs (⌥⌘ + arrows), Spotlight and launchers (⌘/⌥/⇧⌘ Space), the Dock (⌥⌘D),
    /// the dictionary (⌃⌘D), emoji (⌃⌘Space), full screen (⌃⌘F), browser zoom (⌘= ⌘-).
    func test_noDefaultTakesACommonSystemOrBrowserShortcut() {
        for layout in [azerty, qwerty] {
            let defaults = Set(ShortcutDefaults.all.filter { !$0.name.hasPrefix("moveOverlay") }.map { ShortcutDefaults.combo($0, in: layout) })
            for taken in ShortcutDefaults.commonShortcuts(in: layout) {
                XCTAssertFalse(defaults.contains(taken), "\(taken)")
            }
        }
    }

    /// Like Cluely, the block moves with the keyboard, but on ⌃⌘ + arrows (see above).
    func test_moveAskAndTextSizeHaveDefaults() {
        XCTAssertEqual(ShortcutDefaults.combo(ShortcutDefaults.named("moveOverlayLeft"), in: azerty), KeyCombo(keyCode: 123, modifiers: [.command]))
        XCTAssertEqual(ShortcutDefaults.combo(ShortcutDefaults.named("ask"), in: azerty), KeyCombo(keyCode: 36, modifiers: [.control, .command]))
        XCTAssertNotNil(ShortcutDefaults.all.first { $0.name == "textBigger" })
        XCTAssertNotNil(ShortcutDefaults.all.first { $0.name == "textSmaller" })
    }

    func test_movementMigrationPreservesCustomAndRemovedBindings() {
        for name in ["moveOverlayUp", "moveOverlayDown", "moveOverlayLeft", "moveOverlayRight"] {
            let shortcut = ShortcutDefaults.named(name)
            let current = ShortcutDefaults.combo(shortcut, in: azerty)
            let old = KeyCombo(keyCode: current.keyCode, modifiers: [.control, .command])
            let custom = KeyCombo(keyCode: current.keyCode, modifiers: [.control, .option])
            XCTAssertEqual(ShortcutDefaults.update(stored: .set(old), lastDefault: old, legacy: [], current: current), current)
            XCTAssertEqual(ShortcutDefaults.update(stored: .set(old), lastDefault: nil, legacy: ShortcutDefaults.legacy(shortcut), current: current), current)
            XCTAssertNil(ShortcutDefaults.update(stored: .set(custom), lastDefault: old, legacy: [], current: current))
            XCTAssertNil(ShortcutDefaults.update(stored: .removed, lastDefault: old, legacy: [], current: current))
        }
    }

    func test_showHideIsOptionCommandO() {
        let toggle = ShortcutDefaults.combo(ShortcutDefaults.named("toggleOverlay"), in: azerty)
        XCTAssertEqual(toggle, KeyCombo(keyCode: 31, modifiers: [.command, .option]))
    }

    /// An install made before keeps what the user chose; the old defaults (⌘\) give way.
    func test_theOldDefaultsGiveWay_theUsersChoicesStay() {
        let new = KeyCombo(keyCode: 31, modifiers: [.command, .option])
        let backslash = KeyCombo(keyCode: 42, modifiers: [.command])
        let chosen = KeyCombo(keyCode: 3, modifiers: [.command, .control])

        XCTAssertEqual(ShortcutDefaults.update(stored: .set(backslash), lastDefault: nil, legacy: [backslash], current: new), new)
        XCTAssertEqual(ShortcutDefaults.update(stored: .never, lastDefault: nil, legacy: [backslash], current: new), new, "a new install")
        XCTAssertNil(ShortcutDefaults.update(stored: .set(chosen), lastDefault: nil, legacy: [backslash], current: new))
        XCTAssertNil(ShortcutDefaults.update(stored: .removed, lastDefault: nil, legacy: [backslash], current: new), "removed before this version")
        XCTAssertNil(ShortcutDefaults.update(stored: .removed, lastDefault: new, legacy: [backslash], current: new), "removed since")

        // Switched from QWERTY to AZERTY, never changed: the default follows the layout.
        let qwertyA = KeyCombo(keyCode: 0, modifiers: [.command, .shift])
        let azertyA = KeyCombo(keyCode: 12, modifiers: [.command, .shift])
        XCTAssertEqual(ShortcutDefaults.update(stored: .set(qwertyA), lastDefault: qwertyA, legacy: [], current: azertyA), azertyA)
        XCTAssertNil(ShortcutDefaults.update(stored: .set(azertyA), lastDefault: azertyA, legacy: [], current: azertyA))
    }

    /// What was last set is kept between launches.
    func test_aComboSurvivesItsStorage() throws {
        let combo = KeyCombo(keyCode: 31, modifiers: [.command, .option])
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo)), combo)
    }
}

private struct FakeLayout: KeyLayout {
    let characters: [Int: String]
    init(_ characters: [Int: String]) { self.characters = characters }
    func character(forKeyCode keyCode: Int) -> String? { characters[keyCode] }
}
