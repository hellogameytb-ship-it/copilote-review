import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A downscaled JPEG of an image file, oriented (the grid's thumbnails, the captions' upload).
enum ImageThumbnail {
    static func jpeg(of url: URL, maxPixelSize: Int, quality: Double) -> (data: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? (data as Data, image.width, image.height) : nil
    }
}
