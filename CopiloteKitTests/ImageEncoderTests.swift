import CoreGraphics
import ImageIO
import XCTest
@testable import CopiloteKit

final class ImageEncoderTests: XCTestCase {
    func test_encode_downscalesLargeScreenshotsToAMaxLongEdgeOf1600px_keepingAspectRatio() throws {
        let retinaScreenshot = try makeImage(width: 4000, height: 2500)

        let encoded = try XCTUnwrap(ImageEncoder.encodeForModel(retinaScreenshot))

        XCTAssertEqual(encoded.mediaType, "image/jpeg")
        XCTAssertEqual(try decodedSize(encoded.data), CGSize(width: 1600, height: 1000))
        XCTAssertEqual(encoded.pixelWidth, 1600)
        XCTAssertEqual(encoded.pixelHeight, 1000)
    }

    func test_encode_keepsSmallImagesAtTheirNativeSize() throws {
        let regionCapture = try makeImage(width: 800, height: 600)

        let encoded = try XCTUnwrap(ImageEncoder.encodeForModel(regionCapture))

        XCTAssertEqual(try decodedSize(encoded.data), CGSize(width: 800, height: 600))
    }

    /// JPEG has no alpha: a transparent clipboard PNG (black text on nothing) must not turn black.
    func test_encode_putsTransparentImagesOnAWhiteBackground() throws {
        for size in [40, 3000] { // native size, and the downscaled path
            let transparent = try makeImage(width: size, height: size, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0))

            let encoded = try XCTUnwrap(ImageEncoder.encodeForModel(transparent))

            let pixel = try centerPixel(encoded.data)
            XCTAssertGreaterThan(pixel.red, 240, "\(size) px")
            XCTAssertGreaterThan(pixel.green, 240, "\(size) px")
            XCTAssertGreaterThan(pixel.blue, 240, "\(size) px")
        }
    }

    private func centerPixel(_ data: Data) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        return (rgba[0], rgba[1], rgba[2])
    }

    private func makeImage(
        width: Int, height: Int, color: CGColor = CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    ) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func decodedSize(_ data: Data) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }
}
