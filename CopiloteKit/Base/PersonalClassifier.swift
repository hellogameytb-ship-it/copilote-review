import Foundation

/// The small local classifier behind `QueryIntent`: naive Bayes over the words of a few dozen
/// example questions per kind, built in memory at first use (microseconds per question). It
/// only speaks when the cue words found nothing and the question is addressed to the user.
final class PersonalClassifier: Sendable {
    static let shared = PersonalClassifier(examples: PersonalClassifier.examples)

    private let classes: [BaseKind?]
    private let logLikelihoods: [[String: Double]]
    private let unseen: [Double]
    /// Below this, the question is left to the LLM.
    let threshold = 0.6

    init(examples: [(BaseKind?, String)]) {
        var counts: [Int: [String: Int]] = [:]
        var classes: [BaseKind?] = []
        for (kind, text) in examples {
            if !classes.contains(kind) { classes.append(kind) }
            let index = classes.firstIndex(of: kind)!
            for token in BaseText.tokens(of: text) where token.count > 1 {
                counts[index, default: [:]][token, default: 0] += 1
            }
        }
        let vocabulary = Set(counts.values.flatMap(\.keys))
        self.classes = classes
        var likelihoods: [[String: Double]] = []
        var unseen: [Double] = []
        for index in classes.indices {
            let words = counts[index] ?? [:]
            let total = Double(words.values.reduce(0, +) + vocabulary.count)
            likelihoods.append(words.mapValues { log(Double($0 + 1) / total) })
            unseen.append(log(1 / total))
        }
        logLikelihoods = likelihoods
        self.unseen = unseen
    }

    /// The kind of fiche the question is about, or nil (not personal, or not sure).
    func kind(of tokens: [String]) -> BaseKind? {
        let words = tokens.filter { $0.count > 1 }
        let scores = classes.indices.map { index in
            words.reduce(0) { $0 + (logLikelihoods[index][$1] ?? unseen[index]) }
        }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }) else { return nil }
        let top = scores[best]
        let probability = 1 / scores.reduce(0) { $0 + exp($1 - top) }
        return probability >= threshold ? classes[best] : nil
    }

    static let examples: [(BaseKind?, String)] = [
        (.trip, "C'était comment ton séjour au Japon ?"),
        (.trip, "Tu as aimé la ville ?"),
        (.trip, "Il faisait beau là-bas ?"),
        (.trip, "Tu as visité des musées ?"),
        (.trip, "Tu es restée combien de temps sur place ?"),
        (.trip, "Vous êtes allés à la plage ?"),
        (.trip, "Tu as goûté la cuisine locale ?"),
        (.trip, "Tu as pris l'avion ou le train pour y aller ?"),
        (.trip, "Tu as dormi où pendant ton séjour ?"),
        (.trip, "Tu y retournerais ?"),
        (.trip, "How was your stay over there?"),
        (.trip, "Did you enjoy the beach?"),
        (.project, "Tu bosses sur quoi en ce moment ?"),
        (.project, "Ça sert à quoi ce que tu as codé ?"),
        (.project, "Combien d'utilisateurs l'utilisent ?"),
        (.project, "Tu l'as mis en ligne ?"),
        (.project, "C'est open source ton truc ?"),
        (.project, "Quelle architecture tu as choisie pour ton outil ?"),
        (.project, "Tu as codé ça toute seule ?"),
        (.project, "Ça tourne sur quoi ton backend ?"),
        (.project, "What are you building right now?"),
        (.project, "Is your tool live?"),
        (.cv, "Tu as travaillé où avant ?"),
        (.cv, "Tu es en quelle année ?"),
        (.cv, "Tu maîtrises quels outils ?"),
        (.cv, "Tu parles anglais ?"),
        (.cv, "Tu as déjà fait de l'enseignement ?"),
        (.cv, "Ton dernier poste, c'était quoi ?"),
        (.cv, "Tu es diplômée de quelle école ?"),
        (.cv, "What did you do at your last company?"),
        (.cv, "Which tools are you comfortable with?"),
        (.bio, "Tu habites où ?"),
        (.bio, "Tu as grandi où ?"),
        (.bio, "Qu'est-ce que tu aimes faire le week-end ?"),
        (.bio, "Tu fais du sport ?"),
        (.bio, "Tu as des frères et sœurs ?"),
        (.bio, "Tu fais quoi pour te détendre ?"),
        (.bio, "Qu'est-ce qui te passionne ?"),
        (.bio, "Tu lis quoi en ce moment ?"),
        (.bio, "Tu cuisines ?"),
        (.bio, "What do you do on weekends?"),
        (.bio, "Do you have any hobbies?"),
        (nil, "Tu peux m'expliquer comment fonctionne une table de hachage ?"),
        (nil, "Comment tu implémenterais un cache LRU ?"),
        (nil, "Quelle est la complexité de ton algorithme ?"),
        (nil, "Tu peux partager ton écran ?"),
        (nil, "Tu m'entends bien ?"),
        (nil, "Tu as une question pour nous ?"),
        (nil, "Qu'est-ce que tu penses de cette approche ?"),
        (nil, "Tu peux résumer ce qu'on vient de dire ?"),
        (nil, "On passe au point suivant, tu es d'accord ?"),
        (nil, "Tu peux m'expliquer la différence entre un processus et un thread ?"),
        (nil, "Comment tu optimiserais cette requête SQL ?"),
        (nil, "Tu préfères qu'on fasse une pause ?"),
        (nil, "Tu as vu le mail de ce matin ?"),
        (nil, "Can you explain how garbage collection works?"),
        (nil, "How would you design a rate limiter?"),
    ]
}
