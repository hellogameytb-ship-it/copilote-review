import Foundation

public enum VADEvent: Equatable, Sendable {
    case speechStarted(at: TimeInterval)
    case speechEnded(at: TimeInterval)
}

/// Energy-based voice activity detection on 16 kHz mono samples, in 20 ms frames.
/// A frame is voiced when it stands 12 dB above the background noise floor and above -55 dBFS.
/// The floor is the quietest frame of the last 4 seconds ("minimum statistics"): the gaps
/// between words keep it low while someone speaks, and a steady noise that gets louder
/// (music, a hum) becomes the new floor within seconds instead of reading as endless speech.
public struct VoiceActivityDetector: Sendable {
    public let sampleRate: Double
    private let frameLength: Int
    private let minSpeechFrames = 6     // 120 ms of voice before speech starts
    private let minSilenceFrames = 14   // 280 ms of quiet ends the phrase (keeps final text < 500 ms)

    private var pending: [Float] = []
    private var pendingStart: TimeInterval = 0
    private var isSpeaking = false
    private var runLength = 0
    private var runStart: TimeInterval = 0
    private var recentEnergies: [Double] = []
    private var nextEnergySlot = 0
    private let floorWindowFrames = 200 // 4 s

    public init(sampleRate: Double = 16_000) {
        self.sampleRate = sampleRate
        frameLength = Int(sampleRate * 0.02)
    }

    /// `time` is the timestamp of `samples[0]` on the channel's clock.
    public mutating func process(_ samples: [Float], startingAt time: TimeInterval) -> [VADEvent] {
        if pending.isEmpty { pendingStart = time }
        pending += samples
        var events: [VADEvent] = []
        while pending.count >= frameLength {
            let frame = pending.prefix(frameLength)
            let frameTime = pendingStart
            pending.removeFirst(frameLength)
            pendingStart += Double(frameLength) / sampleRate
            let energy = Self.energy(frame)
            remember(energy)
            let floor = recentEnergies.min() ?? energy
            if let event = step(isVoiced: energy > max(floor + 12, -55), at: frameTime) { events.append(event) }
        }
        return events
    }

    private mutating func step(isVoiced: Bool, at time: TimeInterval) -> VADEvent? {
        // A "run" counts consecutive frames that contradict the current state.
        guard isVoiced != isSpeaking else {
            runLength = 0
            return nil
        }
        if runLength == 0 { runStart = time }
        runLength += 1
        if !isSpeaking, runLength >= minSpeechFrames {
            isSpeaking = true
            runLength = 0
            return .speechStarted(at: runStart)
        }
        if isSpeaking, runLength >= minSilenceFrames {
            isSpeaking = false
            runLength = 0
            return .speechEnded(at: runStart)
        }
        return nil
    }

    private mutating func remember(_ energy: Double) {
        if recentEnergies.count < floorWindowFrames {
            recentEnergies.append(energy)
        } else {
            recentEnergies[nextEnergySlot] = energy
        }
        nextEnergySlot = (nextEnergySlot + 1) % floorWindowFrames
    }

    /// Mean power of the frame in dBFS.
    private static func energy(_ frame: ArraySlice<Float>) -> Double {
        let power = frame.reduce(0) { $0 + Double($1 * $1) } / Double(max(frame.count, 1))
        return 10 * log10(power + 1e-12)
    }
}
