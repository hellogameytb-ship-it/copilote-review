import XCTest
@testable import CopiloteKit

/// 16 kHz mono signals built from silence, tones and noise; times in seconds.
final class VoiceActivityDetectorTests: XCTestCase {
    func test_detectsWhereSpeechStartsAndEnds() throws {
        let signal = Signal.silence(1.0) + Signal.tone(1.5) + Signal.silence(1.0)
        var vad = VoiceActivityDetector()

        let events = vad.process(signal, startingAt: 0)

        XCTAssertEqual(events.count, 2)
        guard case let .speechStarted(start) = events.first, case let .speechEnded(end) = events.last else {
            return XCTFail("expected start then end, got \(events)")
        }
        XCTAssertEqual(start, 1.0, accuracy: 0.03)
        XCTAssertEqual(end, 2.5, accuracy: 0.03)
    }
}

final class VoiceActivityDetectorRobustnessTests: XCTestCase {
    func test_aShortClickIsNotSpeech() {
        var vad = VoiceActivityDetector()

        let events = vad.process(Signal.silence(0.5) + Signal.tone(0.06) + Signal.silence(1.0), startingAt: 0)

        XCTAssertEqual(events, [])
    }

    func test_aBreathBetweenWordsDoesNotEndThePhrase() {
        var vad = VoiceActivityDetector()

        let events = vad.process(Signal.tone(1.0) + Signal.silence(0.2) + Signal.tone(1.0) + Signal.silence(1.0), startingAt: 0)

        XCTAssertEqual(events.count, 2)
    }

    /// Audio arrives in buffers of whatever size the device delivers.
    func test_bufferSizesDoNotChangeTheResult() {
        let signal = Signal.silence(0.7) + Signal.tone(1.3) + Signal.silence(0.9)
        var whole = VoiceActivityDetector()
        var chunked = VoiceActivityDetector()

        let expected = whole.process(signal, startingAt: 5)
        var events: [VADEvent] = []
        var offset = 0
        for size in [1_000, 37, 4_096, 511].cycled() {
            guard offset < signal.count else { break }
            let end = min(offset + size, signal.count)
            events += chunked.process(Array(signal[offset..<end]), startingAt: 5 + Double(offset) / Signal.sampleRate)
            offset = end
        }

        XCTAssertEqual(events, expected)
        XCTAssertEqual(events.count, 2)
    }

    /// A fan or a quiet room is not speech; a voice well above it is.
    func test_steadyBackgroundNoiseIsNotSpeech_butAVoiceAboveItIs() {
        let noise = Signal.noise(4.0, amplitude: 0.06) // about -30 dBFS
        let voice = Signal.silence(1.5) + Signal.tone(1.0) + Signal.silence(1.5)
        var vad = VoiceActivityDetector()

        let events = vad.process(zip(noise, voice).map(+), startingAt: 0)

        XCTAssertEqual(events.count, 2)
        if case let .speechStarted(start) = events.first { XCTAssertEqual(start, 1.5, accuracy: 0.05) }
    }

    /// Music or a hum that starts mid-call must not leave the VAD stuck in "speaking":
    /// no phrase end means no final text and no turn end.
    func test_backgroundNoiseThatGetsLouderIsEventuallyTreatedAsTheNewFloor() {
        var vad = VoiceActivityDetector()

        let events = vad.process(Signal.silence(1.0) + Signal.noise(20.0, amplitude: 0.1), startingAt: 0)

        guard case let .speechEnded(end)? = events.last else { return XCTFail("still speaking: \(events)") }
        XCTAssertLessThan(end, 7)
    }
}

private extension Array {
    func cycled() -> UnfoldSequence<Element, Int> {
        sequence(state: 0) { index in
            defer { index += 1 }
            return self[index % count]
        }
    }
}

enum Signal {
    static let sampleRate = 16_000.0

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    /// A 220 Hz tone: loud enough to be speech-level (about -13 dBFS).
    static func tone(_ seconds: Double, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { amplitude * sin(2 * .pi * 220 * Float($0) / Float(sampleRate)) }
    }

    /// Deterministic white noise.
    static func noise(_ seconds: Double, amplitude: Float) -> [Float] {
        var state: UInt32 = 12345
        return (0..<Int(seconds * sampleRate)).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return amplitude * (Float(state) / Float(UInt32.max) * 2 - 1)
        }
    }
}
