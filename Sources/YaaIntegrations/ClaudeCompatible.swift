import Foundation
import YaaCore

/// Agents whose hook files copy Claude's shape (`ClaudeShapedHooks`): Qwen Code, Gemini CLI and Factory Droid.
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
        return ["~/.qwen/settings.json 里写着 \"disableAllHooks\": true，Qwen Code 不会运行任何 hook。",
                "删掉这一项（或改成 false），重开 qwen，再回到这里点「重新检查」。"]
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
    public var postInstallNote: String? { "Gemini CLI 只在信任过的文件夹里运行 hook：第一次在某个项目里打开 gemini 时选择信任。" }

    static let events: [(name: String, timeout: Int)] = [
        "SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "AfterAgent", "Notification", "SessionEnd",
    ].map { ($0, 5000) }

    func file(_ home: URL) -> URL { home.appendingPathComponent(".gemini/settings.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".gemini").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(file(home)) }

    public func pendingSteps(home: URL) -> [String] {
        guard let root = try? JSONFile.load(file(home)).root, let cfg = root["hooksConfig"] as? [String: Any] else { return [] }
        if cfg["enabled"] as? Bool == false {
            return ["~/.gemini/settings.json 的 hooksConfig.enabled 是 false，Gemini CLI 不会运行任何 hook。",
                    "改成 true（或删掉这一项），重开 gemini，再回到这里点「重新检查」。"]
        }
        let disabled = (cfg["disabled"] as? [String] ?? []).filter { $0 == Self.name || HookCommand.isOurs($0) }
        guard !disabled.isEmpty else { return [] }
        return ["yaak hook 在 Gemini CLI 里被关掉了（hooksConfig.disabled）。",
                "在 gemini 里输入 /hooks enable \(Self.name)，或从 ~/.gemini/settings.json 的 hooksConfig.disabled 删掉它，再回到这里点「重新检查」。"]
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
    public var postInstallNote: String? { "Droid 在没信任过的文件夹里不运行任何 hook：第一次在某个项目里打开 droid 时选择信任。" }

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
        return ["Droid 的 hooksDisabled 是 true（~/.factory/settings.json 或 hooks.json），不会运行任何 hook。",
                "在 droid 里输入 /hooks 重新启用，或删掉这一项，再回到这里点「重新检查」。"]
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
