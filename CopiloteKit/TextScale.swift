import Foundation

/// The answer's text size (⌥⌘= / ⌥⌘-, Réglages › Réponses): by tenths, 80 to 160 %.
public enum TextScale {
    public static let range = 0.8...1.6
    public static let step = 0.1

    public static func clamped(_ scale: Double) -> Double {
        min(max(scale, range.lowerBound), range.upperBound)
    }

    /// A step up or down, back on the tenths, within the range.
    public static func stepped(from scale: Double, by steps: Int) -> Double {
        clamped(((scale + Double(steps) * step) * 10).rounded() / 10)
    }
}
