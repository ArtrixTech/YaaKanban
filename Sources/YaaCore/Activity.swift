import Foundation

/// One recorded fact for the efficiency view. Rows are diffs of session states, written as they
/// happen, so a past day can be drawn without replaying every event.
public struct ActivityRow: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// The session entered `text` (a `Lane`), or left the lanes (`text` empty).
        case lane
        /// The user answered after `value` seconds of the agent waiting; `text` is the project.
        case reply
        /// A turn finished with `value` tool calls.
        case turn
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
        if a != b { out.append(ActivityRow(at: now, session: id, kind: .lane, text: b?.rawValue ?? "")) }
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
                }
            }
        }
        return out
    }
}
