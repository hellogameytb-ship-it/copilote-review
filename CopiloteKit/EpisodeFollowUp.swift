import Foundation

/// Only the immediately preceding completed, authorized episode can supply this reference.
public struct EpisodeReference: Sendable {
    public let lookup: String
    public let extracts: [BaseSnippet]
    public init(lookup: String, extracts: [BaseSnippet]) {
        self.lookup = lookup
        self.extracts = extracts
    }

    private static let roleForms = [
        #"what (?:exactly |specifically )?did you (?:personally |actually |specifically )?(?:do|contribute|implement|build|measure)(?: (?:yourself|personally|there|on that project|in that project|for that project|in that example))?"#,
        #"what was (?:your|my) (?:individual |own |personal |specific |exact )?(?:role|contribution|part)(?: (?:there|(?:on|in) (?:it|that project|that example)))?"#,
        #"(?:which|what) part (?:was yours|did you (?:own|handle|play))"#,
        #"(?:can|could) you (?:clarify|explain|elaborate on) your (?:own |personal |individual )?(?:contribution|role)(?: (?:there|in that project))?"#,
        #"toi(?: personnellement)?|qu (?:as tu|avez vous) fait(?: (?:personnellement|concretement|toi meme|vous meme))?|(?:toi )?tu as fait quoi(?: (?:personnellement|concretement))?"#,
        #"quel (?:etait|a ete) (?:ton|votre) (?:role|apport)(?: (?:personnel|exact))?|quelle (?:etait|a ete) (?:ta|votre) contribution|(?:ton|votre) role"#
    ]

    private static let otherForms = [
        #"how did you (?:measure|validate|test|solve|handle) (?:it|that)|what (?:was|were) the (?:result|results|outcome|impact)|what happened next|why did you (?:choose|do) that"#,
        #"comment (?:as tu|avez vous) (?:mesure|valide|teste) (?:ca|cela)|le resultat|les resultats"#
    ]

    /// Match complete questions so a trailing named project goes through a fresh lookup.
    public static func isFollowUp(_ text: String) -> Bool {
        matches(text, forms: roleForms + otherForms)
    }

    static func asksForRole(_ text: String) -> Bool {
        matches(text, forms: roleForms)
    }

    private static func matches(_ text: String, forms: [String]) -> Bool {
        let words = BaseText.tokens(of: InterviewEvidenceStore.currentQuestion([text])).joined(separator: " ")
        let pattern = "^(?:(?:and|so|then|et|donc) )?(?:" + forms.joined(separator: "|") + ")$"
        return words.range(of: pattern, options: .regularExpression) != nil
    }
}
