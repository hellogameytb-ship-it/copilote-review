import Foundation
import NaturalLanguage

/// Vectors on the device: Apple's multilingual contextual model for Latin scripts (French and
/// English in one space), averaged over tokens. Weak on short conversational questions
/// (measured): search ranks it below words, periods and kinds.
public final class ContextualEmbedder: TextEmbedder, @unchecked Sendable {
    public let identifier: String
    private let embedding: NLContextualEmbedding
    private let lock = NSLock()

    /// nil when the model is missing; `prepare()` downloads it once (system asset, not a search).
    public init?() {
        guard let embedding = NLContextualEmbedding(script: .latin), embedding.hasAvailableAssets,
              (try? embedding.load()) != nil else { return nil }
        self.embedding = embedding
        identifier = "nl-contextual-latin-\(embedding.revision)-\(embedding.dimension)"
    }

    /// Asks the system for the model's assets if needed, then loads it.
    public static func prepare() async -> ContextualEmbedder? {
        if let ready = ContextualEmbedder() { return ready }
        guard let embedding = NLContextualEmbedding(script: .latin) else { return nil }
        _ = try? await embedding.requestAssets()
        return ContextualEmbedder()
    }

    public func vector(for text: String) -> [Float]? {
        lock.withLock {
            guard !text.isEmpty, let result = try? embedding.embeddingResult(for: text, language: nil) else { return nil }
            var sum = [Double](repeating: 0, count: embedding.dimension)
            var count = 0
            result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                for index in 0..<min(vector.count, sum.count) { sum[index] += vector[index] }
                count += 1
                return true
            }
            guard count > 0 else { return nil }
            return sum.map { Float($0 / Double(count)) }
        }
    }
}

/// Search without vectors (no model on this Mac).
public struct NoEmbedder: TextEmbedder {
    public let identifier = "none"
    public init() {}
    public func vector(for text: String) -> [Float]? { nil }
}
