import Foundation

/// One piece of context the user can switch on or off before asking: a phrase of the
/// transcript, a capture, an extract of the base.
public struct ContextItem: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case line
        case capture
        case extract
    }

    public let id: String
    public let kind: Kind
    /// What the switch shows: "Eux : …", "Capture 2", "Revisio › Chiffres (projets/revisio.md)".
    public let label: String
    public var isIncluded: Bool
}

/// What goes with an action (Répondre, Que dire, Notes): everything by default, minus what the
/// user switched off. Choices survive the arrival of new phrases.
public struct AssistContext: Equatable, Sendable {
    public private(set) var items: [ContextItem] = []
    private var lines: [String: TranscriptLine] = [:]
    private var captures: [String: CapturedImage] = [:]
    private var extracts: [String: BaseSnippet] = [:]

    public init(lines: [TranscriptLine] = [], captures: [CapturedImage] = [], extracts: [BaseSnippet] = []) {
        refresh(lines: lines, captures: captures, extracts: extracts)
    }

    public mutating func refresh(lines: [TranscriptLine], captures: [CapturedImage], extracts: [BaseSnippet]) {
        let excluded = Set(items.filter { !$0.isIncluded }.map(\.id))
        var items: [ContextItem] = []
        self.lines = [:]
        self.captures = [:]
        self.extracts = [:]
        for line in lines {
            let id = "line-\(line.speaker.rawValue)-\(line.start)"
            self.lines[id] = line
            items.append(ContextItem(id: id, kind: .line, label: line.labeled, isIncluded: !excluded.contains(id)))
        }
        var occurrences: [Int: Int] = [:]
        for (index, capture) in captures.enumerated() {
            // By content: a switch follows its capture when the stack changes around it.
            let hash = capture.data.hashValue
            let occurrence = occurrences[hash, default: 0]
            occurrences[hash] = occurrence + 1
            let id = "capture-\(hash)-\(occurrence)"
            self.captures[id] = capture
            items.append(ContextItem(id: id, kind: .capture, label: "Screenshot \(index + 1)", isIncluded: !excluded.contains(id)))
        }
        for extract in extracts {
            let id = "extract-\(extract.source)"
            self.extracts[id] = extract
            items.append(ContextItem(id: id, kind: .extract, label: extract.source, isIncluded: !excluded.contains(id)))
        }
        self.items = items
    }

    /// Replace only retrieved extracts; keep click-time switches for every other item.
    public mutating func replaceExtracts(with fresh: [BaseSnippet]) {
        let excluded = Set(items.filter { !$0.isIncluded }.map(\.id))
        items.removeAll { $0.kind == .extract }
        extracts = [:]
        for extract in fresh {
            let id = "extract-\(extract.source)"
            extracts[id] = extract
            items.append(ContextItem(id: id, kind: .extract, label: extract.source, isIncluded: !excluded.contains(id)))
        }
    }

    public mutating func toggle(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isIncluded.toggle()
    }

    public var includedLines: [TranscriptLine] { included(.line).compactMap { lines[$0.id] } }
    /// What the user switched off, to leave it out wherever it appears.
    public var excludedLineTexts: Set<String> {
        Set(items.filter { $0.kind == .line && !$0.isIncluded }.compactMap { lines[$0.id]?.text })
    }
    public var includedCaptures: [CapturedImage] { included(.capture).compactMap { captures[$0.id] } }
    public var includedExtracts: [BaseSnippet] { included(.extract).compactMap { extracts[$0.id] } }

    private func included(_ kind: ContextItem.Kind) -> [ContextItem] {
        items.filter { $0.kind == kind && $0.isIncluded }
    }
}
