import Foundation

/// Computes `ActivityReport`s off the main thread, on a read-only connection of its own. The
/// reads behind one (a session's lane before the range, the rows in it) took tens of ms on a
/// large history, and more while the disk was busy; done in the views that show the figures, they
/// held up the panel as it folded and unfolded.
public final class ReportQueue: @unchecked Sendable {
    /// What a report is computed from, besides the stored rows.
    public struct Request: Sendable {
        public var range: DateInterval
        public var buckets: Int
        public var edges: [Date]?
        public var now: Date
        public var awaySince: Date?
        public var recordedSince: Date?
        public var interruptsSince: Date?

        public init(range: DateInterval, buckets: Int = 48, edges: [Date]? = nil, now: Date, awaySince: Date? = nil,
                    recordedSince: Date? = nil, interruptsSince: Date? = nil) {
            self.range = range
            self.buckets = buckets
            self.edges = edges
            self.now = now
            self.awaySince = awaySince
            self.recordedSince = recordedSince
            self.interruptsSince = interruptsSince
        }
    }

    private let queue = DispatchQueue(label: "com.artrix.yaakanban.reports", qos: .userInitiated)
    // Used only on `queue`.
    private let store: Store
    /// Each session's lane just before a report's start. Rows are recorded at or near the present,
    /// so for a start already past this no longer changes; `recorded` drops it when one lands earlier.
    private var lanesBefore: [Date: (lanes: [String: Lane], held: [String: Date])] = [:]

    public init(store: Store) { self.store = store }

    /// Computes the report on the queue and hands it to `done`, on the queue.
    public func compute(_ r: Request, done: @escaping @Sendable (ActivityReport) -> Void) {
        queue.async { done(self.compute(r)) }
    }

    /// The report, computed on the queue while the caller waits: for a report with nothing to show
    /// until it is ready.
    public func computeNow(_ r: Request) -> ActivityReport { queue.sync { compute(r) } }

    private func compute(_ r: Request) -> ActivityReport {
        if lanesBefore.count > 24 { lanesBefore = [:] }
        let before = lanesBefore[r.range.start] ?? (store.lanes(before: r.range.start), store.held(before: r.range.start))
        lanesBefore[r.range.start] = before
        // Work while away counts toward when the user left, so an absence from the range runs on past it.
        var to = min(r.range.end, r.now)
        if let a = r.awaySince, a < r.range.end { to = r.now }
        else if let e = store.awayEnd(across: r.range.end) { to = min(max(to, e), r.now) }
        return ActivityReport.compute(rows: store.activity(from: r.range.start, to: to),
                                      lanesBefore: before.lanes, heldBefore: before.held, range: r.range, now: r.now,
                                      awaySince: r.awaySince, recordedSince: r.recordedSince,
                                      interruptsSince: r.interruptsSince, buckets: r.buckets, edges: r.edges)
    }

    /// Rows were written (and committed): a lane row before a cached start changes what was open
    /// there. Queued after any compute already asked for, so none keeps a stale lane.
    public func recorded(_ rows: [ActivityRow]) {
        let times = rows.filter { $0.kind == .lane }.map(\.at)
        guard !times.isEmpty else { return }
        queue.async {
            if times.contains(where: { t in self.lanesBefore.keys.contains { t < $0 } }) { self.lanesBefore = [:] }
        }
    }

    /// Lanes were rewritten wholesale (a backfill).
    public func forgetLanes() { queue.async { self.lanesBefore = [:] } }
}
