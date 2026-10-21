import Foundation

/// Turns a raw hook envelope into agent-neutral events.
///
/// Claude Code and Codex share the Claude hook schema. Cursor has its own. OpenCode and pi
/// run YaaKanban's own plugin, which emits the "yaak" schema (see `Plugins.swift`).
public enum Normalizer {
    /// Payload key the CLI adds when it is blocking on a permission decision.
    public static let awaitingKey = "_yaak_awaiting"

    /// Tools that are themselves a question to the user.
    public static let askTools: Set<String> = ["askuserquestion", "request_user_input", "ask_user", "askquestion"]

    public static func normalize(_ env: HookEnvelope) -> [AgentEvent] {
        switch env.agent {
        case .claudeCode, .codex: return claudeSchema(env)
        case .cursor: return cursorSchema(env)
        case .opencode, .pi: return yaakSchema(env)
        }
    }

    // MARK: Claude Code / Codex

    static func claudeSchema(_ env: HookEnvelope) -> [AgentEvent] {
        let p = env.payload
        guard let sid = p["session_id"]?.string else { return [] }
        let subagent = p["agent_id"]?.string
        func ev(_ kind: AgentEvent.Kind) -> AgentEvent {
            AgentEvent(agent: env.agent, sessionId: sid, at: env.receivedAt, kind: kind,
                       cwd: p["cwd"]?.string ?? env.cwd, transcriptPath: p["transcript_path"]?.string,
                       agentPid: env.agentPid, terminal: env.terminal, subagentId: subagent)
        }
        let tool = p["tool_name"]?.string ?? "tool"
        let input = p["tool_input"] ?? .null
        let toolId = p["tool_use_id"]?.string ?? syntheticToolId(tool, input)

        switch p["hook_event_name"]?.string ?? env.event {
        case "SessionStart": return [ev(.sessionStart)]
        case "UserPromptSubmit": return [ev(.promptSubmitted(p["prompt"]?.string ?? ""))]
        case "PreToolUse":
            var out = [ev(.toolStart(id: toolId, name: tool, input: input))]
            if askTools.contains(tool.lowercased()) { out.append(ev(.needsInput(askText(input)))) }
            return out
        case "PostToolUse", "PostToolUseFailure":
            let resp = p["tool_response"]
            let failed = p["hook_event_name"]?.string == "PostToolUseFailure"
                || resp?["is_error"]?.bool == true || p["error"] != nil
            let text = resp.map(\.text) ?? p["error"]?.string
            return [ev(.toolEnd(id: toolId, name: tool, output: text, isError: failed))]
        case "PermissionRequest":
            // Claude routes AskUserQuestion through the permission flow; it is a question, not an approval.
            if askTools.contains(tool.lowercased()) { return [ev(.needsInput(askText(input)))] }
            let req = PermissionRequest(id: toolId, tool: tool,
                                        summary: ToolSummary.summarize(tool: tool, input: input),
                                        awaitingDecision: p[awaitingKey]?.bool == true,
                                        detail: ToolSummary.detail(tool: tool, input: input))
            return [ev(.permission(req))]
        case "Notification":
            switch p["notification_type"]?.string {
            case nil, "permission_prompt", "elicitation_dialog":
                return [ev(.attentionNotice(p["message"]?.string ?? "Needs your input"))]
            case "idle_prompt":
                // Usually follows Stop (no-op then); after an interrupt it is the only "turn over" signal.
                return [ev(.statusSnapshot(.idle))]
            default:
                return [] // auth_success and other informational types
            }
        case "Stop":
            return [ev(.turnEnd(lastMessage: p["last_assistant_message"]?.string))]
        case "SubagentStart":
            return [ev(.subagentStart(id: subagent ?? toolId, type: p["agent_type"]?.string))]
        case "SubagentStop":
            return [ev(.subagentStop(id: subagent ?? ""))]
        case "SessionEnd": return [ev(.sessionEnd)]
        default: return []
        }
    }

    // MARK: Cursor

    static func cursorSchema(_ env: HookEnvelope) -> [AgentEvent] {
        let p = env.payload
        guard let sid = p["conversation_id"]?.string ?? p["session_id"]?.string else { return [] }
        let cwd = p["workspace_roots"]?.array?.first?.string ?? env.cwd
        func ev(_ kind: AgentEvent.Kind) -> AgentEvent {
            AgentEvent(agent: .cursor, sessionId: sid, at: env.receivedAt, kind: kind, cwd: cwd,
                       transcriptPath: p["transcript_path"]?.string, agentPid: env.agentPid, terminal: env.terminal)
        }
        let tool = p["tool_name"]?.string ?? "tool"
        let input = p["tool_input"] ?? .null
        let toolId = p["tool_use_id"]?.string ?? syntheticToolId(tool, input)

        switch p["hook_event_name"]?.string ?? env.event {
        case "sessionStart": return [ev(.sessionStart)]
        case "beforeSubmitPrompt": return [ev(.promptSubmitted(p["prompt"]?.string ?? ""))]
        case "preToolUse": return [ev(.toolStart(id: toolId, name: tool, input: input))]
        case "postToolUse":
            let out = (p["tool_output"] ?? p["tool_response"]).map(\.text)
            return [ev(.toolEnd(id: toolId, name: tool, output: out, isError: false))]
        case "postToolUseFailure":
            return [ev(.toolEnd(id: toolId, name: tool, output: p["error_message"]?.string, isError: true))]
        case "stop": return [ev(.turnEnd(lastMessage: nil))]
        case "sessionEnd": return [ev(.sessionEnd)]
        default: return []
        }
    }

    // MARK: YaaKanban plugins (OpenCode, pi)

    static func yaakSchema(_ env: HookEnvelope) -> [AgentEvent] {
        let p = env.payload
        guard let sid = p["session_id"]?.string else { return [] }
        func ev(_ kind: AgentEvent.Kind) -> AgentEvent {
            AgentEvent(agent: env.agent, sessionId: sid, at: env.receivedAt, kind: kind,
                       cwd: p["cwd"]?.string ?? env.cwd, transcriptPath: p["transcript_path"]?.string,
                       agentPid: env.agentPid, terminal: env.terminal, subagentId: p["subagent_id"]?.string)
        }
        let tool = p["tool"]?.string ?? "tool"
        let input = p["input"] ?? .null
        let toolId = p["id"]?.string ?? syntheticToolId(tool, input)

        switch env.event {
        case "session_start": return [ev(.sessionStart)]
        case "prompt": return [ev(.promptSubmitted(p["prompt"]?.string ?? ""))]
        case "tool_start":
            var out = [ev(.toolStart(id: toolId, name: tool, input: input))]
            if askTools.contains(tool.lowercased()) { out.append(ev(.needsInput(askText(input)))) }
            return out
        case "tool_end":
            return [ev(.toolEnd(id: toolId, name: tool, output: p["output"]?.text, isError: p["is_error"]?.bool == true))]
        case "permission":
            let summary = p["title"]?.string ?? ToolSummary.summarize(tool: tool, input: input)
            return [ev(.permission(PermissionRequest(id: toolId, tool: tool, summary: summary,
                                                     awaitingDecision: p[awaitingKey]?.bool == true,
                                                     detail: ToolSummary.detail(tool: tool, input: input))))]
        case "needs_input": return [ev(.needsInput(p["message"]?.string ?? "Needs your input"))]
        case "input_answered": return [ev(.inputAnswered)]
        case "turn_end": return [ev(.turnEnd(lastMessage: p["message"]?.string))]
        case "session_end": return [ev(.sessionEnd)]
        case "title": return [ev(.titleChanged(p["title"]?.string))]
        default: return []
        }
    }

    // MARK: helpers

    /// Stable across processes (pre and post hooks run in different `yaak` processes).
    static func syntheticToolId(_ tool: String, _ input: JSONValue) -> String { syntheticToolId(tool, input.text) }

    /// Same id from the stored `ToolCall.input` text.
    static func syntheticToolId(_ tool: String, _ inputText: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in inputText.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return "\(tool):\(String(h, radix: 16))"
    }

    static func askText(_ input: JSONValue) -> String {
        if let qs = input["questions"]?.array, let q = qs.first?["question"]?.string {
            return qs.count > 1 ? "\(q)（共 \(qs.count) 个问题）" : q
        }
        return input["question"]?.string ?? input["prompt"]?.string ?? "Agent asked a question"
    }
}
