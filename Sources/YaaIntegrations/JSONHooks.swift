import Foundation
import YaaCore

/// Edits hook files shaped like Claude's: `{"hooks": {Event: [{matcher?, hooks: [{type, command, timeout}]}]}}`.
/// Codex uses the same shape. Our entries are recognised by command (`HookCommand.isOurs`). An existing entry
/// of ours is updated in place and new ones are appended, so index-keyed trust (Codex) of other hooks is preserved.
enum ClaudeShapedHooks {
    static func edit(_ root: inout [String: Any], events: [(name: String, timeout: Int)], command: (String) -> String,
                     install: Bool, marker: [String: Any]) {
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
                let inner = (g["hooks"] as? [[String: Any]] ?? []).compactMap { h -> [String: Any]? in
                    guard HookCommand.isOurs(h["command"] as? String ?? "") else { return h }
                    // Keep the first entry of ours where it is; drop duplicates and unwanted ones.
                    guard let entry = wanted[event], !placed.contains(event) else { return nil }
                    placed.insert(event)
                    return entry
                }
                if inner.isEmpty && g["hooks"] != nil { return nil }
                g["hooks"] = inner
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
    public var description: String {
        switch self { case .unreadable(let p): return "\(p) is not a JSON object; refusing to edit it" }
    }
}

public struct ClaudeIntegration: Integration {
    public let agent = AgentKind.claudeCode
    public init() {}

    static let events: [(name: String, timeout: Int)] = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification",
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
    public var postInstallNote: String? { "Codex: run /hooks inside Codex and trust the new YaaKanban hooks." }

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
                                   install: install, marker: [:])
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
