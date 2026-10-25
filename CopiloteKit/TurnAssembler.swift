import Foundation

/// Cuts one channel's speech into turns: a turn ends when the speaker has been quiet
/// for `turnGap` and the final transcript has caught up with the end of speech
/// (or after `finalizationGrace`, with whatever text has arrived). Continuous speech
/// is also cut every `maxTurnLength`, so a long monologue still yields turns.
public struct TurnAssembler: Sendable {
    public let speaker: Speaker
    public let turnGap: TimeInterval
    public let finalizationGrace: TimeInterval
    public let maxTurnLength: TimeInterval

    private var pending: [String] = []
    private var finalsEnd: TimeInterval = 0
    private var turnStart: TimeInterval?
    private var isSpeaking = false
    private var lastSpeechEnd: TimeInterval?

    public init(
        speaker: Speaker,
        turnGap: TimeInterval = 0.8,
        finalizationGrace: TimeInterval = 1.5,
        maxTurnLength: TimeInterval = 10
    ) {
        self.speaker = speaker
        self.turnGap = turnGap
        self.finalizationGrace = finalizationGrace
        self.maxTurnLength = maxTurnLength
    }

    public mutating func handle(_ event: VADEvent) {
        switch event {
        case let .speechStarted(time):
            isSpeaking = true
            if turnStart == nil { turnStart = time }
        case let .speechEnded(time):
            isSpeaking = false
            lastSpeechEnd = time
        }
    }

    public mutating func addFinal(_ text: String, start: TimeInterval, end: TimeInterval) {
        if turnStart == nil { turnStart = start }
        pending.append(text)
        finalsEnd = max(finalsEnd, end)
    }

    /// Call as audio time moves on; returns the turns that just ended.
    public mutating func advance(to now: TimeInterval) -> [Turn] {
        guard !pending.isEmpty, let start = turnStart else { return [] }
        if isSpeaking {
            guard now - start >= maxTurnLength else { return [] }
            return [emit(start: start, end: finalsEnd, nextStart: finalsEnd)]
        }
        guard let end = lastSpeechEnd, now - end >= turnGap else { return [] }
        // Final results end slightly before the VAD's end of speech (trailing silence).
        let transcriptCaughtUp = finalsEnd >= end - 0.3
        guard transcriptCaughtUp || now - end >= finalizationGrace else { return [] }
        // ASR punctuation alone is not reliable: a question ending in "et" / "because"
        // is still unfinished. Allow a longer pause for its continuation.
        guard TurnCompletion.isComplete(pending.joined(separator: " ")) || now - end >= 3 else { return [] }
        return [emit(start: start, end: max(end, finalsEnd), nextStart: nil)]
    }

    /// The stream is over: whatever text is left becomes a last turn.
    public mutating func flush() -> [Turn] {
        guard !pending.isEmpty, let start = turnStart else { return [] }
        return [emit(start: start, end: max(lastSpeechEnd ?? finalsEnd, finalsEnd), nextStart: nil)]
    }

    private mutating func emit(start: TimeInterval, end: TimeInterval, nextStart: TimeInterval?) -> Turn {
        let turn = Turn(speaker: speaker, text: pending.joined(separator: " "), start: start, end: end)
        pending.removeAll()
        turnStart = nextStart
        return turn
    }
}
