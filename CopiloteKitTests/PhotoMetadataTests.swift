import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CopiloteKit

final class PhotoMetadataTests: XCTestCase {
    func test_readsTheDayTakenAndTheGPSPosition_withItsHemisphere() throws {
        let data = try jpeg(exif: [kCGImagePropertyExifDateTimeOriginal as String: "2026:07:12 18:42:05"], gps: [
            kCGImagePropertyGPSLatitude as String: 38.9637, kCGImagePropertyGPSLatitudeRef as String: "N",
            kCGImagePropertyGPSLongitude as String: 9.4176, kCGImagePropertyGPSLongitudeRef as String: "W",
        ])

        let metadata = try XCTUnwrap(PhotoMetadata(data: data))

        XCTAssertEqual(metadata.taken, .day(2026, 7, 12))
        XCTAssertEqual(try XCTUnwrap(metadata.coordinate?.latitude), 38.9637, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(metadata.coordinate?.longitude), -9.4176, accuracy: 1e-4)
        XCTAssertEqual(metadata.pixelWidth, 8)
    }

    func test_aPhotoWithoutEXIFHasNeitherDayNorPlace() throws {
        let metadata = try XCTUnwrap(PhotoMetadata(data: try jpeg(exif: nil, gps: nil)))

        XCTAssertNil(metadata.taken)
        XCTAssertNil(metadata.coordinate)
    }

    func test_aZeroPositionIsNoPosition() throws {
        // Some cameras write 0/0 when they had no fix.
        let data = try jpeg(exif: nil, gps: [
            kCGImagePropertyGPSLatitude as String: 0.0, kCGImagePropertyGPSLatitudeRef as String: "N",
            kCGImagePropertyGPSLongitude as String: 0.0, kCGImagePropertyGPSLongitudeRef as String: "E",
        ])

        XCTAssertNil(try XCTUnwrap(PhotoMetadata(data: data)).coordinate)
    }

    func test_somethingThatIsNotAnImageGivesNothing() {
        XCTAssertNil(PhotoMetadata(data: Data("pas une image".utf8)))
    }

    private func jpeg(exif: [String: Any]?, gps: [String: Any]?) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [String: Any] = [:]
        if let exif { properties[kCGImagePropertyExifDictionary as String] = exif }
        if let gps { properties[kCGImagePropertyGPSDictionary as String] = gps }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

final class PlaceNamesTests: XCTestCase {
    /// Apple keeps some cities in their own language even in French: the usual French name wins.
    func test_citiesGetTheirUsualFrenchName() {
        XCTAssertEqual(PlaceNames.french(city: "Lisboa", country: "Portugal"), "Lisbonne, Portugal")
        XCTAssertEqual(PlaceNames.french(city: "München", country: "Allemagne"), "Munich, Allemagne")
        XCTAssertEqual(PlaceNames.french(city: "Ericeira", country: "Portugal"), "Ericeira, Portugal")
        XCTAssertEqual(PlaceNames.french(city: nil, country: "Japon"), "Japon")
        XCTAssertNil(PlaceNames.french(city: nil, country: nil))
    }
}
