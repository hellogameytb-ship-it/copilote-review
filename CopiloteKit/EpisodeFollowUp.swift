import Foundation

/// Only the immediately preceding completed, authorized episode can supply this reference.
public struct EpisodeReference: Sendable {
    public let lookup: String
    public let extracts: [BaseSnippet]
    public init(lookup: String, extracts: [BaseSnippet]) {
        self.lookup = lookup
        self.extracts = extracts
    }

    /// Match questions that refer back without naming a new subject. A trailing named
    /// project or a second question must go through a fresh lookup.
    public static func isFollowUp(_ text: String) -> Bool {
        let words = BaseText.tokens(of: InterviewEvidenceStore.currentQuestion([text])).joined(separator: " ")
        let forms = [
            #"what (?:exactly |specifically )?did you (?:personally |actually |specifically )?(?:do|contribute|implement|build|measure)(?: (?:yourself|personally|there|on that project|in that project|for that project|in that example))?"#,
            #"what was your (?:individual |own |personal |specific |exact )?(?:role|contribution|part)(?: (?:there|(?:on|in) (?:it|that project|that example)))?"#,
            #"(?:which|what) part (?:was yours|did you (?:own|handle|play))"#,
            #"(?:can|could) you (?:clarify|explain|elaborate on) your (?:own |personal |individual )?(?:contribution|role)(?: (?:there|in that project))?"#,
            #"how did you (?:measure|validate|test|solve|handle) (?:it|that)|what (?:was|were) the (?:result|results|outcome|impact)|what happened next|why did you (?:choose|do) that"#,
            #"toi(?: personnellement)?|qu (?:as tu|avez vous) fait(?: (?:personnellement|concretement|toi meme|vous meme))?|(?:toi )?tu as fait quoi(?: (?:personnellement|concretement))?"#,
            #"quel (?:etait|a ete) (?:ton|votre) (?:role|apport)(?: (?:personnel|exact))?|quelle (?:etait|a ete) (?:ta|votre) contribution|(?:ton|votre) role"#,
            #"comment (?:as tu|avez vous) (?:mesure|valide|teste) (?:ca|cela)|le resultat|les resultats"#
        ]
        let pattern = "^(?:(?:and|so|then|et|donc) )?(?:" + forms.joined(separator: "|") + ")$"
        return words.range(of: pattern, options: .regularExpression) != nil
    }
}
