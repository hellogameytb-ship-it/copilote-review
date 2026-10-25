import Foundation

/// A date to the day, no time zone: what a fiche, a CV line or a photo's EXIF says.
public struct CalendarDay: Comparable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// "2025-07-04".
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Today in the user's calendar.
    public static func today(_ date: Date = Date(), calendar: Calendar = .current) -> CalendarDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return .day(parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Days since 1970-01-01 (proleptic Gregorian), for lengths and distances between days.
    public var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func lastDay(ofMonth month: Int, year: Int) -> Int {
        switch month {
        case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

/// Inclusive span of days.
public struct DateSpan: Hashable, Sendable, Codable {
    public let start: CalendarDay
    public let end: CalendarDay

    public init(_ start: CalendarDay, _ end: CalendarDay) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    /// Frontmatter dates: "2025-07-04", "2025-07" or "2025"; a missing end covers the start's
    /// whole day, month or year.
    public init?(start: String?, end: String?) {
        guard let start = start.flatMap(Self.partial) else { return nil }
        let end = end.flatMap(Self.partial) ?? start
        self.init(start.first, end.last)
    }

    /// Dates written in a line of text: "(juin 2024 – août 2024)", "2021–2024",
    /// "sept. 2025 - aujourd'hui". The first date starts the span, the last ends it.
    public init?(text: String, today: CalendarDay = .today()) {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        var found: [(first: CalendarDay, last: CalendarDay)] = []
        for match in folded.matches(of: Self.textDate) {
            if match.output.now != nil {
                found.append((today, today))
            } else if let year = match.output.year.flatMap({ Int($0) }) {
                let month = match.output.month.flatMap { Self.monthNumber(String($0)) }
                found.append(Self.range(year: year, month: month))
            }
        }
        guard let first = found.first, let last = found.last else { return nil }
        self.init(first.first, last.last)
    }

    /// Days in common with `other` (0 when apart).
    public func overlap(with other: DateSpan) -> Int {
        max(0, min(end.ordinal, other.end.ordinal) - max(start.ordinal, other.start.ordinal) + 1)
    }

    /// The whole month.
    public static func month(_ month: Int, of year: Int) -> DateSpan {
        DateSpan(.day(year, month, 1), .day(year, month, CalendarDay.lastDay(ofMonth: month, year: year)))
    }

    public func overlaps(_ other: DateSpan) -> Bool {
        start <= other.end && other.start <= end
    }

    public func contains(_ day: CalendarDay) -> Bool {
        start <= day && day <= end
    }

    // MARK: Parsing

    private static func partial(_ text: String) -> (first: CalendarDay, last: CalendarDay)? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-").map(String.init)
        guard let year = parts.first.flatMap(Int.init), parts[0].count == 4 else { return nil }
        switch parts.count {
        case 1:
            return range(year: year, month: nil)
        case 2:
            guard let month = Int(parts[1]), (1...12).contains(month) else { return nil }
            return range(year: year, month: month)
        case 3:
            guard let day = CalendarDay(iso: text.trimmingCharacters(in: .whitespaces)) else { return nil }
            return (day, day)
        default:
            return nil
        }
    }

    private static func range(year: Int, month: Int?) -> (first: CalendarDay, last: CalendarDay) {
        guard let month else { return (.day(year, 1, 1), .day(year, 12, 31)) }
        return (.day(year, month, 1), .day(year, month, CalendarDay.lastDay(ofMonth: month, year: year)))
    }

    private static let textDate = /(?<now>aujourd'hui|aujourd’hui|present|now|en cours)|(?:(?<month>janv(?:ier)?|fevr?(?:ier)?|mars|avr(?:il)?|mai|juin|juil(?:let)?|aout|sept(?:embre)?|oct(?:obre)?|nov(?:embre)?|dec(?:embre)?|jan(?:uary)?|feb(?:ruary)?|march|apr(?:il)?|may|june|july|aug(?:ust)?|sep|october|november|december)\.?\s+)?(?<year>(?:19|20)\d\d)(?!\d)/

    static func monthNumber(_ name: String) -> Int? {
        let prefixes: [(String, Int)] = [
            ("jan", 1), ("fe", 2), ("mar", 3), ("av", 4), ("ap", 4), ("mai", 5), ("may", 5),
            ("juin", 6), ("june", 6), ("juil", 7), ("july", 7), ("ao", 8), ("au", 8), ("se", 9),
            ("oc", 10), ("no", 11), ("de", 12),
        ]
        return prefixes.first { name.hasPrefix($0.0) }?.1
    }
}
