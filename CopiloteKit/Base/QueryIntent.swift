import Foundation

/// What a question asks of the base, decided on the device in well under a millisecond (no LLM
/// on the hot path): is it about the user, which kinds of fiche, which period, which words.
/// Cue words first; the small local classifier (`PersonalClassifier`) for phrasings they miss.
public struct QueryIntent: Equatable, Sendable {
    public let question: String
    public let isPersonal: Bool
    /// Empty: any kind.
    public let kinds: Set<BaseKind>
    /// The kinds named by cue words alone (not guessed by the classifier or from a period).
    public let cueKinds: Set<BaseKind>
    /// Addressed to the user ("tu", "ton", "you"…).
    public let isAddressed: Bool
    /// "Un projet qui t'a mis sous pression", "un échec", "un conflit": a story is expected.
    public let isBehavioral: Bool
    public let period: DateSpan?
    /// Content words (cue words, stop words and the period removed), then hints.
    public let terms: [QueryTerm]

    public init(question: String, today: CalendarDay = .today()) {
        self.question = question
        let tokens = BaseText.tokens(of: question)
        var consumed = Set<Int>()

        var kinds = Set<BaseKind>()
        var hints: [QueryTerm] = []
        var behavioral = false
        for group in Self.cueGroups {
            let positions = group.cues.flatMap { $0.positions(in: tokens) }
            guard !positions.isEmpty else { continue }
            consumed.formUnion(positions)
            kinds.formUnion(group.kinds)
            if let hint = group.hint, !hints.contains(hint) { hints.append(hint) }
            if Self.storyGroups.contains(where: { $0.hint == group.hint }) { behavioral = true }
        }
        cueKinds = kinds
        isBehavioral = behavioral
        let (period, periodPositions) = PeriodParser.period(in: tokens, today: today)
        consumed.formUnion(periodPositions)

        let addressed = tokens.contains { Self.secondPerson.contains($0) || ["mon", "ma", "mes", "notre", "nos", "my", "our"].contains($0) }
        isAddressed = addressed
        var personal = addressed && (!kinds.isEmpty || period != nil)
        if addressed, kinds.isEmpty, let guess = PersonalClassifier.shared.kind(of: tokens) {
            kinds = [guess]
            personal = true
        }
        if kinds.isEmpty, period != nil { kinds = [.trip, .photo] }
        if kinds.contains(.trip) || kinds.contains(.photo) { kinds.formUnion([.trip, .photo]) }

        let content = tokens.enumerated()
            .filter { !consumed.contains($0.offset) && !Self.stopWords.contains($0.element) && $0.element.count > 1 }
            .map(\.element)
        var words: [String] = []
        for word in content where !words.contains(word) { words.append(word) }

        self.isPersonal = personal
        self.kinds = kinds
        self.period = period
        self.terms = hints + words.map { QueryTerm(word: $0) }
    }

    // MARK: Cue words

    struct Cue {
        let words: [String]

        init(_ phrase: String) {
            words = phrase.split(separator: " ").map(String.init)
        }

        /// Token positions of each occurrence; a word ending in `*` matches by prefix.
        func positions(in tokens: [String]) -> [Int] {
            guard tokens.count >= words.count else { return [] }
            var found: [Int] = []
            for start in 0...(tokens.count - words.count) {
                let matches = words.enumerated().allSatisfy { offset, word in
                    word.hasSuffix("*") ? tokens[start + offset].hasPrefix(word.dropLast()) : tokens[start + offset] == word
                }
                if matches { found.append(contentsOf: start..<(start + words.count)) }
            }
            return found
        }
    }

    struct CueGroup {
        let kinds: Set<BaseKind>
        let cues: [Cue]
        let hint: QueryTerm?
    }

    /// Story questions, by theme: each finds its own story ("Histoires › Pression / deadline").
    static let storyGroups: [CueGroup] = [
        CueGroup(kinds: [.project], cues: ["sous pression", "pression", "deadline*", "stress*", "urgence", "pressure", "rush"].map(Cue.init),
                 hint: QueryTerm(word: "pression", alternatives: ["deadline", "stress", "urgence", "pressure"])),
        CueGroup(kinds: [.project], cues: ["echec*", "echoue*", "erreur*", "failure*", "failed", "mistake*"].map(Cue.init),
                 hint: QueryTerm(word: "echec", alternatives: ["erreur", "appris", "failure", "mistake"])),
        CueGroup(kinds: [.project], cues: ["conflit*", "desaccord*", "disagree*", "conflict*", "tension*"].map(Cue.init),
                 hint: QueryTerm(word: "conflit", alternatives: ["desaccord", "tension", "conflict", "disagree"])),
        CueGroup(kinds: [.project], cues: ["fierte", "fier", "fiere", "proud*", "reussite"].map(Cue.init),
                 hint: QueryTerm(word: "fierte", alternatives: ["fier", "reussite", "proud"])),
        CueGroup(kinds: [.project], cues: ["difficile", "challenge*", "defi*", "tell me about a time"].map(Cue.init),
                 hint: QueryTerm(word: "histoires", alternatives: ["pression", "deadline", "echec", "conflit", "desaccord", "fierte", "difficile"])),
    ]

    static let cueGroups: [CueGroup] = storyGroups + [
        CueGroup(kinds: [.trip], cues: [
            "vacances", "voyage*", "parti", "partie", "partis", "visite*", "etais ou", "ou etais", "etiez ou", "es alle*", "es parti*",
            "where did you go", "where were you", "trip*", "travel*", "vacation*", "holiday*",
        ].map(Cue.init), hint: nil),
        CueGroup(kinds: [.photo], cues: ["photo*", "pics", "picture*", "montre*", "show me"].map(Cue.init), hint: nil),
        CueGroup(kinds: [.project], cues: [
            "projet*", "app", "apps", "appli*", "application*", "project*", "side project*", "construit", "developpe*",
            "built", "building", "working on", "bosses sur", "travailles sur",
        ].map(Cue.init), hint: nil),
        CueGroup(kinds: [.cv], cues: [
            "codes en", "code en", "programmes en", "langage*", "techno*", "stack", "competence*", "skill*", "language*",
        ].map(Cue.init), hint: QueryTerm(word: "competences", alternatives: ["langages", "langues", "skills", "stack", "outils"])),
        CueGroup(kinds: [.cv], cues: [
            "etudes", "etudie*", "ecole", "fac", "universite", "diplome*", "master", "licence", "formation", "cursus",
            "studies", "study", "studying", "degree", "university", "college",
        ].map(Cue.init), hint: QueryTerm(word: "formation", alternatives: ["licence", "master", "universite", "etudes", "diplome"])),
        CueGroup(kinds: [.cv], cues: [
            "stage*", "experience*", "boulot", "job*", "travaille", "travaillais", "bosse", "bossais", "taf", "internship*",
            "worked", "parcours", "cv", "resume",
        ].map(Cue.init), hint: QueryTerm(word: "experiences", alternatives: ["stage", "poste", "job", "internship"])),
        CueGroup(kinds: [.bio], cues: [
            "viens d ou", "d ou tu viens", "d ou vous venez", "originaire*", "grandi", "where are you from", "presente toi",
            "presentez vous", "about yourself", "qui es tu", "parle moi de toi",
        ].map(Cue.init), hint: QueryTerm(word: "bref", alternatives: ["viens", "grandi", "originaire", "ne"])),
        CueGroup(kinds: [.bio], cues: [
            "temps libre", "loisir*", "passion*", "hobby", "hobbies", "en dehors des cours", "for fun", "free time",
        ].map(Cue.init), hint: QueryTerm(word: "interets", alternatives: ["loisirs", "passions", "hobbies"])),
    ]

    static let secondPerson: Set<String> = ["tu", "t", "ton", "ta", "tes", "toi", "te", "vous", "votre", "vos", "you", "your", "yours", "yourself"]

    static let stopWords: Set<String> = [
        "a", "ai", "alors", "as", "au", "aux", "avec", "avoir", "bien", "bon", "c", "ca", "ce", "cela", "ces", "cet", "cette", "chez",
        "comme", "comment", "d", "dans", "de", "deja", "des", "dis", "dit", "donc", "du", "elle", "en", "encore", "est", "et", "etait",
        "etais", "ete", "etre", "eu", "euh", "fais", "fait", "faire", "fois", "general", "genre", "hein", "il", "j", "je", "juste", "l",
        "la", "le", "les", "leur", "lui", "m", "ma", "mais", "me", "merci", "mes", "moi", "mon", "n", "ne", "non", "nous", "ok", "on",
        "ou", "oui", "par", "parle", "pas", "peu", "peut", "peux", "plus", "pour", "pourquoi", "puis", "qu", "quand", "que", "quel",
        "quelle", "quelles", "quels", "qui", "quoi", "raconte", "s", "sa", "sans", "se", "ses", "si", "sinon", "son", "sont", "sur",
        "t", "ta", "te", "tes", "toi", "ton", "tres", "tu", "un", "une", "vos", "votre", "vous", "vraiment", "y", "accord", "voila", "veux", "veut", "voulais", "aimerais",
        "an", "and", "any", "are", "at", "be", "been", "can", "could", "did", "do", "does", "for", "from", "go", "how", "i", "in",
        "is", "it", "last", "me", "my", "of", "on", "or", "our", "so", "some", "tell", "that", "the", "these", "this", "those", "to",
        "was", "we", "went", "were", "what", "when", "where", "which", "who", "why", "will", "with", "would", "you", "your", "about",
        // Interjections that open spoken questions.
        "genial", "super", "cool", "top", "parfait", "salut", "bonjour", "hello", "hey", "hi", "ouais", "bref", "tiens", "ecoute",
        "okay", "ah", "oh", "hum", "great", "nice", "so", "well",
    ]
}

/// "cet été", "l'été dernier", "en avril 2025", "l'an dernier", "à Noël"…
enum PeriodParser {
    static func period(in tokens: [String], today: CalendarDay) -> (DateSpan?, Set<Int>) {
        for (index, token) in tokens.enumerated() {
            if let season = Season(token) {
                let previous = index > 0 ? tokens[index - 1] : ""
                let next = index + 1 < tokens.count ? tokens[index + 1] : ""
                let last = ["dernier", "derniere"].contains(next) || previous == "last"
                var positions: Set<Int> = [index]
                if ["cet", "ce", "cette", "this", "last", "l", "le", "en", "pendant"].contains(previous) { positions.insert(index - 1) }
                if last, ["dernier", "derniere"].contains(next) { positions.insert(index + 1) }
                return (season.span(last: last, today: today), positions)
            }
            if ["noel", "christmas"].contains(token) {
                let year = today.month == 12 && today.day >= 20 ? today.year : today.year - 1
                return (DateSpan(.day(year, 12, 20), .day(year + 1, 1, 5)), [index])
            }
            if let month = months[token], !["mars", "mai", "march", "may"].contains(token) || index > 0 && ["en", "in", "de", "depuis"].contains(tokens[index - 1]) {
                var positions: Set<Int> = [index]
                var year = today.month >= month ? today.year : today.year - 1
                if index + 1 < tokens.count, let explicit = Int(tokens[index + 1]), (1900...2100).contains(explicit) {
                    year = explicit
                    positions.insert(index + 1)
                }
                return (DateSpan.month(month, of: year), positions)
            }
            if let year = Int(token), (1900...2100).contains(year), token.count == 4 {
                return (DateSpan(.day(year, 1, 1), .day(year, 12, 31)), [index])
            }
        }
        let joined = " " + tokens.joined(separator: " ") + " "
        if joined.contains(" l an dernier ") || joined.contains(" l annee derniere ") || joined.contains(" last year ") {
            return (DateSpan(.day(today.year - 1, 1, 1), .day(today.year - 1, 12, 31)), positions(of: ["an", "annee", "dernier", "derniere", "last", "year"], in: tokens))
        }
        if joined.contains(" cette annee ") || joined.contains(" this year ") {
            return (DateSpan(.day(today.year, 1, 1), today), positions(of: ["cette", "annee", "this", "year"], in: tokens))
        }
        return (nil, [])
    }

    /// Whole month names only ("se" or "de" are not months); "mars", "mai", "may" need "en" / "in" before them.
    static let months: [String: Int] = [
        "janvier": 1, "janv": 1, "january": 1, "fevrier": 2, "fevr": 2, "february": 2, "mars": 3, "march": 3,
        "avril": 4, "avr": 4, "april": 4, "mai": 5, "may": 5, "juin": 6, "june": 6, "juillet": 7, "juil": 7, "july": 7,
        "aout": 8, "august": 8, "septembre": 9, "sept": 9, "september": 9, "octobre": 10, "october": 10,
        "novembre": 11, "november": 11, "decembre": 12, "december": 12,
    ]

    private static func positions(of words: Set<String>, in tokens: [String]) -> Set<Int> {
        Set(tokens.indices.filter { words.contains(tokens[$0]) })
    }

    enum Season {
        case summer, autumn, winter, spring

        init?(_ token: String) {
            switch token {
            case "ete", "summer": self = .summer
            case "automne", "autumn", "fall": self = .autumn
            case "hiver", "winter": self = .winter
            case "printemps", "spring": self = .spring
            default: return nil
            }
        }

        func occurrence(startingIn year: Int) -> DateSpan {
            switch self {
            case .summer: return DateSpan(.day(year, 6, 1), .day(year, 8, 31))
            case .autumn: return DateSpan(.day(year, 9, 1), .day(year, 11, 30))
            case .winter: return DateSpan(.day(year, 12, 1), .day(year + 1, 2, CalendarDay.lastDay(ofMonth: 2, year: year + 1)))
            case .spring: return DateSpan(.day(year, 3, 1), .day(year, 5, 31))
            }
        }

        /// "cet été": the latest one that has started; "l'été dernier": the latest one that has ended.
        func span(last: Bool, today: CalendarDay) -> DateSpan {
            var year = today.year
            while true {
                let candidate = occurrence(startingIn: year)
                if last ? candidate.end < today : candidate.start <= today { return candidate }
                year -= 1
            }
        }
    }
}
