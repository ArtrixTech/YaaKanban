import Foundation

/// Event schema a custom agent sends to `yaak hook custom`.
public enum CustomAgentProtocol: String, Codable, CaseIterable, Sendable {
    /// YaaKanban's neutral JSON / CLI schema (`session_start`, `prompt`, `tool_start`, `tool_end`,
    /// `permission`, `needs_input`, `input_answered`, `turn_end`, `session_end`, `title`).
    case generic
    /// Claude Code hooks schema (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
    /// `PermissionRequest`, `Notification`, `Stop`, `SubagentStart`, `SubagentStop`, `SessionEnd`).
    case claude
}

/// Accent color choice for a custom agent's monogram or symbol icon.
public enum CustomAgentColor: String, Codable, CaseIterable, Sendable {
    case auto, slate, blue, indigo, purple, pink, red, orange, amber, green, teal, cyan

    /// Concrete palette colors used for deterministic `.auto` assignment.
    public static let palette: [CustomAgentColor] = [
        .blue, .indigo, .purple, .pink, .red, .orange, .amber, .green, .teal, .cyan
    ]

    /// Picks a stable color for `id` when set to `.auto`.
    public func resolved(for id: String) -> CustomAgentColor {
        guard self == .auto else { return self }
        var h: UInt64 = 0xcbf29ce484222325
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Self.palette[Int(h % UInt64(Self.palette.count))]
    }
}

/// Visual icon specification for a custom agent.
public struct CustomAgentIcon: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case monogram, symbol, image
    }

    public var kind: Kind
    /// For `.monogram`: optional 1–2 char override. For `.symbol`: SF Symbol name.
    /// For `.image`: filename inside `Paths.customAgentIcons`.
    public var value: String?
    public var color: CustomAgentColor

    public init(kind: Kind = .monogram, value: String? = nil, color: CustomAgentColor = .auto) {
        self.kind = kind
        self.value = value
        self.color = color
    }

    private enum CodingKeys: String, CodingKey { case kind, value, color }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .monogram
        value = try c.decodeIfPresent(String.self, forKey: .value)
        color = try c.decodeIfPresent(CustomAgentColor.self, forKey: .color) ?? .auto
    }
}

/// A distinct agent for grouping and filtering in the UI (built-in kind, or `.custom` + its slug).
public struct AgentIdentity: Hashable, Codable, Sendable {
    public var kind: AgentKind
    public var customId: String?

    public init(_ kind: AgentKind, customId: String? = nil) {
        self.kind = kind
        if kind == .custom, let cid = customId, !cid.isEmpty {
            self.customId = cid
        } else {
            self.customId = nil
        }
    }

    /// Parses a `SessionState.id` key (`<agent>:<session>` or `custom:<customId>:<session>`).
    public static func from(sessionKey id: String) -> AgentIdentity? {
        let parts = id.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard let first = parts.first, let kind = AgentKind(rawValue: String(first)) else { return nil }
        if kind == .custom, parts.count == 3, !parts[1].isEmpty {
            return AgentIdentity(.custom, customId: String(parts[1]))
        }
        return AgentIdentity(kind)
    }
}

/// Configuration for a user-defined agent integrated through `yaak hook custom`.
public struct CustomAgent: Codable, Equatable, Identifiable, Sendable {
    public static let maxIdLength = 64

    /// Canonical slug used in `--id <id>` and session keys (e.g. `"my-agent"`).
    public var id: String
    /// Human-readable name shown in the UI.
    public var name: String
    /// Event protocol expected from this agent's hooks.
    public var `protocol`: CustomAgentProtocol
    /// Whether permission events block waiting for Allow/Deny from YaaKanban.
    public var supportsApproval: Bool
    /// Optional shell template for resuming a session, e.g. `myagent --resume {session_id}`.
    public var resumeCommandTemplate: String?
    public var icon: CustomAgentIcon
    public var createdAt: Date?

    public init(id: String, name: String, protocol: CustomAgentProtocol = .generic,
                supportsApproval: Bool = true, resumeCommandTemplate: String? = nil,
                icon: CustomAgentIcon = CustomAgentIcon(), createdAt: Date? = Date()) {
        self.id = id
        self.name = name
        self.protocol = `protocol`
        self.supportsApproval = supportsApproval
        self.resumeCommandTemplate = resumeCommandTemplate
        self.icon = icon
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, `protocol`, supportsApproval, resumeCommandTemplate, icon, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        `protocol` = try c.decodeIfPresent(CustomAgentProtocol.self, forKey: .protocol) ?? .generic
        supportsApproval = try c.decodeIfPresent(Bool.self, forKey: .supportsApproval) ?? true
        resumeCommandTemplate = try c.decodeIfPresent(String.self, forKey: .resumeCommandTemplate)
        icon = try c.decodeIfPresent(CustomAgentIcon.self, forKey: .icon) ?? CustomAgentIcon()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    /// Normalizes arbitrary user text into a safe slug (`[a-z0-9][a-z0-9._-]*`).
    public static func sanitizeId(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = ""
        var prevDash = false
        for scalar in lowered.unicodeScalars {
            let v = scalar.value
            let isAlnum = (v >= 0x30 && v <= 0x39) || (v >= 0x61 && v <= 0x7A)
            let isPunct = v == 0x2D || v == 0x5F || v == 0x2E // - _ .
            if isAlnum {
                out.append(Character(scalar))
                prevDash = false
            } else if isPunct {
                if !out.isEmpty {
                    out.append(Character(scalar))
                    prevDash = (v == 0x2D)
                }
            } else if !out.isEmpty && !prevDash {
                out.append("-")
                prevDash = true
            }
        }
        while out.contains("..") { out = out.replacingOccurrences(of: "..", with: ".") }
        while out.hasSuffix("-") || out.hasSuffix(".") || out.hasSuffix("_") { out.removeLast() }
        if out.count > maxIdLength { out = String(out.prefix(maxIdLength)) }
        while out.hasSuffix("-") || out.hasSuffix(".") || out.hasSuffix("_") { out.removeLast() }
        return out
    }

    /// Valid slug: non-empty, <= 64 chars, starts with `[a-z0-9]`, contains only `[a-z0-9._-]`, never `..`.
    public static func isValidId(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= maxIdLength, !id.contains("..") else { return false }
        var first = true
        for scalar in id.unicodeScalars {
            let v = scalar.value
            let isAlnum = (v >= 0x30 && v <= 0x39) || (v >= 0x61 && v <= 0x7A)
            let isPunct = v == 0x2D || v == 0x5F || v == 0x2E
            if first {
                guard isAlnum else { return false }
                first = false
            } else {
                guard isAlnum || isPunct else { return false }
            }
        }
        return true
    }

    /// 1–2 uppercase characters for monogram rendering.
    public var monogram: String {
        if icon.kind == .monogram, let custom = icon.value?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return String(custom.prefix(2)).uppercased()
        }
        return Self.monogram(from: name.isEmpty ? id : name)
    }

    public static func monogram(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        // Non-ASCII leading character (e.g. CJK): a single character reads cleanest at small sizes.
        if !first.isASCII { return String(first) }
        let words = trimmed.split { $0.isWhitespace || $0 == "-" || $0 == "_" || $0 == "." }
        if words.count >= 2, let a = words[0].first, let b = words[1].first {
            return String([a, b]).uppercased()
        }
        return String(trimmed.prefix(2)).uppercased()
    }

    /// Expands `resumeCommandTemplate` for `sessionId`, shell-quoting the id.
    public func resumeCommand(sessionId: String) -> String? {
        guard !sessionId.isEmpty, !sessionId.hasPrefix("-") else { return nil }
        guard let tpl = resumeCommandTemplate?.trimmingCharacters(in: .whitespacesAndNewlines), !tpl.isEmpty else {
            return nil
        }
        let quoted = shellQuote(sessionId)
        return tpl
            .replacingOccurrences(of: "{session_id}", with: quoted)
            .replacingOccurrences(of: "{id}", with: quoted)
    }

    /// Fallback display name for an unregistered custom agent id.
    public static func defaultDisplayName(for id: String?) -> String {
        if let id, !id.isEmpty { return id }
        return AgentKind.custom.displayName
    }

    /// Short CLI / hook configuration snippet for quick copy in Settings.
    public func hookSnippet(yaakPath: String) -> String {
        let bin = shellQuote(yaakPath)
        switch `protocol` {
        case .generic:
            var lines = [
                "# Start a turn (stdin JSON or CLI flags):",
                "echo '{\"session_id\":\"s1\",\"prompt\":\"Fix bug\"}' | \(bin) hook custom prompt --id \(id)",
                "# Tool start & end:",
                "echo '{\"session_id\":\"s1\",\"id\":\"t1\",\"tool\":\"bash\",\"input\":{\"command\":\"ls\"}}' | \(bin) hook custom tool_start --id \(id)",
                "echo '{\"session_id\":\"s1\",\"id\":\"t1\",\"tool\":\"bash\",\"output\":\"ok\"}' | \(bin) hook custom tool_end --id \(id)",
            ]
            if supportsApproval {
                lines.append("# Blocking approval (prints 'allow' or 'deny', or empty on timeout):")
                lines.append("DECISION=$(echo '{\"session_id\":\"s1\",\"id\":\"t2\",\"tool\":\"bash\",\"input\":{\"command\":\"rm -rf build\"}}' | \(bin) hook custom permission --id \(id))")
            }
            lines.append("# Finish a turn:")
            lines.append("echo '{\"session_id\":\"s1\",\"message\":\"All done\"}' | \(bin) hook custom turn_end --id \(id)")
            return lines.joined(separator: "\n")

        case .claude:
            var events: [(String, Int)] = [
                ("SessionStart", 5), ("UserPromptSubmit", 5), ("PreToolUse", 5),
                ("PostToolUse", 5), ("PostToolUseFailure", 5), ("Notification", 5),
                ("Stop", 5), ("SubagentStart", 5), ("SubagentStop", 5), ("SessionEnd", 5),
            ]
            if supportsApproval { events.append(("PermissionRequest", 35)) }
            let entries = events.map { ev, timeout in
                """
                  "\(ev)": [{
                    "hooks": [{ "type": "command", "command": "\(yaakPath) hook custom \(ev) --id \(id) --format claude", "timeout": \(timeout) }]
                  }]
                """
            }.joined(separator: ",\n")
            return "{\n  \"hooks\": {\n\(entries)\n  }\n}"
        }
    }

    /// Copy-pasteable prompt for any AI coding assistant to wire up this custom agent automatically.
    public func aiPrompt(yaakPath: String) -> String {
        let bin = yaakPath
        switch `protocol` {
        case .generic:
            let approvalDoc = supportsApproval
                ? """
                - `permission`: blocking approval request. Payload: `{"session_id": "...", "id": "<tool_id>", "tool": "<name>", "input": {...}, "title": "<optional summary>"}`.
                  Stdout prints `allow` or `deny` if the user responds in YaaKanban, or empty on timeout (fall back to asking in the terminal). Always exits 0.
                """
                : """
                - `permission` (notify-only): pass `--no-wait` if you only want to notify YaaKanban without waiting for a decision.
                """
            return """
            Please integrate this agent ("\(name)", custom id: `\(id)`) with YaaKanban so YaaKanban can track its session status, tools, notifications, and terminal jumping.

            ## How YaaKanban receives events
            Call the local CLI `\(bin)` as a child process inside the agent's own runtime environment (so YaaKanban automatically inherits `cwd`, PID, and terminal context for jump-to-terminal):

            ```sh
            \(bin) hook custom <event> --id \(id)
            ```

            Pass a JSON object on stdin (or use lightweight CLI flags like `--session`, `--prompt`, `--tool`, `--tool-id`, `--input`, `--output`, `--message`, `--title`, `--cwd`, `--error`, `--interrupted`).

            ## Supported events (`<event>`)
            - `session_start`: `{"session_id": "...", "cwd": "..."}`
            - `prompt`: `{"session_id": "...", "prompt": "<user prompt>"}`
            - `tool_start`: `{"session_id": "...", "id": "<call_id>", "tool": "<tool_name>", "input": {...}}`
            - `tool_end`: `{"session_id": "...", "id": "<call_id>", "tool": "<tool_name>", "output": "<text>", "is_error": false}`
            - `needs_input`: `{"session_id": "...", "message": "<question for user>"}`
            - `input_answered`: `{"session_id": "..."}`
            \(approvalDoc)
            - `turn_end`: `{"session_id": "...", "message": "<assistant final reply>", "interrupted": false}`
            - `subagent_start` / `subagent_stop`: `{"session_id": "...", "subagent_id": "...", "type": "..."}`
            - `title`: `{"session_id": "...", "title": "<session title>"}`
            - `session_end`: `{"session_id": "..."}`

            ## Important rules
            1. Every non-permission hook call returns within ~100ms and always exits 0, even if YaaKanban is not running (events are spooled automatically).
            2. Guard the call so if `\(bin)` does not exist, the agent continues normally without errors.
            3. Keep `session_id` consistent across all events of the same conversation.
            """

        case .claude:
            let approvalNote = supportsApproval
                ? "For `PermissionRequest`, YaaKanban blocks up to the configured timeout and prints Claude Code's decision JSON (`{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"|\"deny\"}}}`) on stdout, or empty on timeout."
                : "For `PermissionRequest`, pass `--no-wait` so it notifies without blocking."
            return """
            Please integrate this agent ("\(name)", custom id: `\(id)`) with YaaKanban using Claude Code-compatible hooks.

            ## Command format
            Configure your agent's hooks to pipe Claude Code-shaped JSON payloads on stdin to:

            ```sh
            \(bin) hook custom <HookEventName> --id \(id) --format claude
            ```

            ## Supported Claude hook events
            `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `SubagentStart`, `SubagentStop`, `SessionEnd`.

            ## Key payload fields
            - Common: `session_id`, `hook_event_name`, `cwd`
            - `UserPromptSubmit`: `prompt`
            - `PreToolUse` / `PostToolUse` / `PostToolUseFailure`: `tool_name`, `tool_use_id`, `tool_input`, `tool_response`, `error`
            - `Stop`: `last_assistant_message`
            - `PermissionRequest`: `tool_name`, `tool_use_id`, `tool_input`. \(approvalNote)

            ## Example hooks JSON
            ```json
            \(hookSnippet(yaakPath: bin))
            ```

            ## Important rules
            1. Non-permission hooks return within ~100ms and always exit 0, even if YaaKanban is closed.
            2. Run the hook in the agent's process environment so YaaKanban captures terminal/PID context automatically.
            """
        }
    }
}

/// Reads and writes `custom-agents.json` and manages imported custom icon files.
public enum CustomAgentStore {
    public static func load(from url: URL) -> [CustomAgent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let list = try? dec.decode([CustomAgent].self, from: data) {
            return list
        }
        // Also tolerate default date decoding (e.g. legacy or hand-edited files).
        return (try? JSONDecoder().decode([CustomAgent].self, from: data)) ?? []
    }

    public static func save(_ agents: [CustomAgent], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        var data = try enc.encode(agents)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    public static func find(_ id: String, at url: URL) -> CustomAgent? {
        guard !id.isEmpty else { return nil }
        return load(from: url).first { $0.id == id }
    }

    /// Copies a user-picked image (SVG/PNG/etc.) into `iconsDir` under a unique filename for `id`.
    public static func saveIcon(from sourceURL: URL, for id: String, iconsDir: URL) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "png" : ext
        let slug = CustomAgent.sanitizeId(id)
        let tag = String(UUID().uuidString.prefix(8)).lowercased()
        let filename = "\(slug.isEmpty ? "custom" : slug)-\(tag).\(safeExt)"
        let dst = iconsDir.appendingPathComponent(filename)
        try fm.copyItem(at: sourceURL, to: dst)
        return filename
    }

    /// Removes a previously imported icon file from `iconsDir`.
    public static func removeIcon(filename: String?, iconsDir: URL) {
        guard let filename, !filename.isEmpty, !filename.contains("/"), !filename.contains("\\"), !filename.contains("..") else { return }
        try? FileManager.default.removeItem(at: iconsDir.appendingPathComponent(filename))
    }
}
