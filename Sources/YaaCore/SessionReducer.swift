import Foundation

/// Pure state machine: folds agent events into session state.
public enum SessionReducer {
    public static let outputLimit = 2048
    /// How long after a turn cut short by a prompt its transcript marker may still be written.
    static let interruptSlack: TimeInterval = 5

    public static func apply(_ e: AgentEvent, to existing: SessionState?) -> SessionState {
        var s = reduce(e, existing)
        // A session the user ended comes back only when it needs them again: a new turn starts
        // or it asks for input. Finishing the turn it was in does not count.
        if s.dismissedAt != nil, let old = existing {
            let newTurn = s.turns.count > old.turns.count
            let wants = s.status == .needsInput && old.status != .needsInput
            let started = s.status == .running && old.status != .running && old.status != .stuck
            if newTurn || wants || started { s.dismissedAt = nil }
        }
        // Waiting on the user: since when, kept while it goes on waiting.
        if s.status == .needsInput {
            if existing?.status != .needsInput || s.needsInputSince == nil { s.needsInputSince = e.at }
        } else {
            s.needsInputSince = nil
        }
        return s
    }

    private static func reduce(_ e: AgentEvent, _ existing: SessionState?) -> SessionState {
        var s = existing ?? SessionState(agent: e.agent, sessionId: e.sessionId, at: e.at)
        if s.projectDir == nil { s.projectDir = e.cwd }
        if case .statusSnapshot(let status) = e.kind {
            // Session files only drive sessions without hooks; for hooked ones they must not
            // count as activity, or silence-based stuck detection would never fire. The exception:
            // going idle after our last hook event means the turn was interrupted (no Stop hook).
            if s.hooked {
                if status == .idle, s.status == .running || s.status == .stuck,
                   e.at > s.lastEventAt.addingTimeInterval(1) {
                    endTurn(&s, at: e.at, lastMessage: nil)
                }
                return s
            }
            if s.status != status { s.lastEventAt = max(s.lastEventAt, e.at) }
            s.cwd = s.cwd ?? e.cwd
            s.agentPid = s.agentPid ?? e.agentPid
            if status == .idle, s.status == .running || s.status == .stuck { s.unreadSince = e.at }
            if status == .running { s.unreadSince = nil }
            s.status = status
            return s
        }
        // Metadata, not activity: it must not reset the stuck clock or bring a dismissed card back.
        if case .titleChanged(let title) = e.kind {
            var peek = s.peek ?? TranscriptPeek()
            peek.title = title.flatMap { TranscriptPeek.clip($0) }
            s.peek = peek == TranscriptPeek() ? nil : peek
            return s
        }
        // Read from the transcript after the fact, often once the turn has ended: metadata too.
        if case .interruptSeen(let at) = e.kind {
            guard let i = s.turns.lastIndex(where: { $0.startedAt <= at }) else { return s }
            // Esc then typing at once: the prompt already ended and marked the turn before, and the
            // marker, written as the abort settles, can land just after the new turn began.
            if i > 0, s.turns[i - 1].interrupted == true, let end = s.turns[i - 1].endedAt,
               at.timeIntervalSince(end) < interruptSlack { return s }
            s.turns[i].interrupted = true
            return s
        }
        // The session file says so on every scan; only the first time counts, so a session that
        // comes back here later is not ended again.
        if case .parked(let job) = e.kind {
            guard s.parkedIn != job else { return s }
            s.parkedIn = job
            endRunningTools(&s, at: max(e.at, s.lastEventAt))
            s.subagents.removeAll()
            s.backgroundTasks = nil
            s.status = .ended
            s.unreadSince = nil
            clearAttention(&s)
            return s
        }
        // An event from before the last turn ended (spooled while the app was busy or down, replayed
        // at its next start) must not reopen the finished turn.
        if let end = s.turns.last?.endedAt, e.at < end, s.status == .idle || s.status == .ended { return s }
        s.lastEventAt = max(s.lastEventAt, e.at)
        if let v = e.cwd { s.cwd = v }
        if let v = e.transcriptPath { s.transcriptPath = v }
        // A process keeps its tty; an event sent as it exits (SessionEnd) finds none to read.
        if var v = e.terminal {
            if v.tty == nil, e.agentPid == nil || e.agentPid == s.agentPid { v.tty = s.terminal?.tty }
            s.terminal = v
        }
        // Background agents end with the process that launched them: a resumed session (a new
        // process) waits for none of the old one's, or its every stop is held for them.
        if let v = e.agentPid, let old = s.agentPid, v != old { s.backgroundTasks = nil }
        if let v = e.agentPid { s.agentPid = v }
        s.hooked = true

        switch e.kind {
        case .sessionStart:
            if s.status == .ended { s.status = .idle }

        case .promptSubmitted(let prompt):
            // A prompt while the last turn is still open: the user cut in, stopping it and typing
            // again or steering it mid-run. It ends there, or it would stay open for good. A
            // background agent's report is not the user's and belongs to the turn it lands in.
            // An answer to the agent's own question is not cutting in.
            if !prompt.hasPrefix("<task-notification>"), let i = s.turns.indices.last, s.turns[i].endedAt == nil {
                s.turns[i].endedAt = e.at
                if s.status != .needsInput { s.turns[i].interrupted = true }
            }
            s.turns.append(Turn(id: s.turns.count + 1, prompt: prompt, startedAt: e.at, toolCount: 0))
            s.status = .running
            s.unreadSince = nil
            // The previous turn's reply; the transcript scan fills in this turn's.
            s.peek?.lastReply = nil
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
            // Match the pending request by id; fall back to the tool name only when no other
            // running call of that tool could be the one waiting (parallel Bash calls).
            if let p = s.pendingPermission,
               p.id == id || (p.tool == name && !s.tools.contains { $0.isRunning && ($0.id == p.id || $0.name == name) }) {
                s.pendingPermission = nil
            }
            resume(&s)

        case .needsInput(let message):
            s.status = .needsInput
            s.needsInputMessage = message

        case .attentionNotice(let message):
            if s.status != .needsInput || s.needsInputMessage == nil { s.needsInputMessage = message }
            s.status = .needsInput

        case .inputAnswered:
            if s.status == .needsInput { s.status = .running }
            clearAttention(&s)

        case .permission(var req):
            // Claude's PermissionRequest has no tool_use_id; adopt the id of the running call with the same input.
            if let t = s.tools.last(where: { $0.isRunning && $0.name == req.tool
                                             && Normalizer.syntheticToolId($0.name, $0.input) == req.id }) {
                req.id = t.id
            }
            s.status = .needsInput
            s.pendingPermission = req
            s.needsInputMessage = "\(req.tool): \(req.summary)"

        case .turnEnd(let last):
            // Kimi sub-agents fire Stop under the parent's session id while its Agent call runs.
            if s.agent == .kimi, s.tools.contains(where: { $0.isRunning && $0.name == "Agent" }) { break }
            endTurn(&s, at: e.at, lastMessage: last)

        case .interrupted(let last):
            if s.agent == .kimi, s.tools.contains(where: { $0.isRunning && $0.name == "Agent" }) { break }
            // Arriving after the next prompt (hooks out of order): that prompt already ended the
            // stopped turn; the one now running is not it.
            if let t = s.turns.last, t.startedAt > e.at { break }
            // Only a turn still running was stopped; a later one would be a session ending idle.
            if let i = s.turns.indices.last, s.turns[i].endedAt == nil { s.turns[i].interrupted = true }
            endTurn(&s, at: e.at, lastMessage: last)

        case .sessionEnd:
            endRunningTools(&s, at: e.at)
            s.subagents.removeAll()
            s.backgroundTasks = nil
            s.status = .ended
            s.unreadSince = nil
            clearAttention(&s)

        case .subagentStart(let id, let type):
            s.subagents.append(Subagent(id: id, type: type, startedAt: e.at))
            resume(&s)

        case .subagentStop(let id):
            // An id we don't know stops the oldest; its calls end with it, or one left open reads
            // as a tool running for ever and flags the session stuck.
            var gone = id
            if let i = s.subagents.firstIndex(where: { $0.id == id }) ?? (s.subagents.isEmpty ? nil : 0) {
                gone = s.subagents.remove(at: i).id
            }
            for i in s.tools.indices where s.tools[i].isRunning && (s.tools[i].subagentId == id || s.tools[i].subagentId == gone) {
                s.tools[i].endedAt = e.at
            }

        case .backgroundStart(let id):
            if !(s.backgroundTasks ?? []).contains(id) { s.backgroundTasks = (s.backgroundTasks ?? []) + [id] }

        case .backgroundEnd(let id):
            s.backgroundTasks?.removeAll { $0 == id }
            if s.backgroundTasks?.isEmpty == true { s.backgroundTasks = nil }

        case .statusSnapshot, .titleChanged, .parked, .interruptSeen:
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

    private static func endTurn(_ s: inout SessionState, at: Date, lastMessage: String?) {
        if let i = s.turns.indices.last {
            // Held for a background agent, a later idle notice must not move the turn's end.
            if !s.awaitsBackground || s.turns[i].endedAt == nil { s.turns[i].endedAt = at }
            if let lastMessage { s.turns[i].lastMessage = lastMessage }
        }
        // The main agent stopped but a background agent is still out: the work is not done.
        // Its notification starts a new turn, and that turn's stop finishes the session.
        if s.awaitsBackground {
            for i in s.tools.indices where s.tools[i].isRunning && s.tools[i].subagentId == nil { s.tools[i].endedAt = at }
            // What is still waiting on the user now belongs to a background agent's tool; keep it.
            if s.status == .needsInput, s.runningTools.contains(where: { $0.subagentId != nil }) { return }
            clearAttention(&s)
            s.status = .running
            return
        }
        endRunningTools(&s, at: at)
        s.subagents.removeAll()
        s.status = .idle
        s.unreadSince = at
        clearAttention(&s)
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

extension Alert {
    public var isDone: Bool { if case .done = self { true } else { false } }
}

public enum Alerts {
    public static func between(_ old: SessionState?, _ new: SessionState) -> Alert? {
        let before = old?.status
        switch new.status {
        case .needsInput where before != .needsInput || old?.needsInputMessage != new.needsInputMessage:
            return .needsInput(new.needsInputMessage ?? String(localized: "Needs your input"))
        case .idle where before == .running || before == .stuck:
            // The user stopped it themselves; there is nothing to tell them.
            if new.currentTurn?.interrupted == true { return nil }
            return .done(new.currentTurn?.lastMessage)
        case .stuck where before != .stuck:
            return .stuck(new.stuckReason ?? String(localized: "No progress"))
        default:
            return nil
        }
    }
}
