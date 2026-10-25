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
