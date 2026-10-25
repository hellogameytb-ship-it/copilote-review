import Foundation
import ImageIO

public struct Coordinate: Hashable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// What a photo says about itself (EXIF through ImageIO): the day it was taken and where.
public struct PhotoMetadata: Equatable, Sendable {
    public let taken: CalendarDay?
    public let coordinate: Coordinate?
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        self.init(source: source)
    }

    public init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        self.init(source: source)
    }

    private init?(source: CGImageSource) {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let stamp = exif?[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        taken = stamp.flatMap(Self.day(fromEXIF:))
        coordinate = (properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]).flatMap(Self.coordinate(fromGPS:))
    }

    /// "2026:07:12 18:42:05": the local day of the camera, which is what people remember.
    private static func day(fromEXIF stamp: String) -> CalendarDay? {
        let date = stamp.prefix(10).split(separator: ":").compactMap { Int($0) }
        guard date.count == 3, date[0] > 1900, (1...12).contains(date[1]), (1...31).contains(date[2]) else { return nil }
        return .day(date[0], date[1], date[2])
    }

    private static func coordinate(fromGPS gps: [CFString: Any]) -> Coordinate? {
        guard let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double,
              latitude != 0 || longitude != 0 else { return nil }
        let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S"
        let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W"
        return Coordinate(latitude: south ? -latitude : latitude, longitude: west ? -longitude : longitude)
    }
}
