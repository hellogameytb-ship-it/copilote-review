import CoreGraphics
import Foundation

/// A screen's usable area (AppKit coordinates: origin bottom-left), named by its display id.
public struct ScreenArea: Equatable, Sendable {
    public let id: String
    public let visibleFrame: CGRect

    public init(id: String, visibleFrame: CGRect) {
        self.id = id
        self.visibleFrame = visibleFrame
    }
}

/// Where the pill sits on each screen: top-centre by default, moved by ⌃⌘ + arrows in steps,
/// remembered per screen. The panel hangs under the pill.
public struct OverlayPlacement: Codable, Equatable, Sendable {
    public enum Direction: Sendable {
        case up, down, left, right
    }

    public static let step: CGFloat = 48
    static let topMargin: CGFloat = 10
    /// Between the pill and what hangs from it (the panel, the tour).
    public static let gap: CGFloat = 8
    static let minimumPanelHeight: CGFloat = 180

    /// Offset of the pill from its default place, per screen id.
    private var offsets: [String: CGPoint] = [:]

    public init() {}

    public func pillFrame(size: CGSize, on screen: ScreenArea) -> CGRect {
        let offset = offsets[screen.id] ?? .zero
        let home = Self.defaultOrigin(size: size, in: screen.visibleFrame)
        return Self.clamped(CGRect(origin: CGPoint(x: home.x + offset.x, y: home.y + offset.y), size: size), in: screen.visibleFrame)
    }

    /// Top-centre of the screen.
    private static func defaultOrigin(size: CGSize, in area: CGRect) -> CGPoint {
        CGPoint(x: area.midX - size.width / 2, y: area.maxY - topMargin - size.height)
    }

    /// Under the pill; too close to the bottom of the screen for that, above it (never over it).
    public func panelFrame(size: CGSize, below pill: CGRect, on screen: ScreenArea) -> CGRect {
        let area = screen.visibleFrame
        let top = pill.minY - Self.gap
        let roomBelow = top - area.minY
        let roomAbove = area.maxY - (pill.maxY + Self.gap)
        if roomBelow < Self.minimumPanelHeight, roomAbove > roomBelow {
            let height = min(size.height, roomAbove)
            return Self.clamped(CGRect(x: pill.midX - size.width / 2, y: pill.maxY + Self.gap, width: size.width, height: height), in: area)
        }
        let height = max(Self.minimumPanelHeight, min(size.height, roomBelow))
        let frame = CGRect(x: pill.midX - size.width / 2, y: top - height, width: size.width, height: height)
        return Self.clamped(frame, in: area)
    }

    /// A single rigid workspace: keep both surfaces on screen without shrinking the panel
    /// as the user moves down, or flipping it above the pill at the lower edge.
    public func workspaceFrames(pillSize: CGSize, panelSize: CGSize, on screen: ScreenArea) -> (pill: CGRect, panel: CGRect) {
        let area = screen.visibleFrame
        let width = min(panelSize.width, area.width)
        let height = min(panelSize.height, max(0, area.height - pillSize.height - Self.gap))
        let groupWidth = max(min(pillSize.width, area.width), width)
        var pill = pillFrame(size: CGSize(width: min(pillSize.width, area.width), height: pillSize.height), on: screen)
        let center = min(max(pill.midX, area.minX + groupWidth / 2), area.maxX - groupWidth / 2)
        pill.origin.x = center - pill.width / 2
        pill.origin.y = max(pill.minY, area.minY + height + Self.gap)
        return (pill, CGRect(x: center - width / 2, y: pill.minY - Self.gap - height, width: width, height: height))
    }

    /// Test the whole group's edge, not only the narrower pill, before crossing displays.
    public mutating func moveWorkspace(_ direction: Direction, pillSize: CGSize, panelSize: CGSize, on screen: ScreenArea, among screens: [ScreenArea]) -> ScreenArea {
        let before = workspaceFrames(pillSize: pillSize, panelSize: panelSize, on: screen).pill
        remember(pillFrame: before, on: screen)
        move(direction, pillSize: pillSize, on: screen)
        let after = workspaceFrames(pillSize: pillSize, panelSize: panelSize, on: screen).pill
        remember(pillFrame: after, on: screen)
        if after == before { return Self.neighbour(of: screen, toward: direction, among: screens) ?? screen }
        return screen
    }

    public mutating func move(_ direction: Direction, pillSize: CGSize, on screen: ScreenArea) {
        var offset = offsets[screen.id] ?? .zero
        switch direction {
        case .up: offset.y += Self.step
        case .down: offset.y -= Self.step
        case .left: offset.x -= Self.step
        case .right: offset.x += Self.step
        }
        offsets[screen.id] = offset
        // Keep the offset where the clamped frame is, so the way back starts at once.
        remember(pillFrame: pillFrame(size: pillSize, on: screen), on: screen)
    }

    /// ⌃⌘ + arrow: a step on this screen; already against that edge, the screen on that side (the
    /// block goes where it was left there). Returns the screen the block is now on.
    public mutating func move(_ direction: Direction, pillSize: CGSize, on screen: ScreenArea, among screens: [ScreenArea]) -> ScreenArea {
        let before = pillFrame(size: pillSize, on: screen)
        move(direction, pillSize: pillSize, on: screen)
        guard pillFrame(size: pillSize, on: screen) == before else { return screen }
        return Self.neighbour(of: screen, toward: direction, among: screens) ?? screen
    }

    /// The panel was dragged: the pill sits centred just above it (one block, whichever part is held).
    public mutating func remember(panelFrame frame: CGRect, pillSize: CGSize, on screen: ScreenArea) {
        let pill = CGRect(x: frame.midX - pillSize.width / 2, y: frame.maxY + Self.gap, width: pillSize.width, height: pillSize.height)
        remember(pillFrame: pill, on: screen)
    }

    /// The screen on that side of this one (its centre beyond this one's edge), the nearest first.
    public static func neighbour(of screen: ScreenArea, toward direction: Direction, among screens: [ScreenArea]) -> ScreenArea? {
        let frame = screen.visibleFrame
        let beyond: (CGRect) -> Bool
        switch direction {
        case .left: beyond = { $0.midX < frame.minX }
        case .right: beyond = { $0.midX > frame.maxX }
        case .up: beyond = { $0.midY > frame.maxY }
        case .down: beyond = { $0.midY < frame.minY }
        }
        return screens
            .filter { $0.id != screen.id && beyond($0.visibleFrame) }
            .min { hypot($0.visibleFrame.midX - frame.midX, $0.visibleFrame.midY - frame.midY) < hypot($1.visibleFrame.midX - frame.midX, $1.visibleFrame.midY - frame.midY) }
    }

    /// « Remettre la pilule au centre »: back to the top centre of this screen.
    public mutating func goHome(on screen: ScreenArea) {
        offsets[screen.id] = nil
    }

    /// The pill was dragged there by hand.
    public mutating func remember(pillFrame frame: CGRect, on screen: ScreenArea) {
        let home = Self.defaultOrigin(size: frame.size, in: screen.visibleFrame)
        offsets[screen.id] = CGPoint(x: frame.minX - home.x, y: frame.minY - home.y)
    }

    private static func clamped(_ frame: CGRect, in area: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = min(max(frame.minX, area.minX), area.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, area.minY), area.maxY - frame.height)
        return frame
    }
}
