import Foundation

/// Visible chat is independent of the bounded text carried to the next model request.
public enum ChatContextBudget {
    public static let maximumPairs = 6
    public static let maximumCharacters = 12_000
    public static func previousExchanges(_ exchanges: [(question: String, answer: String)]) -> String {
        var selected: [String] = []
        var remaining = maximumCharacters
        for exchange in exchanges.suffix(maximumPairs).reversed() {
            let text = "Earlier user question: \(exchange.question.prefix(2000))\nEarlier assistant draft (not evidence of personal facts): \(exchange.answer.prefix(4000))"
            guard text.count + 2 <= remaining else { break }
            selected.append(text); remaining -= text.count + 2
        }
        return selected.reversed().joined(separator: "\n\n")
    }
}
