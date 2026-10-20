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
}

@Suite struct Stuck {
    let cfg = StuckConfig(silence: 300, toolDuration: 300)

    func running(tool: String? = nil, input: String = "{}", at: TimeInterval = 0, pid: Int32? = nil) -> SessionState {
        var s = SessionState(agent: .claudeCode, sessionId: "s", at: t0)
        s.status = .running
        s.agentPid = pid
        s.lastEventAt = t0.addingTimeInterval(at)
        if let tool {
            s.tools = [ToolCall(id: "1", name: tool, summary: "", input: input, output: nil, isError: false, startedAt: t0.addingTimeInterval(at))]
        }
        return s
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
        #expect(StuckDetector.evaluate(idle, now: t0, config: cfg, isAlive: { _ in false })?.status == .ended)
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
