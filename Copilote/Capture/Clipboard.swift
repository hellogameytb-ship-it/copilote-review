import AppKit
import UniformTypeIdentifiers

enum ClipboardContent {
    case text(String)
    case image(CGImage)
    case unsupportedFile
    case empty
}

/// ⌘⇧V: text and code are sent as text, images (or a copied image file) as an image.
enum Clipboard {
    static let maxTextFileBytes = 200_000

    static func read(_ pasteboard: NSPasteboard = .general) -> ClipboardContent {
        // A file copied in Finder also carries its name as text and its icon as an image:
        // look at file URLs first so neither is sent by mistake.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            if type?.conforms(to: .image) == true || type?.conforms(to: .pdf) == true,
               let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return .image(image)
            }
            // Source files, notes, JSON…: sent as text when small enough to be a question.
            if type?.conforms(to: .text) == true,
               let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maxTextFileBytes,
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return .text(text)
            }
            return .unsupportedFile
        }
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        if let image = NSImage(pasteboard: pasteboard),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return .image(cgImage)
        }
        return .empty
    }

    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Immutable image bytes captured only by the composer's explicit Paste gesture.
struct ComposerImagePaste: Sendable {
    let images: [Data]
    let skipped: Int
}

extension Clipboard {
    /// File URLs outrank Finder's text/icon representations; real images outrank accompanying text.
    /// nil delegates ordinary text/RTF pasting to AppKit. Text URLs are never fetched.
    static func composerImages(from board: NSPasteboard) -> ComposerImagePaste? {
        let items = board.pasteboardItems ?? []
        let files = items.compactMap { item -> URL? in
            guard let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL else { return nil }
            return url
        }
        var images: [Data] = []
        var skipped = 0
        var bytes = 0
        let itemLimit = 20, fileLimit = 32 * 1024 * 1024, totalLimit = 64 * 1024 * 1024
        func accept(_ data: Data?) {
            guard images.count < itemLimit, let data, !data.isEmpty,
                  data.count <= fileLimit, bytes + data.count <= totalLimit else { skipped += 1; return }
            images.append(data); bytes += data.count
        }
        if !files.isEmpty {
            for url in files {
                guard images.count < itemLimit,
                      let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true, values.contentType?.conforms(to: .image) == true,
                      let size = values.fileSize, size <= fileLimit, bytes + size <= totalLimit else { skipped += 1; continue }
                accept(try? Data(contentsOf: url))
            }
            return ComposerImagePaste(images: images, skipped: skipped)
        }
        var hasImage = false
        for item in items {
            guard let type = [NSPasteboard.PasteboardType.png, .tiff].first(where: { item.types.contains($0) }) else { continue }
            hasImage = true
            if images.count >= itemLimit { skipped += 1; continue }
            accept(item.data(forType: type))
        }
        return hasImage ? ComposerImagePaste(images: images, skipped: skipped) : nil
    }
}
