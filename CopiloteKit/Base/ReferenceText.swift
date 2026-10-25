import AppKit
import PDFKit

/// Text of the files dropped in `reference/` (PDF, DOCX, RTF, TXT, MD), cut into extracts.
public enum ReferenceText {
    static let extractLength = 700

    public static func read(_ url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
            return document.string ?? ""
        case "docx":
            return try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil).string
        case "rtf":
            return try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
        default:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// Paragraphs grouped into extracts of about 700 characters.
    public static func items(text: String, path: String, kind: BaseKind) -> [BaseItem] {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let title = name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var extracts: [String] = []
        var current = ""
        for paragraph in paragraphs {
            if !current.isEmpty, current.count + paragraph.count > extractLength {
                extracts.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + paragraph
        }
        if !current.isEmpty { extracts.append(current) }
        return extracts.enumerated().map { offset, extract in
            BaseItem(
                id: "\(path)#\(offset + 1)", kind: kind, source: path, title: title,
                section: extracts.count > 1 ? "Extrait \(offset + 1)" : nil, text: title + "\n" + extract
            )
        }
    }
}
