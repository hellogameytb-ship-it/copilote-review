import Foundation

/// The first-launch welcome, in a small panel under the pill (Cluely's and Final Round's first
/// run, the user's retours 5): what Copilote does, the two permissions, Codex, the personal base, the
/// four shortcuts, the stealth mode, then « C'est parti ». Back and Next, skippable, replayable
/// from ⚙.
public struct Onboarding: Equatable, Sendable {
    public enum Step: Int, CaseIterable, Sendable {
        case welcome, permissions, codex, base, shortcuts, stealth
    }

    public private(set) var step: Step = .welcome
    public private(set) var isFinished = false

    public init() {}

    /// Where a relaunch left it (macOS may ask to relaunch Copilote for screen recording).
    public init(resumingAt rawStep: Int) {
        step = Step(rawValue: rawStep) ?? .welcome
    }

    public static var count: Int { Step.allCases.count }
    /// 1 to `count`, for « 2 sur 6 ».
    public var number: Int { step.rawValue + 1 }
    public var isLast: Bool { step == Step.allCases.last }
    public var canGoBack: Bool { step != .welcome }

    /// The next step; on the last one, « C'est parti ».
    public mutating func next() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next } else { isFinished = true }
    }

    public mutating func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    /// « Passer ».
    public mutating func finish() {
        isFinished = true
    }
}
