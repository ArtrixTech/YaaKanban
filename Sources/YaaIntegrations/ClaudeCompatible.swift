import Foundation
import YaaCore

/// Agents whose hook files copy Claude's shape (`ClaudeShapedHooks`): Qwen Code, Gemini CLI, Factory Droid and ZCode.
/// Entries carry no marker key; they are recognised by command, like Codex's.

public struct QwenIntegration: Integration {
    public let agent = AgentKind.qwen
    public init() {}

    static let events: [(name: String, timeout: Int)] = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification",
        "Stop", "SubagentStart", "SubagentStop", "SessionEnd",
    ].map { ($0, 5) } + [("PermissionRequest", Integrations.approvalTimeout + 10)]

    func file(_ home: URL) -> URL { home.appendingPathComponent(".qwen/settings.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".qwen").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(file(home)) }

    public func pendingSteps(home: URL) -> [String] {
        guard let root = try? JSONFile.load(file(home)).root, root["disableAllHooks"] as? Bool == true else { return [] }
        return [String(localized: "~/.qwen/settings.json has \"disableAllHooks\": true, so Qwen Code runs no hooks."),
                String(localized: "Remove it (or set it to false), restart qwen, then come back and click “Recheck”.")]
    }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        try JSONFile.plan(file(home)) { root in
            ClaudeShapedHooks.edit(&root, events: Self.events, command: { HookCommand.make(yaak: yaak, agent: agent, event: $0) },
                                   install: install, marker: [:])
        }
    }
}

/// Gemini CLI: `~/.gemini/settings.json`, timeouts in milliseconds. A hook is named so
/// `hooksConfig.disabled` (which lists names or commands) can be checked. Gemini denies the tool or
/// prompt when a hook exits with anything but 0 or 1 (a missing yaak exits 127), hence `|| true`.
public struct GeminiIntegration: Integration {
    public let agent = AgentKind.gemini
    public init() {}
    static let name = "yaakanban"
    public var postInstallNote: String? { String(localized: "Gemini CLI runs hooks only in trusted folders: choose to trust the folder the first time you open gemini in a project.") }

    static let events: [(name: String, timeout: Int)] = [
        "SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "AfterAgent", "Notification", "SessionEnd",
    ].map { ($0, 5000) }

    func file(_ home: URL) -> URL { home.appendingPathComponent(".gemini/settings.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".gemini").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(file(home)) }

    public func pendingSteps(home: URL) -> [String] {
        guard let root = try? JSONFile.load(file(home)).root, let cfg = root["hooksConfig"] as? [String: Any] else { return [] }
        if cfg["enabled"] as? Bool == false {
            return [String(localized: "hooksConfig.enabled is false in ~/.gemini/settings.json, so Gemini CLI runs no hooks."),
                    String(localized: "Set it to true (or remove it), restart gemini, then come back and click “Recheck”.")]
        }
        let disabled = (cfg["disabled"] as? [String] ?? []).filter { $0 == Self.name || HookCommand.isOurs($0) }
        guard !disabled.isEmpty else { return [] }
        return [String(localized: "The yaak hook is disabled in Gemini CLI (hooksConfig.disabled)."),
                String(localized: "In gemini, run /hooks enable \(Self.name), or remove it from hooksConfig.disabled in ~/.gemini/settings.json, then come back and click “Recheck”.")]
    }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        try JSONFile.plan(file(home)) { root in
            ClaudeShapedHooks.edit(&root, events: Self.events,
                                   command: { HookCommand.make(yaak: yaak, agent: agent, event: $0) + " || true" },
                                   install: install, marker: ["name": Self.name])
        }
    }
}

/// Factory Droid reads `~/.factory/hooks.json` (an event map with no `hooks` wrapper), or the legacy
/// `~/.factory/hooks/hooks.json` when that is absent, and merges `hooks` from `settings.json` per event,
/// the hooks file winning. Each event goes where Droid will read it: a hooks-file event would hide the
/// settings.json entries of that event, so events only settings.json defines get ours there.
public struct DroidIntegration: Integration {
    public let agent = AgentKind.droid
    public init() {}
    public var postInstallNote: String? { String(localized: "Droid runs no hooks in untrusted folders: choose to trust the folder the first time you open droid in a project.") }

    static let events: [(name: String, timeout: Int)] = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd",
    ].map { ($0, 5) }

    func dir(_ home: URL) -> URL { home.appendingPathComponent(".factory") }
    func hooksFile(_ home: URL) -> URL { dir(home).appendingPathComponent("hooks.json") }
    func legacyFile(_ home: URL) -> URL { dir(home).appendingPathComponent("hooks/hooks.json") }
    func settings(_ home: URL) -> URL { dir(home).appendingPathComponent("settings.json") }

    /// The hooks file Droid reads, if any.
    func activeHooksFile(_ home: URL) -> URL? {
        [hooksFile(home), legacyFile(home)].first { Installer.read($0) != nil }
    }

    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: dir(home).path) }
    public func isInstalled(home: URL) -> Bool {
        [hooksFile(home), legacyFile(home), settings(home)].contains(where: JSONFile.containsOurs)
    }

    public func pendingSteps(home: URL) -> [String] {
        let roots = [settings(home), activeHooksFile(home)].compactMap { $0.flatMap { try? JSONFile.load($0).root } }
        guard roots.contains(where: { $0["hooksDisabled"] as? Bool == true }) else { return [] }
        return [String(localized: "Droid has hooksDisabled set to true (~/.factory/settings.json or hooks.json), so it runs no hooks."),
                String(localized: "Re-enable them with /hooks in droid, or remove the setting, then come back and click “Recheck”.")]
    }

    /// Events with foreign entries in a file, ours excluded.
    static func definedEvents(_ hooks: [String: Any]) -> Set<String> {
        Set(hooks.compactMap { event, groups in
            let foreign = (groups as? [[String: Any]] ?? []).contains { g in
                (g["hooks"] as? [[String: Any]] ?? []).contains { !HookCommand.isOurs($0["command"] as? String ?? "") }
            }
            return foreign ? event : nil
        })
    }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        let command = { HookCommand.make(yaak: yaak, agent: agent, event: $0) }
        let active = activeHooksFile(home)
        let settingsHooks = (try JSONFile.load(settings(home)).root)["hooks"] as? [String: Any]
        let hooksRoot = try active.map { try JSONFile.load($0).root } ?? [:]
        // With no hooks file, an existing settings.json `hooks` takes everything; otherwise create hooks.json.
        let target = active ?? (settingsHooks == nil ? hooksFile(home) : nil)
        let inSettings = Self.definedEvents(settingsHooks ?? [:]), inHooks = Self.definedEvents(hooksRoot)
        let toHooks = Self.events.filter { target != nil && (inHooks.contains($0.name) || !inSettings.contains($0.name)) }
        let toSettings = Self.events.filter { e in !toHooks.contains { $0.name == e.name } }

        var changes = try JSONFile.plan(settings(home)) { root in
            ClaudeShapedHooks.edit(&root, events: toSettings, command: command, install: install, marker: [:])
        }
        for file in [hooksFile(home), legacyFile(home)] where Installer.read(file) != nil || file == target {
            changes += try JSONFile.plan(file) { root in
                var wrapped: [String: Any] = ["hooks": root]
                ClaudeShapedHooks.edit(&wrapped, events: file == target ? toHooks : [], command: command,
                                       install: install, marker: [:])
                root = wrapped["hooks"] as? [String: Any] ?? [:]
            }.map { c in
                // Droid reads a hooks file just because it exists; an emptied one would hide the legacy file.
                guard let after = c.after, (try? JSONSerialization.jsonObject(with: Data(after.utf8)) as? [String: Any])?.isEmpty == true
                else { return c }
                return FileChange(path: c.path, before: c.before, after: nil)
            }
        }
        return changes
    }
}

/// ZCode keeps user hooks in `~/.zcode/cli/config.json` under `hooks.events` (Claude's event map), and
/// runs none of them until `hooks.enabled` is true. Each hook also has its own `enabled` switch.
/// The file is ZCode's whole CLI config, so only `hooks` is touched.
public struct ZCodeIntegration: Integration {
    public let agent = AgentKind.zcode
    public init() {}
    public var postInstallNote: String? { String(localized: "ZCode reads its hook config when a session starts: only sessions opened after installing will report.") }

    static let events: [(name: String, timeout: Int)] = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Stop",
    ].map { ($0, 5) } + [("PermissionRequest", Integrations.approvalTimeout + 10)]

    func file(_ home: URL) -> URL { home.appendingPathComponent(".zcode/cli/config.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".zcode").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(file(home)) }

    public func pendingSteps(home: URL) -> [String] {
        guard let hooks = (try? JSONFile.load(file(home)).root)?["hooks"] as? [String: Any] else { return [] }
        if hooks["enabled"] as? Bool != true {
            return [String(localized: "ZCode's main hook switch is off (hooks.enabled in ~/.zcode/cli/config.json)."),
                    String(localized: "Turn it on in ZCode under Settings → Hooks, or set hooks.enabled to true, then come back and click “Recheck”.")]
        }
        let off = Self.disabledEvents(hooks["events"] as? [String: Any] ?? [:])
        guard !off.isEmpty else { return [] }
        return [String(localized: "YaaKanban's \(off.sorted().formatted(.list(type: .and))) hooks are disabled in ZCode."),
                String(localized: "Turn them back on in ZCode under Settings → Hooks, then come back and click “Recheck”.")]
    }

    /// Events whose hook of ours is switched off.
    static func disabledEvents(_ events: [String: Any]) -> Set<String> {
        Set(events.compactMap { event, groups in
            (groups as? [[String: Any]] ?? []).contains { g in
                (g["hooks"] as? [[String: Any]] ?? []).contains {
                    HookCommand.isOurs($0["command"] as? String ?? "") && $0["enabled"] as? Bool == false
                }
            } ? event : nil
        })
    }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        let url = file(home)
        let root = try JSONFile.load(url).root
        if root["hooks"] != nil && !(root["hooks"] is [String: Any])
            || (root["hooks"] as? [String: Any])?["events"].map({ !($0 is [String: Any]) }) == true {
            throw IntegrationError.refused("hooks in \(url.path) is not an object; refusing to edit it")
        }
        let existing = (root["hooks"] as? [String: Any])?["events"] as? [String: Any] ?? [:]
        if let bad = existing.first(where: { !($0.value is [Any]) })?.key {
            throw IntegrationError.refused("hooks.events.\(bad) in \(url.path) is not an array; refusing to edit it")
        }
        return try JSONFile.plan(url) { root in
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            let events = hooks["events"] as? [String: Any] ?? [:]
            let off = Self.disabledEvents(events)
            var wrapped: [String: Any] = ["hooks": events]
            ClaudeShapedHooks.edit(&wrapped, events: Self.events, command: { HookCommand.make(yaak: yaak, agent: agent, event: $0) },
                                   install: install, marker: [:])
            var edited = wrapped["hooks"] as? [String: Any] ?? [:]
            // Keep a hook the user switched off switched off; give our groups a catch-all matcher.
            for (event, groups) in edited {
                edited[event] = (groups as? [[String: Any]] ?? []).map { g in
                    var g = g
                    let inner = g["hooks"] as? [[String: Any]] ?? []
                    guard inner.contains(where: { HookCommand.isOurs($0["command"] as? String ?? "") }) else { return g }
                    if g["matcher"] == nil { g["matcher"] = "*" }
                    // The documented timeout is in seconds; timeoutMs, if read, wins and says the same.
                    g["hooks"] = inner.map { h in
                        var h = h
                        guard HookCommand.isOurs(h["command"] as? String ?? "") else { return h }
                        if let t = h["timeout"] as? Int { h["timeoutMs"] = t * 1000 }
                        if off.contains(event) { h["enabled"] = false }
                        return h
                    }
                    return g
                }
            }
            let foreign = !DroidIntegration.definedEvents(edited).isEmpty
            hooks["events"] = edited.isEmpty ? nil : edited
            // Turn the switch on only when nobody has set it and no other hook would start running;
            // otherwise it is the user's call, and pendingSteps asks for it.
            if install && !foreign && hooks["enabled"] == nil { hooks["enabled"] = true }
            // With no hooks left, an `enabled: true` (likely ours) switches nothing on; take it back.
            if !install && hooks["events"] == nil && hooks["enabled"] as? Bool == true { hooks["enabled"] = nil }
            root["hooks"] = hooks.isEmpty ? nil : hooks
        }
    }
}
