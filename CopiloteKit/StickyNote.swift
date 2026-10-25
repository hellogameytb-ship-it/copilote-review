import Foundation
import CoreGraphics

public struct StickyNote: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public var frame: CGRect
    public var isPinned = false
    public var includeInAI = false
    public var deletedAt: Date?
    public var profileID: String?
    public var title: String?
    public var sourceKey: String?

    public init(id: UUID = UUID(), text: String = "", frame: CGRect = CGRect(x: 100, y: 100, width: 280, height: 220)) {
        self.id = id; self.text = text; self.frame = frame
    }

    /// Keep restored notes reachable after a display disconnect or resolution change.
    public static func fitted(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        guard let screen = screens.max(by: { intersectionArea(frame, $0) < intersectionArea(frame, $1) }) else { return frame }
        let width = min(max(frame.width, 220), screen.width)
        let height = min(max(frame.height, 160), screen.height)
        return CGRect(x: min(max(frame.minX, screen.minX), screen.maxX - width), y: min(max(frame.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }
    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let area = lhs.intersection(rhs)
        return area.isNull ? 0 : area.width * area.height
    }
}
