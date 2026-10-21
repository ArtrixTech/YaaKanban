import Foundation

/// Efficiency figures over a time range, from recorded `ActivityRow`s. Pure, so the same numbers
/// back the main window, the menu and the tests.
public struct ActivityReport: Sendable {
    public struct Segment: Equatable, Sendable {
        public var lane: Lane
        public var start: Date
        public var end: Date
    }

    public var range: DateInterval
    /// Swimlanes: per session, its lane segments within the range, sessions in order of first activity.
    public var lanes: [(session: String, segments: [Segment])] = []
    /// Merged times the user was away, within the range.
    public var away: [DateInterval] = []

    /// Time something was running or waiting on the user, while the user was here.
    public var activeTime: TimeInterval = 0
    /// Average number of running sessions while at least one ran, and the most at once.
    public var parallelAverage: Double = 0
    public var parallelPeak = 0
    /// Where the chart slices start and end: `buckets + 1` dates over the whole range.
    public var bucketEdges: [Date] = []
    /// Average running sessions per slice of the whole range, for a chart.
    public var parallelBuckets: [Double] = []
    /// Average sessions waiting on the user per slice, while the user was here.
    public var waitingBuckets: [Double] = []
    /// Running ÷ (running + waiting on the user), in session-time, while the user was here.
    public var utilization: Double?
    /// Time something waited on the user and nothing ran, while the user was here.
    public var bottleneck: TimeInterval = 0
    /// How long agents waited for the user to answer, away time taken out.
    public var replies: [TimeInterval] = []
    public var replyMedian: TimeInterval?
    public var replyP90: TimeInterval?
    /// Median reply per project, slowest first.
    public var replyByProject: [(project: String, median: TimeInterval, count: Int)] = []
    public var turns = 0
    public var toolCalls = 0
    public var tokens = 0
    /// Jumps to a session.
    public var switches = 0
    /// The range up to here was rebuilt from the session history: running time and turns only,
    /// no waits, replies, absences or tokens. Utilization and bottleneck cover only the rest.
    public var rebuiltUntil: Date?
    /// Nothing in the range was recorded live, so waits are unknown.
    public var allRebuilt: Bool { rebuiltUntil.map { $0 >= min(range.end, computedAt) } ?? false }
    var computedAt = Date.distantFuture

    public init(range: DateInterval) { self.range = range }

    public var activeHours: Double { activeTime / 3600 }
    public func perActiveHour(_ n: Int) -> Double? { activeTime >= 60 ? Double(n) / activeHours : nil }

    /// Per session, time running and waiting on the user (away time taken out) in the range,
    /// busiest first.
    public var sessionTotals: [(session: String, running: TimeInterval, waiting: TimeInterval)] {
        lanes.map { l in
            var run = 0.0, wait = 0.0
            for s in l.segments {
                let i = DateInterval(start: s.start, end: s.end)
                if s.lane == .running { run += i.duration } else { wait += i.duration - Self.overlap(i, away) }
            }
            return (l.session, run, wait)
        }
        .sorted { $0.running + $0.waiting > $1.running + $1.waiting }
    }

    /// - Parameters:
    ///   - rows: rows in `range`, plus away rows that reach into it.
    ///   - lanesBefore: each session's lane when the range starts.
    ///   - awaySince: the user has been away since then, still.
    ///   - recordedSince: rows before this were rebuilt (`ActivityBackfill`).
    ///   - buckets: equal chart slices, unless `edges` gives them (e.g. calendar days).
    public static func compute(rows: [ActivityRow], lanesBefore: [String: Lane], range: DateInterval,
                               now: Date, awaySince: Date? = nil, recordedSince: Date? = nil,
                               buckets: Int = 48, edges: [Date]? = nil) -> ActivityReport {
        var r = ActivityReport(range: range)
        r.bucketEdges = edges.flatMap { $0.count > 1 ? $0 : nil }
            ?? (0...max(buckets, 1)).map { range.start.addingTimeInterval(range.duration * Double($0) / Double(max(buckets, 1))) }
        r.computedAt = now
        r.rebuiltUntil = recordedSince.flatMap { $0 > range.start ? min($0, range.end) : nil }
        let end = min(range.end, now)
        guard end > range.start else { return r }
        let rows = rows.sorted { $0.at < $1.at }

        r.away = mergedAway(rows: rows, awaySince: awaySince, from: range.start, to: end)

        // Lane segments.
        var open: [String: (Lane, Date)] = [:]
        var order: [String] = []
        var seen: Set<String> = []
        var segs: [String: [Segment]] = [:]
        func close(_ id: String, at t: Date) {
            guard let (lane, from) = open.removeValue(forKey: id), t > from else { return }
            segs[id, default: []].append(Segment(lane: lane, start: from, end: t))
        }
        for (id, lane) in lanesBefore.sorted(by: { $0.key < $1.key }) {
            open[id] = (lane, range.start)
            order.append(id); seen.insert(id)
        }
        for row in rows where row.kind == .lane && row.at >= range.start && row.at < end {
            close(row.session, at: row.at)
            if let lane = Lane(rawValue: row.text) {
                open[row.session] = (lane, row.at)
                if seen.insert(row.session).inserted { order.append(row.session) }
            }
        }
        for id in Array(open.keys) { close(id, at: end) }
        r.lanes = order.compactMap { id in segs[id].map { (id, $0) } }

        r.sweep(segments: segs.values.flatMap { $0 }, from: range.start, to: end, measuredFrom: r.rebuiltUntil ?? range.start)

        for row in rows where row.at >= range.start && row.at < end {
            switch row.kind {
            case .turn: r.turns += 1; r.toolCalls += Int(row.value)
            case .tokens: r.tokens += Int(row.value)
            case .focus: r.switches += 1
            case .lane, .reply, .away: break
            }
        }

        // Replies: the wait minus any time the user was away during it.
        let allAway = mergedAway(rows: rows, awaySince: awaySince, from: .distantPast, to: end)
        var byProject: [String: [TimeInterval]] = [:]
        for row in rows where row.kind == .reply && row.at >= range.start && row.at < end {
            let wait = DateInterval(start: row.at.addingTimeInterval(-row.value), end: row.at)
            let latency = max(0, row.value - overlap(wait, allAway))
            r.replies.append(latency)
            if !row.text.isEmpty { byProject[row.text, default: []].append(latency) }
        }
        r.replyMedian = percentile(r.replies, 0.5)
        r.replyP90 = percentile(r.replies, 0.9)
        r.replyByProject = byProject.map { ($0.key, percentile($0.value, 0.5)!, $0.value.count) }
            .sorted { $0.median > $1.median }
        return r
    }

    /// Walks the range through every segment and away edge, adding up time by how many sessions
    /// ran or waited. Waits count only from `measuredFrom`, where they were recorded.
    private mutating func sweep(segments: [Segment], from start: Date, to end: Date, measuredFrom: Date) {
        // (time, Δrunning, Δwaiting, Δaway)
        var edges: [(Date, Int, Int, Int)] = []
        for s in segments {
            let (dr, dw) = s.lane == .running ? (1, 0) : (0, 1)
            edges.append((s.start, dr, dw, 0))
            edges.append((s.end, -dr, -dw, 0))
        }
        for a in away {
            edges.append((a.start, 0, 0, 1))
            edges.append((a.end, 0, 0, -1))
        }
        edges.append((measuredFrom, 0, 0, 0))
        edges.sort { $0.0 < $1.0 }

        // Slices cover the whole range, so they line up with its axis; those past now stay 0.
        let cuts = bucketEdges.map { $0.timeIntervalSince(start) }
        let n = cuts.count - 1
        var runSums = [Double](repeating: 0, count: max(n, 0))
        var waitSums = runSums
        /// Spreads `count` over the slices t..<next covers. Steps by slice index: recomputing it
        /// from `a` can round down at an edge and never advance.
        func spread(_ count: Int, _ t: Date, _ next: Date, into sums: inout [Double]) {
            var a = t.timeIntervalSince(start)
            let b = next.timeIntervalSince(start)
            var k = max(0, (cuts.firstIndex { $0 > a } ?? cuts.count) - 1)
            while a < b, k < n {
                let edge = k == n - 1 ? b : min(b, cuts[k + 1])
                sums[k] += Double(count) * max(0, edge - a)
                a = max(a, edge)
                k += 1
            }
        }
        var running = 0, waiting = 0, awayDepth = 0
        var t = start
        var runTime = 0.0, waitTime = 0.0, parallelWeighted = 0.0, parallelTime = 0.0
        var i = 0
        while t < end {
            while i < edges.count, edges[i].0 <= t {
                running += edges[i].1; waiting += edges[i].2; awayDepth += edges[i].3
                i += 1
            }
            let next = i < edges.count ? min(edges[i].0, end) : end
            let dt = next.timeIntervalSince(t)
            if dt > 0 {
                if running > 0 {
                    parallelWeighted += Double(running) * dt
                    parallelTime += dt
                    parallelPeak = max(parallelPeak, running)
                    spread(running, t, next, into: &runSums)
                }
                if waiting > 0, awayDepth == 0 { spread(waiting, t, next, into: &waitSums) }
                if awayDepth == 0 {
                    if running > 0 || waiting > 0 { activeTime += dt }
                    if t >= measuredFrom {
                        runTime += Double(running) * dt
                        waitTime += Double(waiting) * dt
                        if running == 0 && waiting > 0 { bottleneck += dt }
                    }
                }
            }
            t = next
        }
        parallelAverage = parallelTime > 0 ? parallelWeighted / parallelTime : 0
        let widths = (0..<max(n, 0)).map { cuts[$0 + 1] - cuts[$0] }
        parallelBuckets = zip(runSums, widths).map { $1 > 0 ? $0 / $1 : 0 }
        waitingBuckets = zip(waitSums, widths).map { $1 > 0 ? $0 / $1 : 0 }
        utilization = runTime + waitTime > 0 ? runTime / (runTime + waitTime) : nil
    }

    static func mergedAway(rows: [ActivityRow], awaySince: Date?, from start: Date, to end: Date) -> [DateInterval] {
        var spans = rows.filter { $0.kind == .away }.map { ($0.at, $0.at.addingTimeInterval($0.value)) }
        if let awaySince { spans.append((awaySince, end)) }
        var out: [DateInterval] = []
        for (a, b) in spans.sorted(by: { $0.0 < $1.0 }) {
            let (a, b) = (max(a, start), min(b, end))
            guard b > a else { continue }
            if let last = out.last, a <= last.end {
                out[out.count - 1].end = max(last.end, b)
            } else {
                out.append(DateInterval(start: a, end: b))
            }
        }
        return out
    }

    static func overlap(_ i: DateInterval, _ spans: [DateInterval]) -> TimeInterval {
        spans.reduce(0) { sum, s in
            let a = max(i.start, s.start), b = min(i.end, s.end)
            return sum + max(0, b.timeIntervalSince(a))
        }
    }

    /// Nearest-rank percentile.
    static func percentile(_ xs: [TimeInterval], _ p: Double) -> TimeInterval? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s[min(s.count - 1, max(0, Int((p * Double(s.count)).rounded(.up)) - 1))]
    }
}

/// Sessions waiting on the user right now, and since when the longest has waited.
public struct Backlog: Equatable, Sendable {
    public var count = 0
    public var oldest: Date?

    public init(_ sessions: [SessionState]) {
        for s in sessions {
            guard let lane = Activity.lane(s), lane.isWaiting else { continue }
            count += 1
            let since = s.status == .needsInput ? s.needsInputSince ?? s.lastEventAt
                : s.status == .stuck ? s.lastEventAt : s.unreadSince ?? s.lastEventAt
            oldest = min(oldest ?? since, since)
        }
    }
}
