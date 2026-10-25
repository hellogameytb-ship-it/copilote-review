import Foundation

/// Cuts a Markdown file of the base into items: the fiche's summary (frontmatter + intro), then
/// one item per `##` section, or per `###` entry when a section has some (a CV is cut by
/// experience). Comments (`<!-- -->`) are the templates' instructions and are dropped.
public enum BaseChunker {
    public static func items(markdown: String, path: String, today: CalendarDay = .today(), kind override: BaseKind? = nil) -> [BaseItem] {
        guard let kind = override ?? kind(forPath: path) else { return [] }
        let parsed = Frontmatter(markdown: markdown)
        let fields = parsed.fields
        let body = withoutComments(parsed.body)
        let blocks = sections(of: body)
        let title = fields["nom"]?.text ?? fields["lieu"]?.text ?? fields["titre"]?.text
            ?? blocks.h1 ?? fileTitle(path)
        let ficheDates = DateSpan(start: fields["debut"]?.text ?? fields["date"]?.text, end: fields["fin"]?.text)

        var items: [BaseItem] = []
        let summary = [fields["pitch"]?.text, fields["stack"].map { "Stack : " + $0.items.joined(separator: ", ") },
                       fields["lieu"]?.text, blocks.intro]
            .compactMap { $0 }.filter { !$0.isEmpty }
        if !summary.isEmpty, kind == .project || kind == .trip || !blocks.intro.isEmpty {
            items.append(BaseItem(
                id: "\(path)#fiche", kind: kind, source: path, title: title,
                text: ([title] + summary).joined(separator: "\n"),
                dates: ficheDates, place: fields["lieu"]?.text, fields: fields
            ))
        }
        for block in blocks.sections where !block.text.isEmpty {
            items.append(BaseItem(
                id: "\(path)#\(block.heading.slug)", kind: kind, source: path, title: title, section: block.heading,
                text: [title, block.heading, block.text].joined(separator: "\n"),
                dates: CalendarDay(iso: block.heading).map { DateSpan($0, $0) }
                    ?? (kind == .cv ? DateSpan(text: block.heading, today: today) : ficheDates),
                place: fields["lieu"]?.text, fields: fields
            ))
        }
        return items
    }

    /// nil for files that are not indexed (templates start with `_`, root files other than
    /// `cv.md` and `bio.md`).
    public static func kind(forPath path: String) -> BaseKind? {
        let parts = path.split(separator: "/").map(String.init)
        guard let file = parts.last, !file.hasPrefix("_"), !file.hasPrefix(".") else { return nil }
        if parts.count == 1 {
            switch file.lowercased() {
            case "cv.md": return .cv
            case "bio.md": return .bio
            case BaseScaffold.opinionsFile: return .opinion
            default: return nil
            }
        }
        switch parts[0] {
        case "projets": return .project
        case "voyages": return .trip
        case "notes": return .note
        case "reference": return .reference
        default: return nil
        }
    }

    // MARK: Parsing

    private struct Section {
        let heading: String
        let text: String
    }

    private static func sections(of body: String) -> (h1: String?, intro: String, sections: [Section]) {
        var h1: String?
        var intro: [String] = []
        var sections: [Section] = []
        var parent: String?
        var heading: String?
        var lines: [String] = []
        var parentHasEntries = false

        func flush() {
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if let heading {
                sections.append(Section(heading: heading, text: text))
            } else {
                intro.append(text)
            }
            lines = []
        }

        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("# ") {
                flush()
                h1 = h1 ?? String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                heading = nil
            } else if line.hasPrefix("## ") {
                flush()
                parent = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                parentHasEntries = false
                heading = parent
            } else if line.hasPrefix("### ") {
                flush()
                // A section cut into entries keeps only its entries (its own lead-in is short).
                if !parentHasEntries, let last = sections.last, last.heading == parent, last.text.isEmpty {
                    sections.removeLast()
                }
                parentHasEntries = true
                let entry = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                heading = parent.map { "\($0) › \(entry)" } ?? entry
            } else {
                lines.append(line)
            }
        }
        flush()
        let introText = intro.filter { !$0.isEmpty }.joined(separator: "\n")
        return (h1, introText, sections)
    }

    private static func withoutComments(_ text: String) -> String {
        text.replacing(/<!--[\s\S]*?-->/, with: "")
    }

    private static func fileTitle(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return ((name as NSString).deletingPathExtension).replacingOccurrences(of: "-", with: " ")
    }
}
