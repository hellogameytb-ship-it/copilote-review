import Foundation

/// A contiguous passage in a permitted document. Never join actions or outcomes across stories.
struct BehavioralEpisode {
    let source: String
    let passage: String
    let context: BaseText
    let quality: Int
    let position: Int

    private static func pattern(_ value: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: value)
    }
    private static let action = pattern(#"\b(?:i|we)\s+(?:[a-z]{2,}ed|built|wrote|made|met|found|ran|led|took|set|split|chose|put|rewrote|fixed|brought|taught|sent|cut|tried)\b|\b(?:j ai|nous avons|on a)\s+(?:[a-z]{2,}(?:e|i|u)|mis|pris|fait|choisi)\b"#)
    private static let weakAction = pattern(#"\b(?:i|we)\s+(?:wanted|needed|hoped|planned|expected|faced|imagined|considered|supposed|believed|wished)\b|\b(?:j ai|nous avons|on a) (?:voulu|espere|envisage|imagine|ete)\b"#)
    private static let difficulty = pattern(#"\b(?:outage|incident|setback|failed|failure|broke|blocked|broken|unavailable|lost|couldn t|could not|was unable|kept failing|ran out|deadline|pressure|conflict|disagreement|missing|too slow|too long|instead of|panne|bloqu[a-z]*|echou[a-z]*|echec|tombe[a-z]*|desaccord|pression|impossible|ne (?:pouvai[a-z]*|fonctionnait) pas|didn t (?:work|pass)|couldn t)\b"#)
    private static let disruption = pattern(#"\b(?:failed|broke|outage|interrupted|stopped|crashed|blocked|couldn t|could not|tomb[a-z]*|panne|echou[a-z]*|bloqu[a-z]*|ne pouvait pas|ne pouvaient pas|ne fonctionnait plus|indisponible|conflit|disagreement)\b"#)
    private static let outcome = pattern(#"\b(?:as a result|which allowed|resulted in|so that we could|restored|recovered|prevented|reduced|saved|resumed|succeeded|passed|cut .* by|no longer|was able to|were able to|a permis|a sauve|a reduit|a repris|retabli|resultat|avons pu|ai pu)\b"#)
    private static let unverified = pattern(#"\b(?:a confirmer|a verifier|a valider|a eviter|ne jamais dire|do not use|illustrative example|to (?:be )?(?:confirm(?:ed)?|verify)|unverified|unconfirmed|not verified|fictional|hypothetical|hypothetique|ficti[fv][a-z]*|invented example|sample answer|example answer|exemple invente|do not (?:say|claim)|ne pas (?:dire|affirmer)|not my experience|pas mon experience|placeholder)\b"#)
    private static let speculative = pattern(#"\b(?:i would|we would|i could|we could|if i|if we|should (?:i|we)|i might|we might|i plan to|i will|we will|j aurais|je pourrais|je devrais|je vais|si je|si nous|a faire|todo)\b"#)
    private static let starField = pattern(#"^(?:situation|task|tache|action|actions|result|results|resultat|resultats)\b"#)
    private static let components = pattern(#"(?<=[.!?])\s+|\n+"#)

    private static func matches(_ pattern: NSRegularExpression, _ text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
    private static func normalized(_ text: String) -> String {
        BaseText.tokens(of: text).joined(separator: " ")
    }

    /// Raw vault notes are indexed as numbered extracts. A caution at the end of one
    /// extract still qualifies its continuation, until a new headed section starts.
    static func catalog(_ items: [BaseItem]) -> [Self] {
        var all = items.filter { $0.kind != .note }.flatMap(passages)
        let notes = Dictionary(grouping: items.filter { $0.kind == .note }, by: \.source)
        for file in notes.values {
            var caution = false
            func ordinal(_ item: BaseItem) -> Int {
                Int(item.id.split(separator: "#").last ?? "") ?? 0
            }
            for item in file.sorted(by: { ordinal($0) < ordinal($1) }) {
                let body = BaseContext.body(of: item).trimmingCharacters(in: .whitespacesAndNewlines)
                if let first = body.components(separatedBy: .newlines).first,
                   first.hasPrefix("#") || first.hasPrefix("**") {
                    let heading = normalized(first)
                    if !matches(starField, heading) { caution = false }
                }
                if matches(unverified, normalized(item.label + " " + body)) { caution = true }
                if !caution { all += passages(in: item) }
            }
        }
        return all
    }

    static func passages(in item: BaseItem) -> [Self] {
        let path = Set(BaseText.tokens(of: item.source))
        let interviewNote = item.kind == .note && !path.isDisjoint(with: ["interview", "entretiens", "entretien", "interviews"])
        guard item.kind == .cv || item.kind == .project || interviewNote,
              path.isDisjoint(with: ["archive", "archives"]), VaultPolicy.allows(path: item.source),
              !VaultPolicy.containsSecrets(item.text) else { return [] }
        let body = BaseContext.body(of: item)
        // A caution in a heading can qualify a quoted answer several lines below.
        guard !matches(unverified, normalized(item.label + "\n" + body)) else { return [] }
        let source = "\(item.label) (\(item.source))"
        let section = normalized(item.section ?? "")
        let curated = section.contains("histoires") || section.contains("case study")
        var result: [Self] = []
        var block: [String] = []

        func finishBlock() {
            defer { block.removeAll(keepingCapacity: true) }
            guard !block.isEmpty else { return }
            let sentences = block.flatMap { line in
                components.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "\n")
                    .components(separatedBy: "\n").filter { !$0.isEmpty }
            }
            let folded = sentences.map(normalized)
            guard !folded.contains(where: { matches(speculative, $0) }) else { return }
            for i in sentences.indices {
                let concrete = weakAction.stringByReplacingMatches(in: folded[i], range: NSRange(folded[i].startIndex..., in: folded[i]), withTemplate: "")
                let personal = matches(action, concrete)
                guard personal || (curated && item.kind == .project && matches(outcome, folded[i])) else { continue }
                var best: Self?
                for first in max(0, i - 3)...i {
                    for last in i...min(sentences.count - 1, i + 3) {
                        let text = sentences[first...last].joined(separator: " ")
                        guard text.count <= 1000 else { continue }
                        let window = folded[first...last].joined(separator: " ")
                        guard matches(difficulty, window) else { continue }
                        let hasOutcome = matches(outcome, window)
                        let priorIncident = folded[first..<i].contains { matches(disruption, $0) }
                        let laterOutcome = folded[(i + 1)..<(last + 1)].contains { matches(outcome, $0) }
                        let grade = (personal ? 4 : 1) + (hasOutcome ? 6 : 0)
                            + (priorIncident ? 3 : 0) + (laterOutcome ? 2 : 0)
                        if let best, best.quality > grade || (best.quality == grade && best.passage.count <= text.count) { continue }
                        best = Self(source: source, passage: text, context: BaseText(section + " " + window),
                                    quality: grade, position: result.count)
                    }
                }
                if let best { result.append(best) }
            }
        }
        var structured = false
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // A quoted blank line is still part of the same quotation.
            if line == ">" { continue }
            let field = line.trimmingCharacters(in: CharacterSet(charactersIn: "-*># "))
            if let colon = field.firstIndex(of: ":"), matches(starField, normalized(String(field[..<colon]))),
               field[..<colon].count < 18 {
                if normalized(String(field[..<colon])).hasPrefix("situation") { finishBlock() }
                structured = true
                block.append(line)
                continue
            }
            if line.isEmpty && structured { continue }
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("**") || line.hasPrefix("|") {
                structured = false
                finishBlock()
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { finishBlock() }
            structured = false
            block.append(line)
        }
        finishBlock()
        return result
    }

    static func best(for intent: QueryIntent, in episodes: [Self], namedProjects: [String] = []) -> [BaseSnippet] {
        let specific = intent.storyTerms.filter { $0.word != "histoires" }
        var winner: Self?
        var top = Int.min
        for episode in episodes {
            if !namedProjects.isEmpty {
                let record = " " + normalized(episode.source + " " + episode.passage) + " "
                guard namedProjects.contains(where: { record.contains(" " + $0 + " ") }) else { continue }
            }
            guard specific.isEmpty || specific.contains(where: { $0.matches(episode.context) }) else { continue }
            let relevance = intent.terms.filter { $0.matches(episode.context) }.count
            let score = episode.quality * 10 + min(9, relevance)
            let firstInSourceOrder = winner.map { (episode.source, episode.position) < ($0.source, $0.position) } ?? true
            if score > top || (score == top && firstInSourceOrder) {
                winner = episode
                top = score
            }
        }
        return winner.map { [BaseSnippet(source: $0.source, text: $0.passage)] } ?? []
    }
}
