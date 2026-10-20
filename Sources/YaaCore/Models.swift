import Foundation

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case codex
    case cursor
    case opencode
    case pi

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .opencode: return "OpenCode"
        case .pi: return "pi"
        }
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case running, needsInput = "needs_input", stuck, idle, ended

    /// Sessions in these states want the user's attention.
    public var needsAttention: Bool { self == .needsInput || self == .stuck }
}

/// Where the agent runs, captured from the hook process environment.
public struct TerminalContext: Codable, Equatable, Sendable {
    public var termProgram: String?
    public var waveBlockId: String?
    public var waveTabId: String?
    public var waveWorkspaceId: String?
    public var waveJWT: String?

    public init(termProgram: String? = nil, waveBlockId: String? = nil, waveTabId: String? = nil,
                waveWorkspaceId: String? = nil, waveJWT: String? = nil) {
        self.termProgram = termProgram
        self.waveBlockId = waveBlockId
        self.waveTabId = waveTabId
        self.waveWorkspaceId = waveWorkspaceId
        self.waveJWT = waveJWT
    }

    public init(environment env: [String: String]) {
        self.init(termProgram: env["TERM_PROGRAM"], waveBlockId: env["WAVETERM_BLOCKID"],
                  waveTabId: env["WAVETERM_TABID"], waveWorkspaceId: env["WAVETERM_WORKSPACEID"],
                  waveJWT: env["WAVETERM_JWT"])
    }

    public var isWave: Bool { waveBlockId != nil }
}

/// What a hook invocation sends to the app: the raw agent payload plus local context.
public struct HookEnvelope: Codable, Equatable, Sendable {
    public var agent: AgentKind
    public var event: String
    public var receivedAt: Date
    public var agentPid: Int32?
    public var cwd: String?
    public var terminal: TerminalContext
    public var payload: JSONValue

    public init(agent: AgentKind, event: String, receivedAt: Date = Date(), agentPid: Int32? = nil,
                cwd: String? = nil, terminal: TerminalContext = TerminalContext(), payload: JSONValue = .null) {
        self.agent = agent
        self.event = event
        self.receivedAt = receivedAt
        self.agentPid = agentPid
        self.cwd = cwd
        self.terminal = terminal
        self.payload = payload
    }
}

public struct PermissionRequest: Codable, Equatable, Sendable {
    public var id: String
    public var tool: String
    public var summary: String
    /// True when the hook is blocked waiting for a decision from the app.
    public var awaitingDecision: Bool
    /// Full input text, set only when `summary` does not show all of it (multi-line or long).
    public var detail: String?

    public init(id: String, tool: String, summary: String, awaitingDecision: Bool, detail: String? = nil) {
        self.id = id
        self.tool = tool
        self.summary = summary
        self.awaitingDecision = awaitingDecision
        self.detail = detail
    }

    /// The summary hides part of what would be approved.
    public var isTruncated: Bool { detail != nil }
}

/// Agent-neutral event produced by a normalizer from a `HookEnvelope`.
public struct AgentEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case sessionStart
        case promptSubmitted(String)
        case toolStart(id: String, name: String, input: JSONValue)
        case toolEnd(id: String, name: String, output: String?, isError: Bool)
        case needsInput(String)
        /// A generic "waiting for you" notice; never replaces a specific question already shown.
        case attentionNotice(String)
        /// The user answered a prompt that was blocking the agent.
        case inputAnswered
        case permission(PermissionRequest)
        case turnEnd(lastMessage: String?)
        case sessionEnd
        case subagentStart(id: String, type: String?)
        case subagentStop(id: String)
        /// Status reported by a session file. Drives sessions without hooks; for hooked ones only an
        /// `.idle` newer than the last hook event counts (an interrupt fires no Stop hook).
        case statusSnapshot(SessionStatus)
    }

    public var agent: AgentKind
    public var sessionId: String
    public var at: Date
    public var kind: Kind
    public var cwd: String?
    public var transcriptPath: String?
    public var agentPid: Int32?
    public var terminal: TerminalContext?
    /// Set when the event originated inside a sub-agent.
    public var subagentId: String?

    public init(agent: AgentKind, sessionId: String, at: Date, kind: Kind, cwd: String? = nil,
                transcriptPath: String? = nil, agentPid: Int32? = nil, terminal: TerminalContext? = nil,
                subagentId: String? = nil) {
        self.agent = agent
        self.sessionId = sessionId
        self.at = at
        self.kind = kind
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.agentPid = agentPid
        self.terminal = terminal
        self.subagentId = subagentId
    }
}

public struct ToolCall: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var input: String
    public var output: String?
    public var isError: Bool
    public var startedAt: Date
    public var endedAt: Date?
    /// Set when the call ran inside a sub-agent.
    public var subagentId: String?

    public var isRunning: Bool { endedAt == nil }
}

public struct Turn: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var prompt: String
    public var startedAt: Date
    public var endedAt: Date?
    public var toolCount: Int
    public var lastMessage: String?
}

public struct Subagent: Codable, Equatable, Sendable {
    public var id: String
    public var type: String?
    public var startedAt: Date
}

public struct SessionState: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(agent.rawValue):\(sessionId)" }
    public var agent: AgentKind
    public var sessionId: String
    public var cwd: String?
    /// The cwd the session was first seen in; sessions are grouped by it (`cwd` follows `cd`).
    public var projectDir: String?
    public var transcriptPath: String?
    public var agentPid: Int32?
    public var terminal: TerminalContext?
    public var status: SessionStatus
    public var stuckReason: String?
    public var needsInputMessage: String?
    public var pendingPermission: PermissionRequest?
    public var startedAt: Date
    public var lastEventAt: Date
    public var turns: [Turn]
    /// Most recent tool calls, newest last, capped at `SessionState.toolHistoryLimit`.
    public var tools: [ToolCall]
    public var subagents: [Subagent]
    /// True once a real hook event was seen; false for sessions discovered by scanning only.
    public var hooked: Bool
    /// Set when a turn finishes; cleared once the user looks at the session or sends a new prompt.
    public var unreadSince: Date?
    /// What the transcript says, for sessions whose turns we did not see through hooks.
    public var peek: TranscriptPeek?
    /// Token and tool totals from the transcript, when it can be read.
    public var usage: Usage?
    /// Set when the user ends the session in the panel; it stays in history but leaves the boards.
    public var dismissedAt: Date?

    public static let toolHistoryLimit = 200

    public init(agent: AgentKind, sessionId: String, at: Date) {
        self.agent = agent
        self.sessionId = sessionId
        self.status = .idle
        self.startedAt = at
        self.lastEventAt = at
        self.turns = []
        self.tools = []
        self.subagents = []
        self.hooked = false
    }

    /// Short name: the agent's own title, else the first prompt's first line, else the project.
    public var title: String {
        if let t = peek?.title, !t.isEmpty { return t }
        let first = turns.first { !$0.prompt.isEmpty }?.prompt ?? peek?.lastPrompt
        if let p = first.flatMap(Self.firstLine), !p.isEmpty { return p.count > 40 ? String(p.prefix(40)) + "…" : p }
        return projectName ?? sessionId
    }

    static func firstLine(_ s: String) -> String? {
        s.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public var groupDir: String? { projectDir ?? cwd }
    public var projectName: String? { groupDir.map { ($0 as NSString).lastPathComponent } }
    public var currentTurn: Turn? { turns.last }
    public var latestTool: ToolCall? { tools.last }
    public var runningTools: [ToolCall] { tools.filter(\.isRunning) }

    /// What the UI shows: `.idle` splits into "to review" and "done".
    public var display: DisplayStatus {
        switch status {
        case .running: .running
        case .needsInput: .needsInput
        case .stuck: .stuck
        case .idle: unreadSince == nil ? .done : .review
        case .ended: .ended
        }
    }

    /// The agent's latest reply, from hooks or the transcript.
    public var lastReply: String? { currentTurn?.lastMessage ?? peek?.lastReply }
}

public enum DisplayStatus: Sendable {
    case needsInput, stuck, review, running, done, ended

    /// Sort order: most urgent first.
    public var rank: Int {
        switch self { case .needsInput: 0; case .stuck: 1; case .review: 2; case .running: 3; case .done: 4; case .ended: 5 }
    }
}
