import Foundation
import Vision

/// What is in a photo, on the device (Vision's image classifier), in English.
public struct VisionLabeler: PhotoLabeler {
    public init() {}

    public func labels(for url: URL) -> [String] {
        let request = VNClassifyImageRequest()
        guard (try? VNImageRequestHandler(url: url).perform([request])) != nil,
              let observations = request.results else { return [] }
        return observations
            .filter { $0.confidence >= 0.3 && !Self.generic.contains($0.identifier) }
            .prefix(6)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    static let generic: Set<String> = ["outdoor", "indoor", "structure", "material", "textile", "liquid", "water_body"]

}
