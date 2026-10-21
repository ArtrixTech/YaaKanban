import Foundation

/// The span the overview covers, compared against the one before it.
public enum Period: String, CaseIterable, Sendable {
    case day, week, month

    public var component: Calendar.Component {
        switch self { case .day: .day; case .week: .weekOfYear; case .month: .month }
    }
}

/// The ranges and chart slices for a period `back` periods ago, all on the wall clock (a
/// daylight-saving day has 46 or 50 half hours).
public struct Periods: Equatable, Sendable {
    public var range: DateInterval
    public var previous: DateInterval
    /// The previous period up to as far into it, on the clock, as `now` is into this one.
    public var previousSoFar: DateInterval
    public var inProgress: Bool
    public var edges: [Date]
    public var previousEdges: [Date]

    public init(_ period: Period, back: Int, now: Date, calendar cal: Calendar = .current) {
        let anchor = cal.date(byAdding: period.component, value: -back, to: now)!
        range = cal.dateInterval(of: period.component, for: anchor)!
        previous = cal.dateInterval(of: period.component, for: cal.date(byAdding: period.component, value: -1, to: range.start)!)!
        inProgress = range.contains(now)
        if inProgress {
            // Rounded up to 10 minutes, so its cached report serves redraws for a while.
            let at = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 600).rounded(.up) * 600)
            // Days in, then the same clock time: not elapsed seconds, which shift across a clock change.
            let days = cal.dateComponents([.day], from: range.start, to: cal.startOfDay(for: at)).day ?? 0
            let clock = cal.dateComponents([.hour, .minute], from: at)
            let prev = previous
            let end = cal.date(byAdding: .day, value: days, to: prev.start)
                .flatMap { cal.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: $0) }
                .map { min($0, prev.end) } ?? prev.end
            previousSoFar = DateInterval(start: prev.start, end: max(prev.start, end))
        } else {
            previousSoFar = previous
        }
        edges = Self.edges(period, range, cal)
        previousEdges = Self.edges(period, previous, cal)
    }

    /// Half hours of a day, 3 hours of a week, days of a month, each at its clock time (a time
    /// skipped by daylight saving merges into the next, a repeated hour is one longer slot).
    public static func edges(_ period: Period, _ range: DateInterval, _ cal: Calendar) -> [Date] {
        let minutes: [Int] = switch period {
        case .day: Array(stride(from: 0, to: 1440, by: 30))
        case .week: Array(stride(from: 0, to: 1440, by: 180))
        case .month: [0]
        }
        var out: [Date] = []
        var day = range.start
        while day < range.end {
            for m in minutes {
                guard let d = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day),
                      range.contains(d), d != range.end, d > (out.last ?? .distantPast) else { continue }
                out.append(d)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = cal.startOfDay(for: next)
        }
        if out.first != range.start { out.insert(range.start, at: 0) }
        out.append(range.end)
        return out
    }
}
