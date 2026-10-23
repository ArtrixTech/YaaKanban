import Foundation

/// Turns a raw hook envelope into agent-neutral events.
///
/// Claude Code, Codex, DeepSeek dsh (through its Claude hooks bridge), Qwen Code, Droid, ZCode and Kiro CLI
/// share the Claude hook schema; Gemini CLI, Copilot CLI and Kimi Code are renamed into it. Cursor and Hermes have their own. OpenCode and pi
/// run YaaKanban's own plugin, which emits the "yaak" schema (see `Plugins.swift`).
public enum Normalizer {
    /// Payload key the CLI adds when it is blocking on a permission decision.
    public static let awaitingKey = "_yaak_awaiting"

    /// Tools that are themselves a question to the user.
    public static let askTools: Set<String> = ["askuserquestion", "request_user_input", "ask_user", "askquestion"]

    public static func normalize(_ env: HookEnvelope) -> [AgentEvent] {
        switch env.agent {
        case .claudeCode, .codex, .deepseek, .qwen, .droid, .kiro: return claudeSchema(env)
        case .zcode: return claudeSchema(withoutTranscript(env))
        case .gemini: return claudeSchema(geminiAsClaude(env))
        case .copilot: return claudeSchema(copilotAsClaude(env))
        case .kimi: return kimiSchema(env)
        case .hermes: return hermesSchema(env)
        case .cursor: return cursorSchema(env)
        case .opencode, .pi: return yaakSchema(env)
        }
    }

    // MARK: Claude Code / Codex

    static func claudeSchema(_ env: HookEnvelope) -> [AgentEvent] {
        let p = env.payload
        guard let sid = p["session_id"]?.string else { return [] }
        if isCodexBackground(env.agent, transcriptPath: p["transcript_path"]?.string) { return [] }
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
        case "UserPromptSubmit":
            let prompt = p["prompt"]?.string ?? ""
            return [ev(.promptSubmitted(prompt))] + notifiedTasks(prompt).map { ev(.backgroundEnd(id: $0)) }
        case "PreToolUse":
            var out = [ev(.toolStart(id: toolId, name: tool, input: input))]
            if askTools.contains(tool.lowercased()) { out.append(ev(.needsInput(askText(input)))) }
            return out
        case "PostToolUse", "PostToolUseFailure":
            let resp = p["tool_response"]
            let failed = p["hook_event_name"]?.string == "PostToolUseFailure"
                || resp?["is_error"]?.bool == true || p["error"] != nil
            let text = resp.map(\.text) ?? p["error"]?.string
            var out = [ev(.toolEnd(id: toolId, name: tool, output: text, isError: failed))]
            // Only the main agent's: a sub-agent's own background children report to it, not to us.
            // A resumed agent (SendMessage) notifies again under the same id.
            if env.agent == .claudeCode, subagent == nil, let id = backgroundLaunch(tool, resp) {
                out.append(ev(.backgroundStart(id: id)))
            }
            return out
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

    /// The Codex app runs its own model calls (next-message suggestions, their safety check,
    /// memory consolidation) as threads that fire hooks but have no rollout file. A user's thread,
    /// and its sub-agents, always have one.
    public static func isCodexBackground(_ agent: AgentKind, transcriptPath: String?) -> Bool {
        agent == .codex && (transcriptPath ?? "").isEmpty
    }

    static func backgroundLaunch(_ tool: String, _ resp: JSONValue?) -> String? {
        switch tool.lowercased() {
        case "agent", "task": return resp?["isAsync"]?.bool == true ? resp?["agentId"]?.string : nil
        case "sendmessage": return resp?["success"]?.bool == true ? resp?["resumedAgentId"]?.string : nil
        default: return nil
        }
    }

    /// Claude Code tells the main agent a background task stopped by sending it a prompt that
    /// starts with `<task-notification>`; returns the task ids it names.
    static func notifiedTasks(_ prompt: String) -> [String] {
        guard prompt.hasPrefix("<task-notification>") else { return [] }
        return prompt.components(separatedBy: "<task-id>").dropFirst().compactMap { part in
            part.range(of: "</task-id>").map { String(part[..<$0.lowerBound]).trimmingCharacters(in: .whitespaces) }
        }
    }

    // MARK: Gemini CLI / Copilot CLI (renamed into the Claude schema)

    /// Gemini's events carry Claude's fields under its own event names.
    static func geminiAsClaude(_ env: HookEnvelope) -> HookEnvelope {
        guard var o = env.payload.object else { return env }
        let names = ["BeforeAgent": "UserPromptSubmit", "BeforeTool": "PreToolUse", "AfterTool": "PostToolUse",
                     "AfterAgent": "Stop"]
        let event = o["hook_event_name"]?.string ?? env.event
        o["hook_event_name"] = .string(names[event] ?? event)
        switch event {
        case "AfterTool":
            // tool_response is {llmContent, returnDisplay, error?}; returnDisplay may be a diff object.
            let r = o["tool_response"]
            if let err = r?["error"], err != .null { o["error"] = err["message"] ?? .string(err.text) }
            o["tool_response"] = r?["llmContent"]?.string.map(JSONValue.string) ?? r?["returnDisplay"] ?? r?["llmContent"]
        case "AfterAgent":
            o["last_assistant_message"] = o["prompt_response"]
        case "Notification":
            // The only type today is ToolPermission: the user is being asked to confirm a tool.
            o["notification_type"] = .string("permission_prompt")
        default: break
        }
        var e = env
        e.payload = .object(o)
        return e
    }

    /// Copilot's camelCase hooks: `sessionId`, `toolName`, `toolArgs` (a JSON string), `toolResult`.
    static func copilotAsClaude(_ env: HookEnvelope) -> HookEnvelope {
        guard var o = env.payload.object else { return env }
        let names = ["sessionStart": "SessionStart", "sessionEnd": "SessionEnd", "userPromptSubmitted": "UserPromptSubmit",
                     "preToolUse": "PreToolUse", "postToolUse": "PostToolUse", "postToolUseFailure": "PostToolUseFailure",
                     "permissionRequest": "PermissionRequest", "agentStop": "Stop", "notification": "Notification"]
        let event = o["hook_event_name"]?.string ?? env.event
        o["hook_event_name"] = .string(names[event] ?? event)
        for (camel, snake) in [("sessionId", "session_id"), ("transcriptPath", "transcript_path"), ("toolName", "tool_name"),
                               ("toolUseId", "tool_use_id"), ("toolCallId", "tool_use_id"),
                               ("notificationType", "notification_type"), ("workingDirectory", "cwd")] where o[snake] == nil {
            o[snake] = o[camel]
        }
        if o["tool_input"] == nil, let args = o["toolArgs"] {
            o["tool_input"] = args.string.flatMap { JSONValue.parse(Data($0.utf8)) } ?? args
        }
        if o["tool_response"] == nil, let r = o["toolResult"] {
            o["tool_response"] = r["textResultForLlm"] ?? r
            if ["failure", "error", "denied", "rejected"].contains(r["resultType"]?.string ?? "") {
                o["hook_event_name"] = .string("PostToolUseFailure")
            }
        }
        if case .object(let err)? = o["error"] { o["error"] = err["message"] ?? .string("error") }
        var e = env
        e.payload = .object(o)
        return e
    }

    /// ZCode's `transcript_path` is a temporary file it deletes after the hook runs.
    static func withoutTranscript(_ env: HookEnvelope) -> HookEnvelope {
        guard var o = env.payload.object else { return env }
        o["transcript_path"] = nil
        var e = env
        e.payload = .object(o)
        return e
    }

    // MARK: Kimi Code

    /// Kimi's external hooks use Claude's event names with `tool_call_id`, `tool_output` and an error
    /// object. Its PermissionRequest is fire-and-forget; PermissionResult reports the user's answer.
    static func kimiSchema(_ env: HookEnvelope) -> [AgentEvent] {
        guard var o = env.payload.object else { return [] }
        let event = o["hook_event_name"]?.string ?? env.event
        switch event {
        case "PermissionResult":
            guard let sid = o["session_id"]?.string else { return [] }
            return [AgentEvent(agent: .kimi, sessionId: sid, at: env.receivedAt, kind: .inputAnswered,
                               cwd: o["cwd"]?.string ?? env.cwd, transcriptPath: nil,
                               agentPid: env.agentPid, terminal: env.terminal)]
        // Sub-agent events carry only a name; it pairs start with stop well enough for display.
        case "SubagentStart", "SubagentStop":
            o["agent_id"] = o["agent_name"]
            o["agent_type"] = o["agent_name"]
            o["hook_event_name"] = .string(event)
        // An interrupted or failed turn fires these instead of Stop.
        case "Interrupt", "StopFailure": o["hook_event_name"] = .string("Stop")
        default: o["hook_event_name"] = .string(event)
        }
        // The prompt is a list of content parts; keep the text ones.
        if case .array(let parts)? = o["prompt"] {
            let text = parts.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }
            o["prompt"] = .string(text.joined(separator: " "))
        }
        if o["tool_use_id"] == nil { o["tool_use_id"] = o["tool_call_id"] }
        if o["tool_response"] == nil { o["tool_response"] = o["tool_output"] }
        if case .object(let err)? = o["error"] { o["error"] = err["message"] ?? .string("error") }
        o[awaitingKey] = nil
        var e = env
        e.payload = .object(o)
        return claudeSchema(e)
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

    // MARK: Hermes

    /// Hermes shell hooks: `{hook_event_name, session_id, tool_name, tool_input, cwd, extra}`, the
    /// event's other arguments in `extra`.
    static func hermesSchema(_ env: HookEnvelope) -> [AgentEvent] {
        let p = env.payload
        guard let sid = p["session_id"]?.string, !sid.isEmpty else { return [] }
        let x = p["extra"] ?? .null
        func ev(_ kind: AgentEvent.Kind) -> AgentEvent {
            AgentEvent(agent: .hermes, sessionId: sid, at: env.receivedAt, kind: kind,
                       cwd: p["cwd"]?.string ?? env.cwd, transcriptPath: nil, agentPid: env.agentPid, terminal: env.terminal)
        }
        let tool = p["tool_name"]?.string ?? "tool"
        let input = p["tool_input"] ?? .null
        let toolId = x["tool_call_id"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? syntheticToolId(tool, input)

        switch p["hook_event_name"]?.string ?? env.event {
        case "pre_llm_call":
            var out = x["is_first_turn"]?.bool == true ? [ev(.sessionStart)] : []
            out.append(ev(.promptSubmitted(x["user_message"]?.string ?? "")))
            return out
        case "pre_tool_call":
            var out = [ev(.toolStart(id: toolId, name: tool, input: input))]
            if tool == "clarify" || askTools.contains(tool.lowercased()) { out.append(ev(.needsInput(askText(input)))) }
            return out
        case "post_tool_call":
            let status = x["status"]?.string ?? "ok"
            let output = status == "ok" ? x["result"].map(\.text) : (x["error_message"]?.string ?? x["result"].map(\.text))
            return [ev(.toolEnd(id: toolId, name: tool, output: output, isError: status != "ok"))]
        case "post_llm_call": return [ev(.turnEnd(lastMessage: x["assistant_response"]?.string))]
        // Ends every turn, interrupted ones included; post_llm_call may already have carried the reply.
        case "on_session_end": return [ev(.turnEnd(lastMessage: nil))]
        case "on_session_finalize": return [ev(.sessionEnd)]
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
