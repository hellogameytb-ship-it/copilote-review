import CoreGraphics

/// The pill's ⚙ menu, drawn in one of Copilote's own panels: an NSMenu is a system window that
/// `sharingType = .none` does not cover, so it showed in screen shares. The keyboard of an
/// NSMenu: ↑ ↓ skip what can't be chosen and wrap, Home / End, Return or Space choose.
public struct OverlayMenu: Equatable, Sendable {
    public enum Entry: Equatable, Sendable {
        /// A line to read (the provider), not chosen.
        case info(String)
        case header(String)
        /// One of a group (the mode), ticked when current.
        case choice(id: String, title: String, isChecked: Bool)
        case action(id: String, title: String)
        case separator

        public var id: String? {
            switch self {
            case let .choice(id, _, _), let .action(id, _): return id
            case .info, .header, .separator: return nil
            }
        }
    }

    public let entries: [Entry]
    /// Nothing until an arrow or the mouse, like an NSMenu opened by a click.
    public private(set) var selected: Int?

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public var selectedID: String? { selected.flatMap { entries[$0].id } }

    private var choosable: [Int] { entries.indices.filter { entries[$0].id != nil } }

    public mutating func moveDown() {
        guard let first = choosable.first else { return }
        guard let selected else { return self.selected = first }
        self.selected = choosable.first { $0 > selected } ?? first
    }

    public mutating func moveUp() {
        guard let last = choosable.last else { return }
        guard let selected else { return self.selected = last }
        self.selected = choosable.last { $0 < selected } ?? last
    }

    public mutating func selectFirst() {
        selected = choosable.first
    }

    public mutating func selectLast() {
        selected = choosable.last
    }

    public enum Command: Equatable, Sendable {
        case down, up, first, last, choose, close
    }

    /// An NSMenu's keys, by physical key code: ↓ ↑, Home / Page Up, End / Page Down, Return,
    /// Enter or Space, Échap.
    public static func command(forKeyCode keyCode: Int) -> Command? {
        switch keyCode {
        case 125: return .down
        case 126: return .up
        case 115, 116: return .first
        case 119, 121: return .last
        case 36, 76, 49: return .choose
        case 53: return .close
        default: return nil
        }
    }

    /// The mouse over an entry; over a header or a separator the selection stays.
    public mutating func select(index: Int) {
        guard entries.indices.contains(index), entries[index].id != nil else { return }
        selected = index
    }
}

/// A small panel hung on a button (the ⚙ menu): under it, right-aligned with it, above it when
/// there is no room below, always whole on the screen.
public enum PopoverPlacement {
    public static let gap: CGFloat = 4

    public static func frame(size: CGSize, anchor: CGRect, on screen: CGRect) -> CGRect {
        let x = min(max(anchor.maxX - size.width, screen.minX), screen.maxX - size.width)
        let below = anchor.minY - gap - size.height
        let y = below >= screen.minY ? below : min(anchor.maxY + gap, screen.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// What the pill's ⚙ menu does; an entry's id is `id`.
public enum PillMenuAction: Equatable, Sendable {
    case mode(MeetingMode)
    case openApp, recenter, tour, quit

    public var id: String {
        switch self {
        case let .mode(mode): return "mode." + mode.rawValue
        case .openApp: return "openApp"
        case .recenter: return "recenter"
        case .tour: return "tour"
        case .quit: return "quit"
        }
    }

    public init?(id: String) {
        let all: [PillMenuAction] = MeetingMode.allCases.map(PillMenuAction.mode) + [.openApp, .recenter, .tour, .quit]
        guard let action = all.first(where: { $0.id == id }) else { return nil }
        self = action
    }
}
