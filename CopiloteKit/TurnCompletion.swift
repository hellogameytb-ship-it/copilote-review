import Foundation

/// A conservative local endpoint check after VAD silence; no model call on every phrase.
public enum TurnCompletion {
    public static func requestsAnswer(_ text: String) -> Bool {
        guard isComplete(text) else { return false }
        if text.contains("?") { return true }
        let words = BaseText.tokens(of: text)
        let cues: Set<String> = ["comment", "pourquoi", "qui", "parle", "tell", "quel", "quelle", "quels", "quelles", "quand", "combien", "quoi", "peux", "pourrais", "explique", "raconte", "ecris", "implemente", "what", "why", "how", "which", "when", "where", "explain", "write", "implement", "describe", "present", "demonstrate", "show", "walk", "measure", "estimate", "calculate", "compare", "design", "build", "outline", "summarize", "discuss", "elaborate", "justify", "evaluate", "test", "optimize", "analyse", "analyze", "prove", "give", "list", "presente", "montre", "mesure", "compare", "calcule"]
        let lead = words.drop(while: { ["and", "then", "so", "please", "okay", "ok", "et", "alors"].contains($0) }).first ?? ""
        let joined = words.joined(separator: " ")
        return cues.contains(lead) || ["can", "could", "would", "does", "do", "is", "are"].contains(lead)
            || ["est ce que", "i would like you to", "i need you to", "we need you to", "walk me through", "talk me through"].contains(where: joined.hasPrefix)
    }

    public static func closesExchange(_ text: String) -> Bool {
        InterviewFocus.isClosing(InterviewFocus.normalized(text))
    }

    /// ASR sometimes appends '?' to explanations. Suppress those only for automatic drafting.
    public static func automaticRequest(_ text: String) -> Bool {
        let s = InterviewFocus.normalized(text)
        guard !InterviewFocus.isClosing(s), !LiveAnswerSnapshot.isSocial(text) else { return false }
        if ["are you ready to proceed", "are you ready to start", "can you hear me", "how are you doing", "how are you today"].contains(where: s.hasSuffix) { return false }
        if ["what i can tell you", "you d be working", "you be working", "you would be working", "the work spans",
            "i don t have those", "thanks for", "how we work", "our team will", "your english is clear"].contains(where: s.hasPrefix) { return false }
        return requestsAnswer(text)
    }

    public static func isComplete(_ text: String) -> Bool {
        let words = BaseText.tokens(of: text)
        guard let last = words.last, words.count >= 2 else { return false }
        let unfinished: Set<String> = ["et", "ou", "mais", "parce", "car", "donc", "si", "que", "de", "du", "des", "le", "la", "les", "un", "une", "avec", "pour", "and", "or", "but", "because", "if", "the", "a", "an", "with", "of", "to"]
        guard !unfinished.contains(last) else { return false }
        return true
    }
}
