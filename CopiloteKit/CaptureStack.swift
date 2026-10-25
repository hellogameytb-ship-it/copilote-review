import Foundation

/// A screenshot ready to be sent to the model.
public struct CapturedImage: Equatable, Sendable {
    public let data: Data
    public let mediaType: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(data: Data, mediaType: String, pixelWidth: Int, pixelHeight: Int) {
        self.data = data
        self.mediaType = mediaType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Screenshots accumulated (⌘⇧S / ⌘⇧A) until they are sent together (⌘⇧↩).
public struct CaptureStack: Sendable {
    public enum PushResult: Equatable, Sendable {
        case added
        case full
    }

    /// Above 20 images in one request the API applies a stricter per-image size limit.
    public static let defaultCapacity = 20

    public let capacity: Int
    public private(set) var images: [CapturedImage] = []

    public init(capacity: Int = CaptureStack.defaultCapacity) {
        self.capacity = capacity
    }

    public var isEmpty: Bool { images.isEmpty }

    /// Counter shown in the overlay header.
    public var summary: String {
        switch images.count {
        case 0: return "No screenshots"
        case 1: return "1 screenshot"
        case let n: return "\(n) screenshots"
        }
    }

    @discardableResult
    public mutating func push(_ image: CapturedImage) -> PushResult {
        guard images.count < capacity else { return .full }
        images.append(image)
        return .added
    }

    /// Puts captures back in front (after a failed send), keeping their order.
    /// Returns how many captures no longer fit (the most recent ones are dropped).
    @discardableResult
    public mutating func restore(_ restored: [CapturedImage]) -> Int {
        let all = restored + images
        images = Array(all.prefix(capacity))
        return all.count - images.count
    }

    public mutating func remove(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
    }

    public mutating func move(from index: Int, to destination: Int) {
        guard images.indices.contains(index), images.indices.contains(destination), index != destination else { return }
        let image = images.remove(at: index)
        images.insert(image, at: destination)
    }

    /// Returns every capture, oldest first, and empties the stack.
    public mutating func drain() -> [CapturedImage] {
        defer { images.removeAll() }
        return images
    }
}
