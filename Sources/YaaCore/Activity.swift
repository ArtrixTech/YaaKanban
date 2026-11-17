import Foundation

/// One recorded fact for the efficiency view. Rows are diffs of session states, written as they
/// happen, so a past day can be drawn without replaying every event.
public struct ActivityRow: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// The session entered `text` (a `Lane`), or left the lanes (`text` empty). A running row
        /// with `value` above 0 marks it, from here, only waiting on background work
        /// (`Activity.held`) since `heldSince`; one with 0 back at work. Such a row within the
        /// running lane does not end its stretch.
        case lane
        /// The user answered after `value` seconds of the agent waiting; `text` is the project.
        case reply
        /// A turn finished with `value` tool calls.
        case turn
        /// The user cut a turn short (stopped it, or prompted into it); `at` is when it ended.
        case interrupt
        /// `value` tokens were used (cache reads left out: they re-count the context on every request).
        case tokens
        /// The user jumped to a session.
        case focus
        /// The user was away (no input, or the app not running) for `value` seconds from `at`.
        case away
    }

    public var at: Date
    public var session: String
    public var kind: Kind
    public var value: Double
    public var text: String

    /// A running lane row marking a hold: since when the session has only waited on background
    /// work (`value`, in seconds since 1970; 1 for the row itself). Nil for any other row.
    public var heldSince: Date? {
        guard kind == .lane, text == Lane.running.rawValue, value > 0 else { return nil }
        return value > 1 ? Date(timeIntervalSince1970: value) : at
    }

    /// A row marking `session` held from `at`, waiting since `since` (a relaunch marks it again later).
    public static func held(_ session: String, at: Date, since: Date) -> ActivityRow {
        ActivityRow(at: at, session: session, kind: .lane, value: min(at, since).timeIntervalSince1970, text: Lane.running.rawValue)
    }

    public init(at: Date, session: String, kind: Kind, value: Double = 0, text: String = "") {
        self.at = at
        self.session = session
        self.kind = kind
        self.value = value
        self.text = text
    }
}

/// What a session is doing, as far as the swimlanes care. Finished and reviewed is no lane.
public enum Lane: String, CaseIterable, Sendable {
    case running, needsInput, stuck, review

    /// Waiting on the user.
    public var isWaiting: Bool { self != .running }

    public init?(_ d: DisplayStatus) {
        switch d {
        case .running: self = .running
        case .needsInput: self = .needsInput
        case .stuck: self = .stuck
        case .review: self = .review
        case .done, .ended: return nil
        }
    }
}

public enum Activity {
    /// Sessions this new are counted from their first token tally (there is no earlier one).
    static let freshSession: TimeInterval = 10 * 60

    /// The session's lane. Sub-agents work for their parent and have none.
    public static func lane(_ s: SessionState?) -> Lane? {
        guard let s, s.parentId == nil, s.dismissedAt == nil else { return nil }
        return Lane(s.display)
    }

    /// Running, but only waiting on background work: the turn is over, a background task (a
    /// shell: training, a build) is still out, and no background agent is working.
    public static func held(_ s: SessionState) -> Bool {
        s.status == .running && s.awaitsBackground && s.subagents.isEmpty && s.turns.last.map { $0.endedAt != nil } == true
    }

    /// When a held session's wait began: where its last turn ended (with any background agent's
    /// calls after the Stop), at most `now`.
    public static func heldSince(_ s: SessionState, now: Date) -> Date? {
        guard held(s), let i = s.turns.indices.last else { return nil }
        return min(now, s.end(ofTurn: i) ?? now)
    }

    /// The lane row for `s` entering `lane` at `now`. `working`: it ran just before, so a hold starts now.
    public static func laneRow(_ s: SessionState, _ lane: Lane?, now: Date, working: Bool) -> ActivityRow {
        if lane == .running, let since = heldSince(s, now: now) { return .held(s.id, at: now, since: working ? now : since) }
        return ActivityRow(at: now, session: s.id, kind: .lane, text: lane?.rawValue ?? "")
    }

    /// Rows for one state change, seen at `now`. `lane` maps a session to its lane (the app passes
    /// one that also knows which sessions have left the boards).
    public static func rows(old: SessionState?, new: SessionState, now: Date,
                            lane: (SessionState?) -> Lane? = Activity.lane) -> [ActivityRow] {
        var out: [ActivityRow] = []
        let id = new.id
        if let tokens = tokenDelta(old: old, new: new, now: now) {
            out.append(ActivityRow(at: now, session: id, kind: .tokens, value: Double(tokens)))
        }
        // Before the sub-agent check: a session found to be a sub-agent leaves the lanes.
        let (a, b) = (lane(old), lane(new))
        let (ha, hb) = (a == .running && old.map(held) == true, b == .running && held(new))
        if a != b || ha != hb {
            out.append(laneRow(new, b, now: now, working: a == .running && !ha))
        }
        guard new.parentId == nil, let old else { return out }
        // Only an agent the user still owed an answer counts: not a result already reviewed, nor
        // a session resumed days later.
        if a?.isWaiting == true, a != .stuck, let wait = replyWait(old: old, new: new), wait.latency >= 0 {
            out.append(ActivityRow(at: wait.at, session: id, kind: .reply, value: wait.latency, text: new.projectName ?? ""))
        }
        let ended = Set(old.turns.filter { $0.endedAt != nil }.map(\.id))
        for t in new.turns where t.endedAt != nil && !ended.contains(t.id) {
            out.append(ActivityRow(at: t.endedAt!, session: id, kind: .turn, value: Double(t.toolCount)))
        }
        // Counted with its turn, once it has ended and is known to be cut short: the transcript
        // can tell either before the end or after it.
        let cut = Set(old.turns.filter { $0.interrupted == true && $0.endedAt != nil }.map(\.id))
        for t in new.turns where t.interrupted == true && !cut.contains(t.id) {
            if let end = t.endedAt { out.append(ActivityRow(at: end, session: id, kind: .interrupt)) }
        }
        return out
    }

    static func work(_ u: Usage) -> Int { u.input + u.output + u.cacheWrite }

    private static func tokenDelta(old: SessionState?, new: SessionState, now: Date) -> Int? {
        guard let u = new.usage else { return nil }
        let before: Int
        if let o = old?.usage { before = work(o) }
        // The first tally of a session seen from its start counts in full; of an older one it is
        // only the baseline.
        else if now.timeIntervalSince(new.startedAt) < freshSession { before = 0 }
        else { return nil }
        let d = work(u) - before
        return d > 0 ? d : nil
    }

    /// The user answered a waiting agent: a blocked prompt went on, or a new prompt followed a
    /// finished turn. Returns when the answer came and how long the agent had waited.
    private static func replyWait(old: SessionState, new: SessionState) -> (at: Date, latency: TimeInterval)? {
        if new.turns.count > old.turns.count, let t = new.turns.last, old.status != .running {
            let since = old.status == .needsInput ? old.needsInputSince : old.turns.last?.endedAt
            return since.map { (t.startedAt, t.startedAt.timeIntervalSince($0)) }
        }
        if old.status == .needsInput, new.status == .running, let since = old.needsInputSince {
            return (new.lastEventAt, new.lastEventAt.timeIntervalSince(since))
        }
        return nil
    }
}

/// Activity rebuilt from the session history, for the time before it was recorded. Turns give
/// when each session ran; nothing records waits, replies or absences, so those stay empty.
public enum ActivityBackfill {
    public static func rows(_ sessions: [SessionState], before cutoff: Date) -> [ActivityRow] {
        var out: [ActivityRow] = []
        for s in sessions where s.parentId == nil {
            for t in s.turns where t.startedAt < cutoff {
                // Closed just before the cutoff, so recorded rows at the cutoff come after.
                let end = min(t.endedAt ?? s.lastEventAt, cutoff.addingTimeInterval(-0.001))
                guard end > t.startedAt else { continue }
                out.append(ActivityRow(at: t.startedAt, session: s.id, kind: .lane, text: Lane.running.rawValue))
                out.append(ActivityRow(at: end, session: s.id, kind: .lane))
                if t.endedAt != nil, t.endedAt! < cutoff {
                    out.append(ActivityRow(at: t.endedAt!, session: s.id, kind: .turn, value: Double(t.toolCount)))
                    if t.interrupted == true { out.append(ActivityRow(at: t.endedAt!, session: s.id, kind: .interrupt)) }
                }
            }
        }
        return out
    }
}

/// Marks, in lanes recorded before `Activity.held` was, the stretches a session ran after a turn
/// of its own (or its sub-agents') was over and before the next began: held for background work.
/// A turn ends where `SessionState.end(ofTurn:)` says, so a background agent's calls after the
/// Stop keep it at work. A session with no turns known (removed, or never hooked) is left as it
/// ran. Gaps under a minute are left. A stretch still open at `cutoff` stays held only for a
/// session held now; else it is back at work there.
public enum HeldBackfill {
    public static let minimumGap: TimeInterval = 60

    public static func rows(_ sessions: [SessionState], lanes: [ActivityRow], until cutoff: Date) -> [ActivityRow] {
        var turns: [String: [DateInterval]] = [:]
        for s in sessions {
            for k in s.turns.indices {
                let start = s.turns[k].startedAt, end = s.end(ofTurn: k) ?? cutoff
                guard end > start else { continue }
                turns[s.parentId ?? s.id, default: []].append(DateInterval(start: start, end: end))
            }
        }
        for k in turns.keys { turns[k]!.sort { $0.start < $1.start } }
        let heldNow = Set(sessions.filter { $0.parentId == nil && Activity.held($0) }.map(\.id))
        var out: [ActivityRow] = []
        // Just after the row that opened the stretch, so the two never tie.
        func held(_ id: String, _ t: Date, from a: Date, since: Date) {
            out.append(.held(id, at: t == a ? a.addingTimeInterval(0.001) : t, since: since))
        }
        func working(_ id: String, _ b: Date) {
            out.append(ActivityRow(at: b, session: id, kind: .lane, text: Lane.running.rawValue))
        }
        /// The running stretch a..<b; `open` when it still runs at the cutoff.
        func stretch(_ id: String, _ a: Date, _ b: Date, open: Bool) {
            let ts = turns[id] ?? []
            var t = a
            // Where the last turn before the stretch ended (a relaunch reopens a lane mid-wait).
            var over = ts.filter { $0.end <= a }.map(\.end).max()
            for i in ts where i.end > t && i.start < b {
                if let since = over, i.start.timeIntervalSince(t) >= minimumGap { held(id, t, from: a, since: since); working(id, i.start) }
                t = max(t, i.end)
                over = t
            }
            guard let since = over else { return }
            if open, heldNow.contains(id) { held(id, t, from: a, since: since) }
            else if b.timeIntervalSince(t) >= minimumGap {
                held(id, t, from: a, since: since)
                // The lane row that ends a closed stretch follows; an open one is back at work by the cutoff.
                if open { working(id, b.addingTimeInterval(-0.001)) }
            }
        }
        var from: [String: Date] = [:]
        for r in lanes.sorted(by: { $0.at < $1.at }) where r.kind == .lane && r.at < cutoff {
            if let a = from.removeValue(forKey: r.session) { stretch(r.session, a, r.at, open: false) }
            if r.text == Lane.running.rawValue { from[r.session] = r.at }
        }
        for (id, a) in from { stretch(id, a, cutoff, open: true) }
        return out
    }
}
