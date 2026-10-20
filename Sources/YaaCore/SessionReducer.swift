import Foundation

/// Pure state machine: folds agent events into session state.
public enum SessionReducer {
    public static let outputLimit = 2048

    public static func apply(_ e: AgentEvent, to existing: SessionState?) -> SessionState {
        var s = existing ?? SessionState(agent: e.agent, sessionId: e.sessionId, at: e.at)
        if case .statusSnapshot(let status) = e.kind {
            // Session files only drive sessions without hooks; for hooked ones they must not
            // count as activity, or silence-based stuck detection would never fire.
            if s.hooked { return s }
            if s.status != status { s.lastEventAt = max(s.lastEventAt, e.at) }
            s.cwd = s.cwd ?? e.cwd
            s.agentPid = s.agentPid ?? e.agentPid
            s.status = status
            return s
        }
        s.lastEventAt = max(s.lastEventAt, e.at)
        if let v = e.cwd { s.cwd = v }
        if let v = e.transcriptPath { s.transcriptPath = v }
        if let v = e.agentPid { s.agentPid = v }
        if let v = e.terminal { s.terminal = v }
        s.hooked = true

        switch e.kind {
        case .sessionStart:
            if s.status == .ended { s.status = .idle }

        case .promptSubmitted(let prompt):
            s.turns.append(Turn(id: s.turns.count + 1, prompt: prompt, startedAt: e.at, toolCount: 0))
            s.status = .running
            clearAttention(&s)

        case .toolStart(let id, let name, let input):
            s.tools.append(ToolCall(id: id, name: name, summary: ToolSummary.summarize(tool: name, input: input),
                                    input: input.text, output: nil, isError: false, startedAt: e.at,
                                    subagentId: e.subagentId))
            if s.tools.count > SessionState.toolHistoryLimit { s.tools.removeFirst(s.tools.count - SessionState.toolHistoryLimit) }
            if s.turns.isEmpty { s.turns.append(Turn(id: 1, prompt: "", startedAt: e.at, toolCount: 0)) }
            s.turns[s.turns.count - 1].toolCount += 1
            resume(&s)

        case .toolEnd(let id, let name, let output, let isError):
            let idx = s.tools.lastIndex { $0.id == id && $0.isRunning }
                ?? s.tools.lastIndex { $0.name == name && $0.isRunning }
            let clipped = output.map { $0.count > outputLimit ? String($0.prefix(outputLimit)) + "…" : $0 }
            if let idx {
                s.tools[idx].endedAt = e.at
                s.tools[idx].output = clipped
                s.tools[idx].isError = isError
            }
            if s.pendingPermission?.id == id || s.pendingPermission?.tool == name { s.pendingPermission = nil }
            resume(&s)

        case .needsInput(let message):
            s.status = .needsInput
            s.needsInputMessage = message

        case .inputAnswered:
            if s.status == .needsInput { s.status = .running }
            clearAttention(&s)

        case .permission(let req):
            s.status = .needsInput
            s.pendingPermission = req
            s.needsInputMessage = "\(req.tool): \(req.summary)"

        case .turnEnd(let last):
            if let i = s.turns.indices.last {
                s.turns[i].endedAt = e.at
                s.turns[i].lastMessage = last
            }
            endRunningTools(&s, at: e.at)
            s.subagents.removeAll()
            s.status = .idle
            clearAttention(&s)

        case .sessionEnd:
            endRunningTools(&s, at: e.at)
            s.subagents.removeAll()
            s.status = .ended
            clearAttention(&s)

        case .subagentStart(let id, let type):
            s.subagents.append(Subagent(id: id, type: type, startedAt: e.at))
            resume(&s)

        case .subagentStop(let id):
            if let i = s.subagents.firstIndex(where: { $0.id == id }) ?? (s.subagents.isEmpty ? nil : 0) {
                s.subagents.remove(at: i)
            }
            for i in s.tools.indices where s.tools[i].isRunning && s.tools[i].subagentId == id {
                s.tools[i].endedAt = e.at
            }

        case .statusSnapshot:
            break
        }
        return s
    }

    /// Activity after a pause: a stuck session is running again, and a pending
    /// permission is resolved once tools move.
    private static func resume(_ s: inout SessionState) {
        if s.status == .stuck || s.status == .idle || s.status == .ended { s.status = .running }
        if s.status == .needsInput && s.pendingPermission == nil && !lastToolIsAsk(s) { s.status = .running }
        if s.status == .running { s.needsInputMessage = nil; s.stuckReason = nil }
    }

    private static func lastToolIsAsk(_ s: SessionState) -> Bool {
        guard let t = s.tools.last, t.isRunning else { return false }
        return Normalizer.askTools.contains(t.name.lowercased())
    }

    private static func clearAttention(_ s: inout SessionState) {
        s.needsInputMessage = nil
        s.pendingPermission = nil
        s.stuckReason = nil
    }

    private static func endRunningTools(_ s: inout SessionState, at: Date) {
        for i in s.tools.indices where s.tools[i].isRunning { s.tools[i].endedAt = at }
    }
}

/// What the user should be told about a status change.
public enum Alert: Equatable, Sendable {
    case needsInput(String)
    case done(String?)
    case stuck(String)
}

public enum Alerts {
    public static func between(_ old: SessionState?, _ new: SessionState) -> Alert? {
        let before = old?.status
        switch new.status {
        case .needsInput where before != .needsInput || old?.needsInputMessage != new.needsInputMessage:
            return .needsInput(new.needsInputMessage ?? "Needs your input")
        case .idle where before == .running || before == .stuck:
            return .done(new.currentTurn?.lastMessage)
        case .stuck where before != .stuck:
            return .stuck(new.stuckReason ?? "No progress")
        default:
            return nil
        }
    }
}
