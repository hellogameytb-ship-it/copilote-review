import Foundation

/// Who is speaking, known from the audio channel (no diarization).
public enum Speaker: String, Sendable, Equatable, Codable {
    /// The microphone.
    case me = "Moi"
    /// System audio: the other people in the call.
    case them = "Eux"
    public var name: String { self == .me ? "Me" : "Them" }
}

/// One speaker's stretch of speech, from speech start to a pause long enough to end the turn.
/// Times are seconds on the audio channel's clock.
public struct Turn: Equatable, Sendable {
    public let speaker: Speaker
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speaker: Speaker, text: String, start: TimeInterval, end: TimeInterval) {
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
    }
}
