import Foundation

/// The user's opinion on a subject, from avis.md only: a section whose title names the subject.
/// The whole title must be asked about, word for word: "ton président préféré ?" does not land on
/// "Livre préféré", nor "Lyon comme ville ?" on "Ville où vivre", nor "le programme" on "Langage
/// de programmation". A miss gives neutral angles, never someone else's opinion.
public enum OpinionLookup {
    /// The best two sections whose every title word is in the question.
    public static func sections(for question: String, in items: [BaseItem]) -> [BaseItem] {
        let asked = subjectWords(question)
        guard !asked.isEmpty else { return [] }
        return items
            .filter { $0.kind == .opinion && $0.section != nil }
            .compactMap { item -> (BaseItem, Int)? in
                let title = subjectWords(item.section ?? "")
                guard !title.isEmpty, title.allSatisfy({ word in asked.contains { same($0, word) } }) else { return nil }
                let text = LexicalTopicSegmenter.keywords(item.text)
                return (item, 2 * title.count + asked.filter { word in text.contains { same($0, word) } }.count)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .map(\.0)
    }

    /// "C'est qui ton président préféré ?" → "Président préféré": the heading to add to avis.md.
    public static func subject(ofTitle title: String) -> String {
        var subject = title.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "?!.")))
        var matching = true
        while matching {
            let folded = subject.lowercased().replacingOccurrences(of: "’", with: "'")
            guard let opener = openers.first(where: { folded.hasPrefix($0) }) else { break }
            subject = String(subject.dropFirst(opener.count))
            matching = !subject.isEmpty
        }
        subject = subject.trimmingCharacters(in: .whitespaces)
        return subject.isEmpty ? title : subject.prefix(1).uppercased() + subject.dropFirst()
    }

    /// Longest first.
    private static let openers = [
        "qu'est-ce que tu penses de la ", "qu'est-ce que tu penses du ", "qu'est-ce que tu penses des ", "qu'est-ce que tu penses de ",
        "tu penses quoi de la ", "tu penses quoi de l'", "tu penses quoi du ", "tu penses quoi des ", "tu penses quoi de ",
        "c'est qui ton ", "c'est qui ta ", "c'est quoi ton ", "c'est quoi ta ", "c'est quoi tes ",
        "quel est ton ", "quelle est ta ", "quels sont tes ", "quelles sont tes ", "ton avis sur ",
        "what do you think about ", "what do you think of ", "what's your ", "what is your ",
        "ton ", "ta ", "tes ", "votre ", "your ",
    ]

    /// The question's content words, without the words that only say "an opinion is asked".
    static func subjectWords(_ question: String) -> Set<String> {
        LexicalTopicSegmenter.keywords(question).filter { word in !opinionWords.contains { word.hasPrefix($0) } }
    }

    /// The same word, give or take an ending: livre / livres, préféré / préférées (not programme /
    /// programmation).
    static func same(_ a: String, _ b: String) -> Bool {
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        return long.hasPrefix(short) && long.count - short.count <= 2 && short.count >= 3
    }

    /// Accent-free prefixes.
    private static let opinionWords = [
        "prefer", "favori", "favour", "favor", "avis", "pense", "crois", "trouve", "aime", "meilleur",
        "opinion", "think", "like", "best", "view",
    ]
}
