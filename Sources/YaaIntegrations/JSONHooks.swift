import Foundation
import YaaCore

/// Edits hook files shaped like Claude's: `{"hooks": {Event: [{matcher?, hooks: [{type, command, timeout}]}]}}`.
/// Codex uses the same shape. Our entries are recognised by command (`HookCommand.isOurs`). An existing entry
/// of ours is updated in place and new ones are appended, so index-keyed trust (Codex) of other hooks is preserved.
/// With `keepIndexes`, install never removes anything either: surplus entries of ours are re-pointed, not dropped.
enum ClaudeShapedHooks {
    static func edit(_ root: inout [String: Any], events: [(name: String, timeout: Int)], command: (String) -> String,
                     install: Bool, marker: [String: Any], keepIndexes: Bool = false) {
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let wanted = install ? Dictionary(uniqueKeysWithValues: events.map { e -> (String, [String: Any]) in
            var entry: [String: Any] = ["type": "command", "command": command(e.name), "timeout": e.timeout]
            entry.merge(marker) { $1 }
            return (e.name, entry)
        }) : [:]
        var placed = Set<String>()
        for (event, groups) in hooks {
            guard var groups = groups as? [[String: Any]] else { continue }
            groups = groups.compactMap { g in
                var g = g
                let original = g["hooks"] as? [[String: Any]] ?? []
                let inner = original.compactMap { h -> [String: Any]? in
                    guard HookCommand.isOurs(h["command"] as? String ?? "") else { return h }
                    // Keep the first entry of ours where it is; drop duplicates and unwanted ones.
                    if let entry = wanted[event], !placed.contains(event) {
                        placed.insert(event)
                        return entry
                    }
                    // Removing would shift every later entry's index; point it at this yaak instead.
                    if install && keepIndexes {
                        var h = wanted[event] ?? h
                        h["command"] = command(event)
                        return h
                    }
                    return nil
                }
                // Drop a group only when we emptied it; a foreign empty group stays put.
                if inner.isEmpty && !original.isEmpty { return nil }
                if g["hooks"] != nil { g["hooks"] = inner }
                return g
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        for e in events where install && !placed.contains(e.name) {
            var groups = hooks[e.name] as? [[String: Any]] ?? []
            groups.append(["hooks": [wanted[e.name]!]])
            hooks[e.name] = groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
    }
}

enum JSONFile {
    static func load(_ url: URL) throws -> (text: String?, root: [String: Any]) {
        guard let text = Installer.read(url) else { return (nil, [:]) }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (text, [:]) }
        guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw IntegrationError.unreadable(url.path)
        }
        return (text, root)
    }

    static func render(_ root: [String: Any]) throws -> String {
        let d = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: d, as: UTF8.self) + "\n"
    }

    /// Plans an edit; returns no change when the semantic content is unchanged.
    static func plan(_ url: URL, edit: (inout [String: Any]) -> Void) throws -> [FileChange] {
        let (text, before) = try load(url)
        var after = before
        edit(&after)
        if NSDictionary(dictionary: before).isEqual(to: after) { return [] }
        return [FileChange(path: url, before: text, after: try render(after))]
    }

    static func containsOurs(_ url: URL) -> Bool {
        Installer.read(url).map(HookCommand.isOurs) ?? false
    }
}

public enum IntegrationError: Error, CustomStringConvertible {
    case unreadable(String)
    /// The edit would be unsafe; the message says why.
    case refused(String)
    public var description: String {
        switch self {
        case .unreadable(let p): return "\(p) is not a JSON object; refusing to edit it"
        case .refused(let why): return why
        }
    }
}

public struct ClaudeIntegration: Integration {
    public let agent = AgentKind.claudeCode
    public init() {}

    static let events: [(name: String, timeout: Int)] = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification",
        "Stop", "SubagentStart", "SubagentStop", "SessionEnd",
    ].map { ($0, 5) } + [("PermissionRequest", Integrations.approvalTimeout + 10)]

    func file(_ home: URL) -> URL { home.appendingPathComponent(".claude/settings.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(file(home)) }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        try JSONFile.plan(file(home)) { root in
            ClaudeShapedHooks.edit(&root, events: Self.events, command: { HookCommand.make(yaak: yaak, agent: agent, event: $0) },
                                   install: install, marker: ["_yaakanban": true])
        }
    }
}

public struct CodexIntegration: Integration {
    public let agent = AgentKind.codex
    public init() {}
    public var postInstallNote: String? { "Codex 只运行你在 /hooks 里信任过的 hook。" }

    public func pendingSteps(home: URL) -> [String] {
        if CodexTrust.hooksOff(home: home) {
            return ["~/.codex/config.toml 的 [features] 里写着 hooks = false，Codex 不会运行任何 hook。",
                    "删掉这一行（或改成 true），重开 Codex，再回到这里点「重新检查」。"]
        }
        let states = CodexTrust.states(home: home)
        let untrusted = states.filter { $0.state == .untrusted }.count
        let modified = states.filter { $0.state == .modified }.count
        let disabled = states.filter { $0.state == .disabled }.count
        guard untrusted + modified + disabled > 0 else { return [] }
        var steps = ["在终端里打开 codex，输入 /hooks。"]
        if untrusted > 0 { steps.append("信任 \(untrusted) 条未信任的 yaak hook。") }
        if modified > 0 { steps.append("\(modified) 条 yaak hook 在你信任之后变了（yaak 路径或参数），重新信任它们。") }
        if disabled > 0 { steps.append("重新启用 \(disabled) 条被关闭的 yaak hook。") }
        steps.append("回到这里点「重新检查」。已经打开的 Codex 会话要重开才会用上。")
        return steps
    }

    static let events: [(name: String, timeout: Int)] = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
        "Stop", "SubagentStart", "SubagentStop",
    ].map { ($0, 5) }

    func file(_ home: URL) -> URL { home.appendingPathComponent(".codex/hooks.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(file(home)) }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        try JSONFile.plan(file(home)) { root in
            ClaudeShapedHooks.edit(&root, events: Self.events, command: { HookCommand.make(yaak: yaak, agent: agent, event: $0) },
                                   install: install, marker: [:], keepIndexes: true)
        }
    }
}

/// Cursor: `{"version": 1, "hooks": {event: [{command, timeout?}]}}`.
public struct CursorIntegration: Integration {
    public let agent = AgentKind.cursor
    public init() {}

    static let events = ["beforeSubmitPrompt", "preToolUse", "postToolUse", "stop"]

    func file(_ home: URL) -> URL { home.appendingPathComponent(".cursor/hooks.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".cursor").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(file(home)) }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        try JSONFile.plan(file(home)) { root in
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for (event, list) in hooks {
                guard let list = list as? [[String: Any]] else { continue }
                let kept = list.filter { !HookCommand.isOurs($0["command"] as? String ?? "") }
                hooks[event] = kept.isEmpty ? nil : kept
            }
            if install {
                for e in Self.events {
                    var list = hooks[e] as? [[String: Any]] ?? []
                    list.append(["command": HookCommand.make(yaak: yaak, agent: agent, event: e), "timeout": 5, "_yaakanban": true])
                    hooks[e] = list
                }
                if root["version"] == nil { root["version"] = 1 }
            }
            root["hooks"] = hooks.isEmpty ? nil : hooks
        }
    }
}

/// Windsurf (Cascade): `{"hooks": {event: [{command, show_output?}]}}` in `~/.codeium/windsurf/hooks.json`.
/// A pre-hook exiting 2 blocks the action, so the command ends in `|| true`. Our entries are found by command.
public struct WindsurfIntegration: Integration {
    public let agent = AgentKind.windsurf
    public init() {}
    public var postInstallNote: String? { "Windsurf 在 Restricted Mode 下不运行 hook；Cascade 没有权限请求 hook，也没有会话开始/结束事件。" }

    static let events = ["pre_user_prompt", "pre_read_code", "post_read_code", "pre_write_code", "post_write_code",
                         "pre_run_command", "post_run_command", "pre_mcp_tool_use", "post_mcp_tool_use", "post_cascade_response"]

    func file(_ home: URL) -> URL { home.appendingPathComponent(".codeium/windsurf/hooks.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".codeium/windsurf").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(file(home)) }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        let url = file(home)
        let root = try JSONFile.load(url).root
        if root["hooks"] != nil && !(root["hooks"] is [String: Any])
            || (root["hooks"] as? [String: Any])?.values.contains(where: { !($0 is [Any]) }) == true {
            throw IntegrationError.refused("hooks in \(url.path) is not an object of lists; refusing to edit it")
        }
        return try JSONFile.plan(url) { root in
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for (event, list) in hooks {
                let kept = (list as? [Any] ?? []).filter { !HookCommand.isOurs(($0 as? [String: Any])?["command"] as? String ?? "") }
                hooks[event] = kept.isEmpty ? nil : kept
            }
            if install {
                for e in Self.events {
                    hooks[e] = (hooks[e] as? [Any] ?? []) + [["command": HookCommand.make(yaak: yaak, agent: agent, event: e) + " || true",
                                                               "show_output": false]]
                }
            }
            root["hooks"] = hooks.isEmpty ? nil : hooks
        }
    }
}
