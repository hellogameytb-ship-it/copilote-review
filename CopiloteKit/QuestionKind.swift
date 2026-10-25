import Foundation

/// What kind of answer a question calls for (step 4b): each kind has its own format.
public enum QuestionKind: String, CaseIterable, Sendable {
    /// "Les ventes de peluches en 2027": an order of magnitude, reasoned in the open.
    case estimation
    /// "La capitale de l'Australie": a direct answer and a few points.
    case fact
    /// "Ton président préféré": only the user's own avis.md, never an invented opinion.
    case opinion
    /// About the user (fiches, stories): from the base, first person.
    case personal
    /// Code, algorithms: Approche → Code → Complexité → Points clés.
    case technical
    /// Small talk, statements: nothing to answer.
    case none

    /// Rules first (cue words), the personal classifier for phrasings they miss.
    public init(question: String, today: CalendarDay = .today()) {
        let tokens = BaseText.tokens(of: question)
        let intent = QueryIntent(question: question, today: today)
        func has(_ cues: [QueryIntent.Cue]) -> Bool { cues.contains { !$0.positions(in: tokens).isEmpty } }

        // "Ton projet préféré" is about the user's own projects; "ton livre préféré" is an opinion.
        if has(Self.opinionCues), intent.cueKinds.isDisjoint(with: [.project, .trip]) {
            self = .opinion
        } else if intent.isBehavioral, has(Self.technicalCues), !has(Self.narrativeCues) {
            // "Comment tu gères une erreur dans ton code ?": a story word, but no story asked for.
            self = .technical
        } else if intent.isAddressed, !intent.cueKinds.isEmpty {
            self = .personal
        } else if has(Self.estimationCues) {
            self = .estimation
        } else if intent.isPersonal {
            self = .personal
        } else if has(Self.technicalCues) {
            self = .technical
        } else if question.contains("?") || has(Self.questionWords) || TurnCompletion.requestsAnswer(question) {
            self = .fact
        } else {
            self = .none
        }
    }

    /// A year after this one, "l'an prochain", "next year": the answer is a projection.
    public static func asksAboutTheFuture(_ question: String, today: CalendarDay = .today()) -> Bool {
        let tokens = BaseText.tokens(of: question)
        if tokens.contains(where: { Int($0).map { $0 > today.year && $0 < 2200 } ?? false }) { return true }
        let joined = " " + tokens.joined(separator: " ") + " "
        return [" l an prochain ", " l annee prochaine ", " next year ", " a l avenir ", " in the future ", " dans dix ans "].contains(where: joined.contains)
    }

    static let opinionCues = [
        "prefere", "preferee", "preferes", "favori", "favorite", "favourite", "tu penses quoi", "qu est ce que tu penses",
        "tu en penses quoi", "ton avis sur", "votre avis sur", "what do you think", "your opinion", "you prefer", "tu preferes",
    ].map(QueryIntent.Cue.init)

    static let estimationCues = [
        "combien", "how many", "how much", "chiffre d affaires", "ventes", "vente", "marche", "market*", "estime*",
        "estimation*", "ordre de grandeur", "prevision*", "forecast*", "sales", "revenue*",
    ].map(QueryIntent.Cue.init)

    static let technicalCues = [
        "code", "coder", "algorithm*", "algorithme*", "complexite", "complexity", "fonction", "liste chainee", "linked list",
        "arbre", "tree", "recursion", "recursi*", "implement*", "thread*", "sql", "api", "hash*", "tri", "sort*", "java",
        "python", "swift", "pointeur*", "pointer*", "big o",
    ].map(QueryIntent.Cue.init)

    /// Without a "?": « qui » and « ou » (où / or) also start relative clauses and alternatives.
    static let questionWords = [
        "quoi", "quel", "quelle", "quels", "quelles", "c est qui", "comment", "pourquoi", "quand", "combien", "est ce que",
        "what", "who", "when", "where", "why", "how", "which",
    ].map(QueryIntent.Cue.init)

    /// A story is asked for: « raconte-moi », « parle-moi d'une fois où », "tell me about a time".
    static let narrativeCues = [
        "raconte*", "parle moi", "une fois", "situation", "exemple", "example", "tell me about", "describe",
        "a time", "plus grand*", "plus grande", "biggest", "greatest", "pire",
    ].map(QueryIntent.Cue.init)
}
