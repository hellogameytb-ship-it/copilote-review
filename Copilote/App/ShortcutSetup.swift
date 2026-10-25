import Carbon
import CopiloteKit
import KeyboardShortcuts

/// Sets each shortcut the user never chose to the default of the current keyboard layout
/// (`ShortcutDefaults`), at launch and when the layout changes. A shortcut the user recorded or
/// removed is left alone; the first versions' defaults (⌘\…) give way.
@MainActor
enum ShortcutSetup {
    private static var observer: NSObjectProtocol?

    static func start() {
        applyDefaults()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { applyDefaults() }
        }
    }

    static func applyDefaults() {
        let layout = CurrentKeyLayout()
        let store = UserDefaults.standard
        for shortcut in ShortcutDefaults.all {
            let name = KeyboardShortcuts.Name(shortcut.name)
            let current = ShortcutDefaults.combo(shortcut, in: layout)
            let stored = storedState(of: name)
            let key = "defaultShortcut-" + shortcut.name
            let lastDefault = lastDefault(store, key)
            if let new = ShortcutDefaults.update(stored: stored, lastDefault: lastDefault, legacy: ShortcutDefaults.legacy(shortcut), current: current) {
                install(new, for: shortcut)
            } else if stored == .set(current) {
                store.set(try? JSONEncoder().encode(current), forKey: key)
            }
        }
    }
}

extension ShortcutSetup {
    /// Settings › « Redo les raccourcis par défaut »: every shortcut back to this layout's
    /// default, recorded and removed ones included.
    static func resetToDefaults() {
        let layout = CurrentKeyLayout()
        for shortcut in ShortcutDefaults.all {
            install(ShortcutDefaults.combo(shortcut, in: layout), for: shortcut)
        }
    }

    /// Sets the shortcut to this default and records it as the last one set.
    private static func install(_ combo: KeyCombo, for shortcut: ShortcutDefaults.Default) {
        KeyboardShortcuts.setShortcut(
            KeyboardShortcuts.Shortcut(carbonKeyCode: combo.keyCode, carbonModifiers: combo.carbonModifiers), for: KeyboardShortcuts.Name(shortcut.name)
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: "defaultShortcut-" + shortcut.name)
    }

    /// The default last set (JSON; the first evening's builds kept `[keyCode, modifiers]`).
    private static func lastDefault(_ store: UserDefaults, _ key: String) -> KeyCombo? {
        if let data = store.data(forKey: key) { return try? JSONDecoder().decode(KeyCombo.self, from: data) }
        guard let pair = store.array(forKey: key) as? [Int], pair.count == 2 else { return nil }
        return KeyCombo(keyCode: pair[0], carbonModifiers: pair[1])
    }

    /// KeyboardShortcuts answers nil both for "never set" and "removed"; it keeps `false` under its
    /// key for a removed one.
    private static func storedState(of name: KeyboardShortcuts.Name) -> ShortcutDefaults.Stored {
        if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
            return .set(KeyCombo(keyCode: shortcut.carbonKeyCode, carbonModifiers: shortcut.carbonModifiers))
        }
        return UserDefaults.standard.object(forKey: "KeyboardShortcuts_" + name.rawValue) == nil ? .never : .removed
    }
}

/// What each physical key types with no modifier, in the current layout (Text Input Sources).
private struct CurrentKeyLayout: KeyLayout {
    private let data: Data?

    init() {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            data = nil
            return
        }
        data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    func character(forKeyCode keyCode: Int) -> String? {
        guard let data else { return nil }
        return data.withUnsafeBytes { raw -> String? in
            guard let keyboard = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                keyboard, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
