import Foundation

/// Optional, off by default: a one-sentence caption per photo through the active provider, in
/// the offline indexing batch. The photo leaves the Mac (downscaled to 1024 px) only then.
public struct LLMPhotoCaptioner: PhotoCaptioner {
    private let provider: any LLMProvider

    public init(provider: any LLMProvider) {
        self.provider = provider
    }

    public func caption(for url: URL) async throws -> String {
        guard let jpeg = ImageThumbnail.jpeg(of: url, maxPixelSize: 1024, quality: 0.7) else { throw CocoaError(.fileReadCorruptFile) }
        let photo = CapturedImage(data: jpeg.data, mediaType: "image/jpeg", pixelWidth: jpeg.width, pixelHeight: jpeg.height)
        let caption = try await provider.complete(
            system: "Describe personal photos in one short English sentence. Never invent a location or name.",
            prompt: "Describe this photo in one sentence of at most 12 words.", images: [photo]
        )
        return caption.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
