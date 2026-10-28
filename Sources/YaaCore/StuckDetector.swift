import Foundation

public struct StuckConfig: Codable, Equatable, Sendable {
    /// Running with no new event for this long.
    public var silence: TimeInterval
    /// A single foreground tool running for this long.
    public var toolDuration: TimeInterval

    public init(silence: TimeInterval = 300, toolDuration: TimeInterval = 300) {
        self.silence = silence
        self.toolDuration = toolDuration
    }
}

public enum StuckDetector {
    /// Tools that legitimately wait for a long time.
    static let waitingTools: Set<String> = ["monitor", "bashoutput", "wait", "sleep", "schedulewakeup", "task", "agent"]

    /// Returns the state with `stuck` applied (or a dead wait dropped), or nil when nothing changes.
    public static func evaluate(_ s: SessionState, now: Date, config: StuckConfig,
                                isAlive: (Int32) -> Bool) -> SessionState? {
        var out = s
        let processGone = s.agentPid.map { !isAlive($0) } ?? false

        switch s.status {
        // A finished session stays what it was when its process goes: the conversation is still
        // the user's work, and clicking the card offers to reopen it.
        case .ended, .idle:
            return nil
        case .needsInput:
            // Nobody is left to receive the answer.
            guard processGone else { return nil }
            out.status = .idle
            out.pendingPermission = nil
            out.needsInputMessage = nil
            out.needsInputSince = nil
            return out
        case .running, .stuck:
            // Nothing happened after its turn ended: it is finished, whatever revived it (an old
            // event replayed before the reducer ignored them). A background agent still out keeps
            // it running, unless the process is gone (its agents went with it).
            if s.hooked, let end = s.turns.last?.endedAt, end >= s.lastEventAt, s.runningTools.isEmpty, s.subagents.isEmpty,
               !s.awaitsBackground || processGone {
                out.status = .idle
                out.stuckReason = nil
                out.unreadSince = (s.reviewedAt ?? .distantPast) >= end ? nil : end
                return out
            }
            let reason: String?
            let waited = s.runningTools.filter { !leftBehind($0, in: s) }
            if processGone {
                reason = String(localized: "Process exited")
            } else if let t = waited.first(where: { !isBackground($0) && now.timeIntervalSince($0.startedAt) > config.toolDuration }) {
                reason = String(localized: "\(t.name) has been running for \(minutes(now.timeIntervalSince(t.startedAt))) min")
            } else if s.hooked, waited.isEmpty, s.subagents.isEmpty || s.awaitsBackground,
                      now.timeIntervalSince(s.lastEventAt) > config.silence {
                // Silence is only meaningful when hooks report every step. Waiting on background
                // agents it still applies, in case a stop or notification never comes.
                reason = String(localized: "No new events for \(minutes(now.timeIntervalSince(s.lastEventAt))) min")
            } else {
                reason = nil
            }
            if let reason {
                guard s.status != .stuck || s.stuckReason != reason else { return nil }
                out.status = .stuck
                out.stuckReason = reason
                return out
            }
            guard s.status == .stuck else { return nil }
            out.status = .running
            out.stuckReason = nil
            return out
        }
    }

    static func isBackground(_ t: ToolCall) -> Bool {
        if waitingTools.contains(t.name.lowercased()) { return true }
        return t.input.contains("\"run_in_background\":true")
    }

    /// The same agent started another call after it, so it is not waiting on this one. A Codex
    /// exec that outlives its yield keeps running while the agent moves on, and its end only comes
    /// when the agent polls it again. A waiting tool still counts: silence must not end its wait.
    static func leftBehind(_ t: ToolCall, in s: SessionState) -> Bool {
        !isBackground(t) && s.tools.contains { $0.subagentId == t.subagentId && $0.startedAt > t.startedAt }
    }

    static func minutes(_ t: TimeInterval) -> Int { Int(t / 60) }
}
