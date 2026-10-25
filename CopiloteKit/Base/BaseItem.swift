import Foundation

/// What a piece of the base is about; decides how its fiche looks.
public enum BaseKind: String, CaseIterable, Codable, Sendable {
    case project = "projet"
    case trip = "voyage"
    case photo
    case cv
    case bio
    case note
    case reference = "référence"
    /// The user's own opinions (avis.md): the only source of an opinion answer.
    case opinion = "avis"
}

/// One searchable piece of the base: a fiche's summary, one of its sections, a CV entry, a photo.
public struct BaseItem: Hashable, Sendable, Codable {
    /// "<source>#<anchor>", stable across reindexing.
    public var id: String
    public var kind: BaseKind
    /// Path relative to the base folder (or absolute, for photos outside it).
    public var source: String
    /// The fiche's name: project name, trip place, note title.
    public var title: String
    /// nil for a fiche's summary; "Expériences › Stage…" for a CV entry.
    public var section: String?
    /// Plain text, what search reads.
    public var text: String
    public var dates: DateSpan?
    public var place: String?
    /// The fiche's frontmatter (pitch, stack, liens, captures, photos…) and, for photos, what
    /// the indexer read (path, labels).
    public var fields: [String: FrontmatterValue]

    public init(
        id: String, kind: BaseKind, source: String, title: String, section: String? = nil, text: String,
        dates: DateSpan? = nil, place: String? = nil, fields: [String: FrontmatterValue] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.section = section
        self.text = text
        self.dates = dates
        self.place = place
        self.fields = fields
    }

    /// "Revisio › Chiffres", or the title alone for a fiche's summary.
    public var label: String {
        section.map { "\(title) › \($0)" } ?? title
    }
}

extension String {
    /// "Le problème" → "le-probleme".
    var slug: String {
        let folded = folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        var slug = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                slug.unicodeScalars.append(scalar)
            } else if !slug.hasSuffix("-"), !slug.isEmpty {
                slug += "-"
            }
        }
        return slug.hasSuffix("-") ? String(slug.dropLast()) : slug
    }
}
