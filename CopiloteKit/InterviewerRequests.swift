import Foundation

/// Split explicit consecutive requests while keeping explanatory clauses with their request.
/// A single question with several constraints remains a single card.
public enum InterviewerRequests {
    public static func turns(in turn: Turn) -> [Turn] {
        guard turn.speaker == .them else { return [turn] }
        let pattern = #"(?<=[?!;.])\s+|\s+(?i:and then|then|et puis)\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [turn] }
        let text = turn.text as NSString
        var pieces: [String] = []
        var offset = 0
        for match in regex.matches(in: turn.text, range: NSRange(location: 0, length: text.length)) {
            pieces.append(text.substring(with: NSRange(location: offset, length: match.range.location - offset)))
            offset = NSMaxRange(match.range)
        }
        pieces.append(text.substring(from: offset))
        var requests: [String] = []
        for piece in pieces where !piece.isEmpty {
            if TurnCompletion.requestsAnswer(piece) || requests.isEmpty { requests.append(piece) }
            else { requests[requests.count - 1] += " " + piece }
        }
        guard requests.count > 1, requests.allSatisfy(TurnCompletion.requestsAnswer) else { return [turn] }
        return requests.enumerated().map { index, text in
            let duration = (turn.end - turn.start) / Double(requests.count)
            return Turn(speaker: turn.speaker, text: text, start: turn.start + Double(index) * duration, end: turn.start + Double(index + 1) * duration)
        }
    }
}
