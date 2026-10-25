import CoreGraphics
import XCTest
@testable import CopiloteKit

/// ⌘⇧A: the selection is drawn in AppKit points (origin bottom-left) over a frozen
/// screenshot whose pixels start top-left, at the screen's backing scale.
final class CaptureGeometryTests: XCTestCase {
    func test_selectionInPointsMapsToTheSameAreaInRetinaPixels() {
        let selection = CGRect(x: 100, y: 50, width: 200, height: 100) // 50 pt above the bottom edge

        let pixels = CaptureGeometry.pixelRect(for: selection, viewSize: CGSize(width: 1000, height: 500), imageWidth: 2000)

        XCTAssertEqual(pixels, CGRect(x: 200, y: 700, width: 400, height: 200))
    }

    func test_fractionalSelectionsGrowToWholePixels() {
        let selection = CGRect(x: 10.3, y: 10.3, width: 20.2, height: 20.2)

        let pixels = CaptureGeometry.pixelRect(for: selection, viewSize: CGSize(width: 100, height: 100), imageWidth: 100)

        XCTAssertEqual(pixels, CGRect(x: 10, y: 69, width: 21, height: 21))
    }
}
