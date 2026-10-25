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

    public static func isComplete(_ text: String) -> Bool {
        let words = BaseText.tokens(of: text)
        guard let last = words.last, words.count >= 2 else { return false }
        let unfinished: Set<String> = ["et", "ou", "mais", "parce", "car", "donc", "si", "que", "de", "du", "des", "le", "la", "les", "un", "une", "avec", "pour", "and", "or", "but", "because", "if", "the", "a", "an", "with", "of", "to"]
        guard !unfinished.contains(last) else { return false }
        return true
    }
}
