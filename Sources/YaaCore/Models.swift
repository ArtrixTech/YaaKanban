import Foundation

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case codex
    case cursor
    case opencode
    case pi
    case hermes
    case deepseek
    case qwen
    case droid
    case copilot
    case gemini
    case zcode
    case kiro
    case kimi
    case cline
    case omp
    case windsurf

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .opencode: return "OpenCode"
        case .pi: return "pi"
        case .hermes: return "Hermes"
        case .deepseek: return "DeepSeek"
        case .qwen: return "Qwen Code"
        case .droid: return "Droid"
        case .copilot: return "Copilot CLI"
        case .gemini: return "Gemini CLI"
        case .zcode: return "ZCode"
        case .kiro: return "Kiro CLI"
        case .kimi: return "Kimi Code"
        case .cline: return "Cline"
        case .omp: return "omp"
        case .windsurf: return "Windsurf"
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
    /// The pane or tab inside other terminals, for telling whether the user is looking at it
    /// (`TerminalFocus`): iTerm2's session UUID, the agent's tty, WezTerm's pane id, and tmux's
    /// pane id and server socket.
    public var itermSession: String?
    public var tty: String?
    public var weztermPane: String?
    public var tmuxPane: String?
    public var tmuxSocket: String?

    public init(termProgram: String? = nil, waveBlockId: String? = nil, waveTabId: String? = nil,
                waveWorkspaceId: String? = nil, waveJWT: String? = nil, itermSession: String? = nil,
                tty: String? = nil, weztermPane: String? = nil, tmuxPane: String? = nil, tmuxSocket: String? = nil) {
        self.termProgram = termProgram
        self.waveBlockId = waveBlockId
        self.waveTabId = waveTabId
        self.waveWorkspaceId = waveWorkspaceId
        self.waveJWT = waveJWT
        self.itermSession = itermSession
        self.tty = tty
        self.weztermPane = weztermPane
        self.tmuxPane = tmuxPane
        self.tmuxSocket = tmuxSocket
    }

    public init(environment env: [String: String], tty: String? = nil) {
        // Each id only when TERM_PROGRAM names its terminal: an app started from a shell there
        // (`cursor .`, another terminal) inherits them.
        let program = env["TERM_PROGRAM"]
        // ITERM_SESSION_ID is "w0t1p0:<UUID>"; AppleScript's `unique id` is the UUID.
        let iterm = program != "iTerm.app" ? nil
            : env["ITERM_SESSION_ID"].map { $0.split(separator: ":", maxSplits: 1).last.map(String.init) ?? $0 }
        // TMUX is "<socket>,<server pid>,<session>".
        let socket = program != "tmux" ? nil : env["TMUX"].flatMap { $0.split(separator: ",").first.map(String.init) }
        self.init(termProgram: program, waveBlockId: env["WAVETERM_BLOCKID"],
                  waveTabId: env["WAVETERM_TABID"], waveWorkspaceId: env["WAVETERM_WORKSPACEID"],
                  waveJWT: env["WAVETERM_JWT"], itermSession: iterm, tty: tty,
                  weztermPane: program == "WezTerm" ? env["WEZTERM_PANE"] : nil,
                  tmuxPane: socket == nil ? nil : env["TMUX_PANE"], tmuxSocket: socket)
    }

    public var isWave: Bool { waveBlockId != nil }
    public var isTabby: Bool { termProgram == "Tabby" }

    /// OSC 0: sets the tab title of the terminal it is written to (control characters dropped).
    public static func titleSequence(_ title: String) -> String {
        "\u{1b}]0;" + String(String.UnicodeScalarView(title.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7f })) + "\u{07}"
    }
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
    /// Parents of `agentPid`, nearest first, taken while the hook ran (a one-shot agent may be gone
    /// by the time the app reads it). An agent among them called this one as a tool.
    public var ancestorPids: [Int32]?

    public init(agent: AgentKind, event: String, receivedAt: Date = Date(), agentPid: Int32? = nil,
                cwd: String? = nil, terminal: TerminalContext = TerminalContext(), payload: JSONValue = .null,
                ancestorPids: [Int32]? = nil) {
        self.agent = agent
        self.event = event
        self.receivedAt = receivedAt
        self.agentPid = agentPid
        self.cwd = cwd
        self.terminal = terminal
        self.payload = payload
        self.ancestorPids = ancestorPids
    }
}

/// Agents run as tools of another agent (Claude running `codex exec` through Bash): the caller is a
/// session whose agent process is an ancestor of this one's.
public enum CallerLink {
    /// Agents whose hook process is an editor or app that also hosts its terminals; an agent started
    /// in such a terminal by hand is not called by them.
    static let hosts: Set<AgentKind> = [.cursor, .windsurf]

    /// Key of the session that called `s`, the nearest ancestor first; nil when it was not called.
    public static func caller(of s: SessionState, ancestors: [Int32], among sessions: some Collection<SessionState>) -> String? {
        guard !ancestors.isEmpty else { return nil }
        let callers = sessions.filter {
            $0.id != s.id && $0.parentId == nil && $0.status != .ended && !hosts.contains($0.agent) && $0.agentPid != nil
        }
        for pid in ancestors where pid != s.agentPid {
            // One process may host several sessions (after `/clear`); the latest one is calling.
            if let c = callers.filter({ $0.agentPid == pid }).max(by: { $0.lastEventAt < $1.lastEventAt }) { return c.id }
        }
        return nil
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
        /// Claude Code launched a background agent; the main agent may stop before it returns.
        case backgroundStart(id: String)
        /// A background agent reported back (its `<task-notification>`).
        case backgroundEnd(id: String)
        /// Status reported by a session file. Drives sessions without hooks; for hooked ones only an
        /// `.idle` newer than the last hook event counts (an interrupt fires no Stop hook).
        case statusSnapshot(SessionStatus)
        /// The agent's own name for the session (pi's `/name` or an auto title); nil clears it.
        case titleChanged(String?)
        /// Claude Code moved the conversation into a background job (`/bg`), which goes on as a
        /// session of its own; this one gets no Stop or SessionEnd.
        case parked(jobId: String)
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
    /// When it last started waiting on the user (`.needsInput`), for the reminder flash.
    public var needsInputSince: Date?
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
    /// When the user last opened the session. Looking again restarts the blue "left alone" clock.
    public var reviewedAt: Date?
    /// What the transcript says, for sessions whose turns we did not see through hooks.
    public var peek: TranscriptPeek?
    /// Token and tool totals from the transcript, when it can be read.
    public var usage: Usage?
    /// Set when the user ends the session in the panel; it stays in history but leaves the boards.
    public var dismissedAt: Date?
    /// When the user brought it back from the ended list; sessions started before then no longer
    /// count as replacing it.
    public var restoredAt: Date?
    /// A name the user gave the session in YaaKanban; it wins over every other title.
    public var customName: String?
    /// Key of the session that spawned this one as a sub-agent (pi runs them as sessions of their own).
    public var parentId: String?
    /// Background agents launched and not yet reported back; while any is out, a stopped turn
    /// is not finished. Optional so sessions stored before it decode.
    public var backgroundTasks: [String]?
    /// The background job the conversation was moved into, whose session id starts with it.
    public var parkedIn: String?

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

    /// Short name: the user's name for it, else the agent's own title, else the first prompt's first
    /// line, else the project.
    public var title: String {
        if let n = customName, !n.isEmpty { return n }
        if let t = peek?.title, !t.isEmpty { return t }
        let first = turns.first { !$0.prompt.isEmpty }?.prompt ?? peek?.lastPrompt
        if let p = first.flatMap(Self.firstLine), !p.isEmpty { return p.count > 40 ? String(p.prefix(40)) + "…" : p }
        return projectName ?? sessionId
    }

    public static func firstLine(_ s: String) -> String? {
        s.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public var groupDir: String? { projectDir ?? cwd }
    public var projectName: String? { groupDir.map { ($0 as NSString).lastPathComponent } }
    public var currentTurn: Turn? { turns.last }
    public var latestTool: ToolCall? { tools.last }
    public var runningTools: [ToolCall] { tools.filter(\.isRunning) }
    public var awaitsBackground: Bool { !(backgroundTasks ?? []).isEmpty }

    /// What the UI shows: `.idle` splits into "to review" and "done". The agent exiting is not the
    /// end for the user: only ending it on the panel is (and, in the app, outliving the retention).
    public var display: DisplayStatus {
        switch status {
        case .running: .running
        case .needsInput: .needsInput
        case .stuck: .stuck
        case .idle, .ended: dismissedAt != nil ? .ended : unreadSince == nil ? .done : .review
        }
    }

    /// Opened but never used: hooks reported the session, yet no prompt or tool came before it went
    /// quiet or exited. Such a session has nothing to show (a fresh `claude`/`pi` window, or `/new`).
    public var isUnstarted: Bool {
        hooked && turns.isEmpty && (status == .idle || status == .ended)
    }

    /// Whether `query` appears, ignoring case, in its name, project path, id, agent, prompts or replies.
    public func matches(_ query: String) -> Bool {
        let fields: [String?] = [title, cwd, projectDir, sessionId, agent.displayName, peek?.lastPrompt, peek?.lastReply]
            + turns.flatMap { [$0.prompt, $0.lastMessage] }
        return fields.contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }

    /// The agent's latest reply, from hooks or the transcript.
    public var lastReply: String? { currentTurn?.lastMessage ?? peek?.lastReply }

    /// Since when nothing has happened: the last event, or the user looking later.
    public var quietSince: Date { max(lastEventAt, reviewedAt ?? lastEventAt) }

    /// The shell command that continues this session in its own CLI, run from `cwd`.
    public var resumeCommand: String? {
        // The id comes from a hook payload: never let it read as a flag.
        guard !sessionId.isEmpty, !sessionId.hasPrefix("-") else { return nil }
        let id = shellQuote(sessionId)
        switch agent {
        case .claudeCode: return "claude --resume \(id)"
        case .codex: return "codex resume \(id)"
        case .cursor: return "cursor-agent --resume \(id)"
        case .opencode: return "opencode --session \(id)"
        // pi's session id is the session file path.
        case .pi: return "pi --session \(id)"
        case .hermes: return "hermes --resume \(id)"
        // dsh resumes sessions from its web UI, not the command line.
        case .deepseek: return nil
        case .qwen: return "qwen --resume \(id)"
        case .droid: return "droid --resume \(id)"
        case .copilot: return "copilot --resume \(id)"
        case .gemini: return "gemini --resume \(id)"
        // ZCode is a desktop app with no resume command.
        case .zcode: return nil
        case .kiro: return "kiro-cli chat --resume-id \(id)"
        case .kimi: return "kimi --session \(id)"
        case .cline: return "cline --id \(id)"
        // Like pi, omp's session id is the session file path.
        case .omp: return "omp --resume \(id)"
        // Cascade conversations are resumed inside the editor.
        case .windsurf: return nil
        }
    }

    /// How long an ended session keeps its Wave token, so it can be resumed in its tab.
    public static let waveTokenTTL: TimeInterval = 24 * 3600

    /// The Wave token is a live credential: kept while the session runs, and after it ended (or its
    /// process went, `gone`) while it may still be resumed. Dropped once the user ended it on the
    /// board, or `waveTokenTTL` after its last event (clicking the card does not extend it).
    public func dropsWaveToken(now: Date, gone: Bool = false) -> Bool {
        guard status == .ended || gone else { return false }
        return dismissedAt != nil || now.timeIntervalSince(lastEventAt) > Self.waveTokenTTL
    }
}

/// How a card asks for a second look, from how long it has been sitting.
public enum Attention {
    /// Defaults. Waiting on the user this long without being clicked: the card flashes.
    public static let flashAfter: TimeInterval = 30
    /// A reviewed turn with nothing after it starts turning blue after this long.
    public static let staleAfter: TimeInterval = 10 * 60

    /// Whether a session waiting on the user should flash: it has waited `after` since it
    /// started waiting, and the user has not clicked it since.
    public static func flashes(_ s: SessionState, acknowledged: Date?, now: Date,
                               after: TimeInterval = flashAfter) -> Bool {
        guard s.status == .needsInput, let since = s.needsInputSince else { return false }
        if let a = acknowledged, a >= since { return false }
        return now.timeIntervalSince(since) >= after
    }

    /// Default: a finished turn left unreviewed this long while the user is at the Mac flashes.
    public static let reviewFlashAfter: TimeInterval = 10 * 60

    /// Whether a finished, unreviewed turn should flash: the user has been at the Mac (`presentSince`,
    /// nil while away) for `after` since it finished, without opening it. Time away does not count.
    public static func reviewFlashes(_ s: SessionState, presentSince: Date?, now: Date,
                                     after: TimeInterval = reviewFlashAfter) -> Bool {
        guard s.display == .review, let since = s.unreadSince, let back = presentSince else { return false }
        return now.timeIntervalSince(max(since, back)) >= after
    }

    /// 0 to 1: how blue a reviewed, finished turn is, counted from `quietSince`. Rises from `after`
    /// to the middle of `after` and `linger` (when the card leaves the board), then falls back to 0.
    public static func staleness(_ s: SessionState, linger: TimeInterval, now: Date,
                                 after: TimeInterval = staleAfter) -> Double {
        guard s.display == .done, linger > after else { return 0 }
        let t = now.timeIntervalSince(s.quietSince)
        let peak = (after + linger) / 2
        let x = t < peak ? (t - after) / (peak - after) : (linger - t) / (linger - peak)
        let c = min(1, max(0, x))
        return sin(c * .pi / 2)  // visible soon after it starts, flat at the peak
    }
}

public enum DisplayStatus: Sendable {
    case needsInput, stuck, review, running, done, ended

    /// Sort order: most urgent first.
    public var rank: Int {
        switch self { case .needsInput: 0; case .stuck: 1; case .review: 2; case .running: 3; case .done: 4; case .ended: 5 }
    }
}
