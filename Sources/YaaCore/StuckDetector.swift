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

    /// Returns the state with `stuck`/`ended` applied, or nil when nothing changes.
    public static func evaluate(_ s: SessionState, now: Date, config: StuckConfig,
                                isAlive: (Int32) -> Bool) -> SessionState? {
        var out = s
        let processGone = s.agentPid.map { !isAlive($0) } ?? false

        switch s.status {
        case .ended:
            return nil
        case .idle, .needsInput:
            guard processGone else { return nil }
            out.status = .ended
            out.interruptedAt = now
            out.pendingPermission = nil
            return out
        case .running, .stuck:
            let reason: String?
            if processGone {
                reason = "进程已退出"
            } else if let t = s.runningTools.first(where: { !isBackground($0) && now.timeIntervalSince($0.startedAt) > config.toolDuration }) {
                reason = "\(t.name) 已运行 \(minutes(now.timeIntervalSince(t.startedAt))) 分钟"
            } else if s.hooked, s.runningTools.isEmpty, s.subagents.isEmpty, now.timeIntervalSince(s.lastEventAt) > config.silence {
                // Silence is only meaningful when hooks report every step.
                reason = "\(minutes(now.timeIntervalSince(s.lastEventAt))) 分钟无新事件"
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

    static func minutes(_ t: TimeInterval) -> Int { Int(t / 60) }
}
