import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares screenshots for the Messages API: small enough to upload fast,
/// large enough for on-screen text to stay legible.
public enum ImageEncoder {
    /// About half the width of a Retina capture: 14 pt text stays crisp, and a dense full-screen
    /// capture weighs ~0.5 MB instead of ~0.9 MB at 2000 px / 0.85 (upload and image tokens
    /// are most of the latency before the first word). Also under the API's 2000 px limit
    /// for many-image requests.
    public static let maxLongEdge = 1600
    public static let jpegQuality = 0.75

    public static func encodeForModel(_ image: CGImage) -> CapturedImage? {
        let scaled = downscaled(image, maxLongEdge: maxLongEdge) ?? image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, scaled, [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return CapturedImage(
            data: data as Data,
            mediaType: "image/jpeg",
            pixelWidth: scaled.width,
            pixelHeight: scaled.height
        )
    }

    /// Returns nil when the image already fits.
    private static func downscaled(_ image: CGImage, maxLongEdge: Int) -> CGImage? {
        let longEdge = max(image.width, image.height)
        guard longEdge > maxLongEdge else { return nil }
        let scale = Double(maxLongEdge) / Double(longEdge)
        let width = Int((Double(image.width) * scale).rounded())
        let height = Int((Double(image.height) * scale).rounded())
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        // JPEG has no alpha: transparent pixels must land on white, not on the zeroed (black) buffer.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
