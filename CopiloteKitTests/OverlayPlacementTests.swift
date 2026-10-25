import CoreGraphics
import XCTest
@testable import CopiloteKit

final class OverlayPlacementTests: XCTestCase {
    func test_wideWorkspaceReachesNeighbourAndReversesImmediatelyAtBottom() {
        let left = ScreenArea(id: "left", visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        let right = ScreenArea(id: "right", visibleFrame: CGRect(x: 1200, y: 0, width: 1200, height: 900))
        let pill = CGSize(width: 480, height: 40), panel = CGSize(width: 829, height: 651)
        var placement = OverlayPlacement()
        var landed = left
        for _ in 0..<30 {
            landed = placement.moveWorkspace(.right, pillSize: pill, panelSize: panel, on: landed, among: [left, right])
        }
        XCTAssertEqual(landed.id, right.id)
        for _ in 0..<30 { _ = placement.moveWorkspace(.down, pillSize: pill, panelSize: panel, on: right, among: [right]) }
        let bottom = placement.workspaceFrames(pillSize: pill, panelSize: panel, on: right)
        XCTAssertEqual(bottom.panel.minY, right.visibleFrame.minY)
        _ = placement.moveWorkspace(.up, pillSize: pill, panelSize: panel, on: right, among: [right])
        XCTAssertEqual(placement.workspaceFrames(pillSize: pill, panelSize: panel, on: right).panel.minY, OverlayPlacement.step)
    }

    func test_workspaceMovesAsRigidBlockAndFitsSmallOrOffsetDisplays() {
        for area in [CGRect(x: 0, y: 0, width: 1512, height: 900), CGRect(x: -1920, y: -80, width: 1920, height: 1000), CGRect(x: 0, y: 0, width: 430, height: 500)] {
            let screen = ScreenArea(id: "test", visibleFrame: area)
            for origin in [CGPoint(x: -5000, y: -5000), CGPoint(x: 5000, y: 5000), CGPoint(x: 200, y: 400)] {
                var placement = OverlayPlacement()
                placement.remember(pillFrame: CGRect(origin: origin, size: CGSize(width: 480, height: 40)), on: screen)
                let frames = placement.workspaceFrames(pillSize: CGSize(width: 480, height: 40), panelSize: CGSize(width: 600, height: 640), on: screen)
                XCTAssertTrue(area.contains(frames.pill)); XCTAssertTrue(area.contains(frames.panel))
                XCTAssertEqual(frames.pill.midX, frames.panel.midX)
                XCTAssertEqual(frames.pill.minY - frames.panel.maxY, OverlayPlacement.gap)
                XCTAssertEqual(frames.panel.height, min(640, area.height - 48))
            }
        }
    }

    private let laptop = ScreenArea(id: "laptop", visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944))
    private let display = ScreenArea(id: "display", visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415))
    private let pill = CGSize(width: 420, height: 40)

    func test_thePillStartsCenteredAtTheTopOfTheScreen() {
        let frame = OverlayPlacement().pillFrame(size: pill, on: laptop)

        XCTAssertEqual(frame, CGRect(x: 546, y: 894, width: 420, height: 40))
    }

    /// ⌘ + arrows move by steps, on that screen only.
    func test_arrowsMoveByStepsAndEachScreenKeepsItsOwnPlace() {
        var placement = OverlayPlacement()

        placement.move(.right, pillSize: pill, on: laptop)
        placement.move(.right, pillSize: pill, on: laptop)
        placement.move(.down, pillSize: pill, on: laptop)

        XCTAssertEqual(placement.pillFrame(size: pill, on: laptop).origin, CGPoint(x: 546 + 2 * OverlayPlacement.step, y: 894 - OverlayPlacement.step))
        XCTAssertEqual(placement.pillFrame(size: pill, on: display), OverlayPlacement().pillFrame(size: pill, on: display))
    }

    func test_thePillNeverLeavesTheScreen() {
        var placement = OverlayPlacement()
        for _ in 0..<40 { placement.move(.left, pillSize: pill, on: laptop) }
        for _ in 0..<40 { placement.move(.up, pillSize: pill, on: laptop) }

        let frame = placement.pillFrame(size: pill, on: laptop)
        XCTAssertEqual(frame.minX, 0)
        XCTAssertEqual(frame.maxY, 944)
    }

    /// The panel hangs under the pill, centred on it, and stays on screen.
    func test_thePanelHangsUnderThePill_withinTheScreen() {
        var placement = OverlayPlacement()
        for _ in 0..<40 { placement.move(.right, pillSize: pill, on: laptop) }
        let pillFrame = placement.pillFrame(size: pill, on: laptop)

        let panel = placement.panelFrame(size: CGSize(width: 440, height: 640), below: pillFrame, on: laptop)

        XCTAssertEqual(panel.maxY, pillFrame.minY - 8)
        XCTAssertEqual(panel.maxX, 1512, "pushed back inside the screen")
        let tall = placement.panelFrame(size: CGSize(width: 440, height: 2000), below: pillFrame, on: laptop)
        XCTAssertEqual(tall.minY, 0, "shortened to fit")
    }

    /// Dragging the pill by hand: that place becomes the screen's place.
    func test_aDraggedPillKeepsItsNewPlace() {
        var placement = OverlayPlacement()

        placement.remember(pillFrame: CGRect(x: 100, y: 700, width: 420, height: 40), on: laptop)

        XCTAssertEqual(placement.pillFrame(size: pill, on: laptop).origin, CGPoint(x: 100, y: 700))
    }

    func test_thePlaceIsRememberedAcrossLaunches() throws {
        var placement = OverlayPlacement()
        placement.move(.left, pillSize: pill, on: display)

        let restored = try JSONDecoder().decode(OverlayPlacement.self, from: JSONEncoder().encode(placement))

        XCTAssertEqual(restored.pillFrame(size: pill, on: display), placement.pillFrame(size: pill, on: display))
    }
}

/// Opening the app (launch, Dock, Finder, Spotlight) brings the pill back to the top centre of the
/// cursor's screen, wherever it was dragged before.
final class OverlayPlacementHomeTests: XCTestCase {
    func test_goingHomeForgetsWhereThePillWasMovedOnThatScreen() {
        let screen = ScreenArea(id: "1", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
        let other = ScreenArea(id: "2", visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))
        let pill = CGSize(width: 520, height: 40)
        var placement = OverlayPlacement()
        placement.remember(pillFrame: CGRect(x: 0, y: 300, width: 520, height: 40), on: screen)
        placement.move(.left, pillSize: pill, on: other)

        placement.goHome(on: screen)

        XCTAssertEqual(placement.pillFrame(size: pill, on: screen), CGRect(x: 460, y: 825, width: 520, height: 40), "top centre")
        XCTAssertNotEqual(placement.pillFrame(size: pill, on: other).midX, other.visibleFrame.midX, "the other screen keeps its place")
    }
}

/// Pill and panel are one block, whichever is dragged, and it always lands on one screen.
final class OverlayBlockTests: XCTestCase {
    private let screen = ScreenArea(id: "1", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    private let pill = CGSize(width: 520, height: 40)
    private let panel = CGSize(width: 440, height: 460)

    func test_draggingThePanelMovesThePillWithIt() {
        var placement = OverlayPlacement()

        placement.remember(panelFrame: CGRect(x: 100, y: 200, width: 440, height: 460), pillSize: pill, on: screen)

        let pillFrame = placement.pillFrame(size: pill, on: screen)
        XCTAssertEqual(pillFrame.midX, 320, "centred over the panel")
        XCTAssertEqual(pillFrame.minY, 668, "just above it")
        XCTAssertEqual(placement.panelFrame(size: panel, below: pillFrame, on: screen), CGRect(x: 100, y: 200, width: 440, height: 460))
    }

    func test_aBlockDroppedAcrossTheEdgeLandsFullyInside() {
        var placement = OverlayPlacement()

        placement.remember(pillFrame: CGRect(x: 1300, y: 860, width: 520, height: 40), on: screen)

        XCTAssertTrue(screen.visibleFrame.contains(placement.pillFrame(size: pill, on: screen)))
    }

    /// Too close to the bottom for the panel under it: the panel opens above the pill, never over it.
    func test_nearTheBottomThePanelOpensAboveThePill() {
        let low = CGRect(x: 460, y: 60, width: 520, height: 40)

        let frame = OverlayPlacement().panelFrame(size: panel, below: low, on: screen)

        XCTAssertFalse(frame.intersects(low))
        XCTAssertEqual(frame.minY, low.maxY + 8)
        XCTAssertTrue(screen.visibleFrame.contains(frame))
    }
}

/// ⌃⌘ + arrow at the edge of a screen: the block goes to the screen on that side (Cluely's
/// « Change display »).
final class NeighbourScreenTests: XCTestCase {
    private let left = ScreenArea(id: "1", visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 870))
    private let right = ScreenArea(id: "2", visibleFrame: CGRect(x: 1512, y: -200, width: 1920, height: 1050))

    func test_theScreenOnThatSide() {
        XCTAssertEqual(OverlayPlacement.neighbour(of: left, toward: .right, among: [left, right]), right)
        XCTAssertEqual(OverlayPlacement.neighbour(of: right, toward: .left, among: [left, right]), left)
        XCTAssertNil(OverlayPlacement.neighbour(of: left, toward: .left, among: [left, right]))
        XCTAssertNil(OverlayPlacement.neighbour(of: left, toward: .up, among: [left, right]))
    }

    /// ⌃⌘ + arrow: a step on this screen while there is room, then on to the screen on that side.
    func test_aKeyboardMoveStepsThenCrossesToTheNextScreenAtTheEdge() {
        let pill = CGSize(width: 460, height: 40)
        var placement = OverlayPlacement()

        XCTAssertEqual(placement.move(.right, pillSize: pill, on: left, among: [left, right]), left, "room left: a step")
        for _ in 0..<20 { _ = placement.move(.right, pillSize: pill, on: left, among: [left, right]) }
        XCTAssertEqual(placement.pillFrame(size: pill, on: left).maxX, left.visibleFrame.maxX, "stopped whole against the edge")

        XCTAssertEqual(placement.move(.right, pillSize: pill, on: left, among: [left, right]), right, "against the edge: the next screen")
        XCTAssertEqual(placement.move(.right, pillSize: pill, on: right, among: [left, right]), right, "nothing further: stays")
    }
}
