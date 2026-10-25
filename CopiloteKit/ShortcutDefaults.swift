import Foundation

/// A key on the keyboard (macOS virtual key code: a physical place, whatever the layout) and
/// its modifiers.
public struct KeyCombo: Hashable, Sendable, Codable {
    public let keyCode: Int
    public let modifiers: KeyModifiers

    public init(keyCode: Int, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(keyCode: Int, carbonModifiers: Int) {
        self.init(keyCode: keyCode, modifiers: KeyModifiers(carbon: carbonModifiers))
    }

    public var carbonModifiers: Int { modifiers.carbon }
}

public struct KeyModifiers: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)

    /// Carbon's bits (cmdKey, shiftKey, optionKey, controlKey), as global hotkeys store them.
    private static let carbonBits: [(KeyModifiers, Int)] = [(.command, 1 << 8), (.shift, 1 << 9), (.option, 1 << 11), (.control, 1 << 12)]

    init(carbon: Int) {
        self = Self.carbonBits.reduce(into: []) { result, pair in if carbon & pair.1 != 0 { result.insert(pair.0) } }
    }

    var carbon: Int {
        Self.carbonBits.reduce(0) { result, pair in contains(pair.0) ? result | pair.1 : result }
    }
}

/// What a physical key types with no modifier, in the current layout ("&" for the 1 key in AZERTY).
public protocol KeyLayout {
    func character(forKeyCode keyCode: Int) -> String?
}

/// The shortcuts Copilote starts with, easy on AZERTY as on QWERTY: letters are found by the
/// character they type in the current layout (⌘⇧A is the key that types "a"), other keys by
/// their place (Return, arrows, the digit row: what the key types there is what is shown).
/// Nothing on \ [ ] { } | ~ `, nothing that needs Shift or Option just to exist.
public enum ShortcutDefaults {
    public enum Key: Equatable, Sendable {
        case character(String)
        case physical(Int)
    }

    public struct Default: Equatable, Sendable {
        public let name: String
        public let key: Key
        public let modifiers: KeyModifiers
    }

    /// Return, the arrows, space: the same everywhere, shown by their symbol.
    public static let namedKeys: Set<Int> = [36, 49, 123, 124, 125, 126]

    public static let all: [Default] = [
        // ⌥⌘O, O for overlay: free in macOS and the usual launchers (Spotlight ⌘Space, ChatGPT,
        // Raycast and Alfred ⌥Space, 1Password ⇧⌘Space).
        Default(name: "toggleOverlay", key: .character("o"), modifiers: [.command, .option]),
        Default(name: "togglePanel", key: .character("p"), modifiers: [.command, .option]),
        Default(name: "captureScreen", key: .character("s"), modifiers: [.command, .shift]),
        Default(name: "captureRegion", key: .character("a"), modifiers: [.command, .shift]),
        Default(name: "sendCaptures", key: .physical(36), modifiers: [.command, .shift]),
        Default(name: "sendClipboard", key: .character("v"), modifiers: [.command, .shift]),
        Default(name: "clearContext", key: .character("x"), modifiers: [.command, .shift]),
        Default(name: "scrollAnswerUp", key: .physical(126), modifiers: [.command, .shift]),
        Default(name: "scrollAnswerDown", key: .physical(125), modifiers: [.command, .shift]),
        // Explicit user preference: ⌘ + arrows move the workspace outside Copilote editors.
        // Registration is released while Ask, a note, or settings owns text input.
        Default(name: "moveOverlayUp", key: .physical(126), modifiers: [.command]),
        Default(name: "moveOverlayDown", key: .physical(125), modifiers: [.command]),
        Default(name: "moveOverlayLeft", key: .physical(123), modifiers: [.command]),
        Default(name: "moveOverlayRight", key: .physical(124), modifiers: [.command]),
        // ⌃⌘↩ « Demander » (Cluely: ⌘↩), next to ⌘↩ and ⇧⌘↩; ⇧⌘D is Finder, Mail and Safari.
        Default(name: "ask", key: .physical(36), modifiers: [.control, .command]),
        // ⌥⌘= / ⌥⌘-: the answer's text size (Final Round: ⌥= / ⌥-), panel unfolded only.
        Default(name: "textBigger", key: .character("="), modifiers: [.command, .option]),
        Default(name: "textSmaller", key: .character("-"), modifiers: [.command, .option]),
        Default(name: "meetingNotes", key: .character("n"), modifiers: [.command, .shift]),
        // ⌃⌥⌘T, T for "à travers": ⌥⌘T alone is « Afficher la barre d'outils » in most apps.
        Default(name: "toggleClickThrough", key: .character("t"), modifiers: [.control, .command, .option]),
        Default(name: "toggleListening", key: .character("l"), modifiers: [.command, .shift]),
        Default(name: "answerLatestTopic", key: .physical(36), modifiers: [.command]),
    ] + (1...4).flatMap { index in
        [
            // The digit row by place: ⌥& ⌥é ⌥" ⌥' on AZERTY, ⌥1 ⌥2 ⌥3 ⌥4 on QWERTY.
            Default(name: "answerTopic\(index)", key: .physical(17 + index), modifiers: [.option]),
            Default(name: "pinTopic\(index)", key: .physical(17 + index), modifiers: [.option, .shift]),
        ]
    }

    public static func named(_ name: String) -> Default {
        all.first { $0.name == name }!
    }

    /// The key in this layout.
    public static func combo(_ shortcut: Default, in layout: KeyLayout) -> KeyCombo {
        switch shortcut.key {
        case let .physical(keyCode):
            return KeyCombo(keyCode: keyCode, modifiers: shortcut.modifiers)
        case let .character(character):
            let us = usKeyCodes[character]
            if let us, layout.character(forKeyCode: us)?.lowercased() == character {
                return KeyCombo(keyCode: us, modifiers: shortcut.modifiers)
            }
            let found = (0..<128).first { layout.character(forKeyCode: $0)?.lowercased() == character }
            return KeyCombo(keyCode: found ?? us ?? 0, modifiers: shortcut.modifiers)
        }
    }

    /// The defaults of the first versions (US places, ⌘\ to show and hide), to replace where the
    /// user never changed them.
    public static func legacy(_ shortcut: Default) -> [KeyCombo] {
        if shortcut.name.hasPrefix("moveOverlay"), case let .physical(keyCode) = shortcut.key {
            return [KeyCombo(keyCode: keyCode, modifiers: [.control, .command])]
        }
        switch shortcut.name {
        case "togglePanel": return [] // Added later: no historical binding to migrate.
        case "toggleOverlay": return [KeyCombo(keyCode: 42, modifiers: [.command])]
        case "toggleClickThrough": return [KeyCombo(keyCode: 42, modifiers: [.command, .option])]
        default:
            guard case let .character(character) = shortcut.key, let us = usKeyCodes[character] else { return [] }
            return [KeyCombo(keyCode: us, modifiers: shortcut.modifiers)]
        }
    }

    /// What a shortcut holds now: never set, removed by the user, or a key.
    public enum Stored: Equatable, Sendable {
        case never
        case removed
        case set(KeyCombo)
    }

    /// What to set now, or nil to leave the user's shortcut alone: the current default where the
    /// user never chose (a new install, an old default, the default of another layout). A removed
    /// shortcut stays removed.
    public static func update(stored: Stored, lastDefault: KeyCombo?, legacy: [KeyCombo], current: KeyCombo, occupied: Set<KeyCombo> = []) -> KeyCombo? {
        guard !occupied.contains(current) else { return nil }
        switch stored {
        case .never:
            return lastDefault == nil ? current : nil
        case .removed:
            return nil
        case let .set(combo):
            guard combo != current else { return nil }
            if let lastDefault { return combo == lastDefault ? current : nil }
            return legacy.contains(combo) ? current : nil
        }
    }

    /// Shortcuts macOS, Spotlight, the usual launchers and the browsers already use: no default may
    /// take one.
    public static func commonShortcuts(in layout: KeyLayout) -> [KeyCombo] {
        let arrows = [123, 124, 125, 126]
        let space = 49
        func character(_ c: String, _ modifiers: KeyModifiers) -> KeyCombo {
            combo(Default(name: c, key: .character(c), modifiers: modifiers), in: layout)
        }
        return arrows.map { KeyCombo(keyCode: $0, modifiers: [.command]) }               // text editing
            + arrows.map { KeyCombo(keyCode: $0, modifiers: [.command, .option]) }       // tabs
            + [[.command], [.option], [.command, .shift], [.control], [.control, .option], [.control, .command], [.command, .option]]
                .map { KeyCombo(keyCode: space, modifiers: $0) }                           // Spotlight, launchers, input sources, emoji, Finder
            + [character("d", [.command, .option]), character("d", [.control, .command]), character("f", [.control, .command]),
               character("d", [.command, .shift]),                                          // Finder Desktop, Mail Send
               character("q", [.control, .command]), character("=", [.command]), character("-", [.command]),
               character("h", [.command]), character("m", [.command]), character("q", [.command]), character("w", [.command])]
            + [20, 21, 23].map { KeyCombo(keyCode: $0, modifiers: [.command, .shift]) }   // screenshots ⇧⌘3 ⇧⌘4 ⇧⌘5
    }

    /// Where the letters are on a US keyboard (kVK_ANSI_*).
    static let usKeyCodes: [String: Int] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "=": 24, "-": 27,
    ]
}
