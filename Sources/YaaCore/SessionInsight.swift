import Foundation

/// What a tool call did, for the session detail: phases of a turn, the tool mix, the files touched.
public enum ToolKind: String, CaseIterable, Sendable {
    case explore, edit, run, verify, web, delegate, ask, other

    /// Classifies a call by its tool name and, for shells, its command (the call's summary).
    public static func of(_ name: String, summary: String = "") -> ToolKind {
        let n = bare(name)
        if Normalizer.askTools.contains(n) || n.contains("ask_user") || n == "clarify" { return .ask }
        if shells.contains(n) { return command(summary) }
        if editTools.contains(n) { return .edit }
        if readTools.contains(n) { return .explore }
        if n.contains("search") && !n.contains("web") || n.hasPrefix("grep") || n.hasPrefix("glob") { return .explore }
        if n.contains("web") || n.contains("fetch") || n.contains("browser") { return .web }
        if n.contains("agent") || n == "task" || n.hasPrefix("collaboration") || n.hasPrefix("subagent")
            || n == "sendmessage" || n.contains("workflow") { return .delegate }
        if n.hasPrefix("ctx_execute") || n.hasSuffix("execute_python") { return .run }
        return .other
    }

    /// Names that read or edit one file, whose summary is that file's path.
    public static func touchesFile(_ name: String) -> Bool {
        let n = bare(name)
        return fileTools.contains(n) || editTools.contains(n)
    }

    /// Lowercased, without an MCP server prefix (`mcp__server__tool`).
    static func bare(_ name: String) -> String {
        let n = name.lowercased()
        guard n.hasPrefix("mcp__"), let r = n.range(of: "__", options: .backwards) else { return n }
        return String(n[r.upperBound...])
    }

    static let shells: Set<String> = ["bash", "shell", "exec_command", "local_shell", "run_terminal_cmd", "shell_command",
                                      "run_shell_command", "execute_command", "terminal"]
    static let editTools: Set<String> = ["edit", "write", "multiedit", "notebookedit", "apply_patch", "str_replace",
                                         "create", "delete_file", "write_file", "edit_file", "replace", "write_code",
                                         "str_replace_editor", "create_file"]
    static let fileTools: Set<String> = ["read", "view", "read_file", "read_code", "view_image", "notebookread"]
    static let readTools: Set<String> = fileTools.union(["ls", "find", "list_dir", "list_directory", "codebase_search",
                                                         "file_search", "grep_search", "read_many_files", "glob", "grep"])

    /// A shell command: builds and tests verify, looking around explores, the rest runs.
    static func command(_ cmd: String) -> ToolKind {
        let c = " " + cmd.lowercased() + " "
        // Each part of a chain, without the wrappers in front of its command.
        let parts = cmd.lowercased().split(whereSeparator: { "|;&".contains($0) }).map { part in
            Array(part.split(separator: " ").map(String.init).drop { $0.contains("=") || wrappers.contains($0) })
        }
        // A build or test is one a part starts with (not `cat tsconfig.json`, not `rg eslint`).
        if parts.contains(where: { ws in verifyWords.contains { (" " + ws.joined(separator: " ") + " ").hasPrefix($0 + " ") } }) {
            return .verify
        }
        // Every part must only look for the whole to count as exploring.
        let words = parts.compactMap { ws -> String? in
            ws.first == "cd" ? nil : ws.first.map { ($0 as NSString).lastPathComponent }
        }
        var plain = cmd
        for quiet in ["2>&1", "2>/dev/null", ">/dev/null", "> /dev/null", "2> /dev/null", "->", "=>"] {
            plain = plain.replacingOccurrences(of: quiet, with: "")
        }
        // Writing a file through the shell is not looking.
        if plain.contains(">") || words.contains(where: ["sed", "perl"].contains) && cmd.contains(" -i") { return .run }
        if !words.isEmpty, words.allSatisfy(lookWords.contains) || words.first == "git" && gitLooks.contains(where: c.contains) {
            return .explore
        }
        return .run
    }

    static let wrappers: Set<String> = ["rtk", "bypass", "sudo", "env", "time", "npx", "bunx", "uv", "run", "poetry", "exec"]
    static let verifyWords = [" make test", " make build", " make l10n", " swift test", " swift build", " xcodebuild",
                              " pytest", " npm test", " npm run test", " npm run build", " pnpm test", " pnpm build",
                              " yarn test", " cargo test", " cargo build", " cargo check", " go test", " go build",
                              " tsc", " eslint", " ruff", " mypy", " vitest", " jest", " bun test"]
    static let lookWords: Set<String> = ["ls", "cat", "head", "tail", "grep", "rg", "find", "fd", "wc", "sed", "awk",
                                         "nl", "tree", "pwd", "file", "stat", "du", "which", "echo", "sort", "uniq",
                                         "cut", "jq", "diff", "less", "sqlite3", "ps", "lsof", "true", "xargs", "tr",
                                         "basename", "dirname", "realpath", "readlink", "date", "column", "plutil"]
    static let gitLooks = [" git status", " git log", " git diff", " git show", " git blame", " git branch", " git rev-parse", " git worktree list"]
}

extension Turn {
    /// The user wrote this prompt; the agent's harness injects the others (`<task-notification>`,
    /// `<command-name>`, ...), and an empty one is a turn the transcript didn't name.
    public var byUser: Bool { !prompt.isEmpty && !prompt.hasPrefix("<") }

    /// The prompt is a background task reporting back, not the user.
    public var reportsTask: Bool { prompt.hasPrefix("<task-notification>") }
}

/// One turn, as the detail page tells it: its tool calls in kinds and phases, failures, files edited.
public struct TurnInsight: Identifiable, Sendable {
    public var id: Int { turn.id }
    public let turn: Turn
    /// Its calls still in the session's recent tools (sub-agents' left out).
    public let tools: [ToolCall]
    /// When the user came back after it finished: the next prompt's start, if the user wrote it.
    public let followedAt: Date?
    /// When it ended (`SessionState.end(ofTurn:)`); nil while it runs.
    public let end: Date?
    /// Every call it made is still kept (its sub-agents' calls count toward `turn.toolCount`).
    public let complete: Bool
    public let failures: Int
    public let editedFiles: [String]
    public let commands: Int
    /// Consecutive calls of one kind as one stretch, in order.
    public let phases: [(kind: ToolKind, count: Int)]

    init(turn: Turn, tools: [ToolCall], subagentCalls: Int, followedAt: Date?, end: Date?) {
        self.turn = turn
        self.tools = tools
        self.followedAt = followedAt
        self.end = end
        complete = tools.count + subagentCalls >= turn.toolCount
        failures = tools.filter(\.isError).count
        editedFiles = Array(Set(tools.filter { ToolKind.of($0.name) == .edit && !$0.summary.isEmpty }.map(\.summary))).sorted()
        commands = tools.filter { ToolKind.shells.contains(ToolKind.bare($0.name)) }.count
        var out: [(kind: ToolKind, count: Int)] = []
        for t in tools {
            let k = ToolKind.of(t.name, summary: t.summary)
            if out.last?.kind == k { out[out.count - 1].count += 1 } else { out.append((k, 1)) }
        }
        phases = out
    }

    public func duration(now: Date) -> TimeInterval { max(0, (end ?? now).timeIntervalSince(turn.startedAt)) }
}

extension SessionState {
    /// Where turn `i` ended: its Stop or its last call's end, whichever is later, but never after
    /// the next prompt (an interrupt has no Stop);
    /// the last one, if never stopped, runs while the session does and else ended at its last event.
    /// Nil: still running.
    public func end(ofTurn i: Int) -> Date? {
        let t = turns[i]
        let next = i + 1 < turns.count ? turns[i + 1].startedAt : nil
        // Its calls' last end: work after an early Stop (background agents) is still the turn's.
        let last = tools.lazy
            .filter { c in (i == 0 || c.startedAt >= t.startedAt) && (next.map { c.startedAt < $0 } ?? true) }
            .compactMap { $0.endedAt ?? $0.startedAt }.max() ?? t.startedAt
        if let next { return max(t.startedAt, min(max(t.endedAt ?? next, last), next)) }
        if let e = t.endedAt { return max(t.startedAt, e, last) }
        return status == .running ? nil : max(t.startedAt, lastEventAt, last)
    }
}

/// A file the session read or edited, from its recent tool calls.
public struct FileTouch: Equatable, Sendable {
    public let path: String
    public var reads = 0
    public var edits = 0
    public var failed = 0
}

/// Everything the detail page derives from one session's state.
public struct SessionInsight: Sendable {
    public let turns: [TurnInsight]
    /// Kinds of the recent calls, most first.
    public let kinds: [(kind: ToolKind, count: Int)]
    /// Edited files first (most edits first), then files only read.
    public let files: [FileTouch]
    /// Failed calls, newest first.
    public let failures: [ToolCall]
    /// The session's recent tools no longer reach back to its first turn.
    public let truncated: Bool

    public init(_ s: SessionState) {
        let tools = s.tools.filter { $0.subagentId == nil }
        let starts = s.turns.map(\.startedAt)
        var byTurn = Array(repeating: [ToolCall](), count: s.turns.count)
        var subagent = Array(repeating: 0, count: s.turns.count)
        for t in s.tools {
            // The last turn started at or before the call.
            guard let i = starts.lastIndex(where: { $0 <= t.startedAt }) ?? (starts.isEmpty ? nil : 0) else { continue }
            if t.subagentId == nil { byTurn[i].append(t) } else { subagent[i] += 1 }
        }
        turns = s.turns.indices.map { i in
            TurnInsight(turn: s.turns[i], tools: byTurn[i], subagentCalls: subagent[i],
                        followedAt: i + 1 < s.turns.count && s.turns[i + 1].byUser ? s.turns[i + 1].startedAt : nil,
                        end: s.end(ofTurn: i))
        }
        var counts: [ToolKind: Int] = [:]
        var touch: [String: FileTouch] = [:]
        for t in tools {
            let k = ToolKind.of(t.name, summary: t.summary)
            counts[k, default: 0] += 1
            guard ToolKind.touchesFile(t.name), !t.summary.isEmpty else { continue }
            var f = touch[t.summary] ?? FileTouch(path: t.summary)
            if k == .edit { f.edits += 1 } else { f.reads += 1 }
            if t.isError { f.failed += 1 }
            touch[t.summary] = f
        }
        kinds = counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.kind.rawValue < $1.kind.rawValue }
        files = touch.values.sorted {
            ($0.edits > 0) != ($1.edits > 0) ? $0.edits > 0
                : $0.edits != $1.edits ? $0.edits > $1.edits
                : $0.reads != $1.reads ? $0.reads > $1.reads : $0.path < $1.path
        }
        failures = tools.filter(\.isError).reversed()
        truncated = s.turns.reduce(0) { $0 + $1.toolCount } > s.tools.count
    }

    /// Agent time: every turn from its prompt to its end (or now, while it runs).
    public func agentTime(now: Date) -> TimeInterval { turns.reduce(0) { $0 + $1.duration(now: now) } }
}

/// A session's states over time, for its time bar: lane spans from recorded activity, or (before
/// recording began) running spans rebuilt from its turns.
public struct SessionTimeline: Sendable {
    public struct Span: Equatable, Sendable {
        public let lane: Lane
        public let start: Date
        public let end: Date
        public var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// One stretch of the bar: a span, or a gap with nothing going on (`lane` nil). A gap or a
    /// waiting span longer than the fold is drawn at the fold's width, marked folded.
    public struct Piece: Equatable, Sendable {
        public let lane: Lane?
        public let start: Date
        public let end: Date
        public let folded: Bool
        public let weight: Double
    }

    public let spans: [Span]
    /// How long the agent waited each time the user answered it (`reply` rows), in seconds.
    public let replies: [TimeInterval]
    /// Questions and permission asks answered: a needs-input span the agent ran on from.
    public let answered: Int
    /// Rebuilt from turns: only running is known.
    public let rebuilt: Bool

    /// `inLane`: the session is still on the boards, so its last lane runs to now (as the app
    /// records it, from what it displays); by default as YaaCore sees it.
    public init(rows: [ActivityRow], session s: SessionState, now: Date, inLane: Bool? = nil) {
        let lanes = rows.filter { $0.kind == .lane }.sorted { $0.at < $1.at }
        if lanes.isEmpty {
            spans = s.turns.indices.compactMap { i in
                let t = s.turns[i], end = s.end(ofTurn: i) ?? now
                return end > t.startedAt ? Span(lane: .running, start: t.startedAt, end: end) : nil
            }
            rebuilt = true
        } else {
            var out: [Span] = []
            for (i, r) in lanes.enumerated() {
                guard let l = Lane(rawValue: r.text) else { continue }
                // The open last lane runs to now while the session is still in a lane.
                let end = i + 1 < lanes.count ? lanes[i + 1].at : inLane ?? (Activity.lane(s) != nil) ? now : max(r.at, s.lastEventAt)
                if end > r.at { out.append(Span(lane: l, start: r.at, end: end)) }
            }
            spans = out
            rebuilt = false
        }
        replies = rows.filter { $0.kind == .reply }.map(\.value)
        // An ask the user answered; not one they cut short with a new prompt (that counts as the prompt).
        let prompts = Set(s.turns.map { Int($0.startedAt.timeIntervalSince1970.rounded()) })
        answered = zip(spans, spans.dropFirst()).filter { a, b in
            let at = Int(b.start.timeIntervalSince1970.rounded())
            return a.lane == .needsInput && b.lane == .running && a.end == b.start && !(at - 2...at + 2).contains(where: prompts.contains)
        }.count
    }

    public func total(_ lane: Lane) -> TimeInterval { spans.filter { $0.lane == lane }.reduce(0) { $0 + $1.duration } }

    public var meanReply: TimeInterval? { replies.isEmpty ? nil : replies.reduce(0, +) / Double(replies.count) }

    public func pieces(fold: TimeInterval = 15 * 60) -> [Piece] {
        var out: [Piece] = []
        for (i, s) in spans.enumerated() {
            if i > 0, case let gap = s.start.timeIntervalSince(spans[i - 1].end), gap > 0 {
                out.append(Piece(lane: nil, start: spans[i - 1].end, end: s.start, folded: gap > fold, weight: min(gap, fold)))
            }
            let long = s.lane != .running && s.duration > fold
            out.append(Piece(lane: s.lane, start: s.start, end: s.end, folded: long, weight: long ? fold : s.duration))
        }
        return out
    }

    /// Where `date` falls along the bar drawn from `pieces`, 0 to 1.
    public static func fraction(_ date: Date, in pieces: [Piece]) -> Double {
        let total = pieces.reduce(0) { $0 + $1.weight }
        guard total > 0, let first = pieces.first else { return 0 }
        if date <= first.start { return 0 }
        var x = 0.0
        for p in pieces {
            if date < p.end {
                let span = p.end.timeIntervalSince(p.start)
                return (x + (span > 0 ? p.weight * max(0, date.timeIntervalSince(p.start)) / span : 0)) / total
            }
            x += p.weight
        }
        return 1
    }
}
