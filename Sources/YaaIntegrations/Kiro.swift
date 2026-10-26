import Foundation
import YaaCore

/// Kiro CLI's V3 engine loads every `~/.kiro/hooks/*.json`; YaaKanban owns `yaak.json`. Payloads use
/// Claude's field names (no tool id). The V2 engine reads hooks only from agent profiles, so it is not
/// supported; `chat.agentEngine` in `~/.kiro/settings/cli.json` says which engine runs.
public struct KiroIntegration: Integration {
    public let agent = AgentKind.kiro
    public init() {}
    public var postInstallNote: String? { String(localized: "Kiro CLI runs no hooks in untrusted workspaces: choose to trust the workspace the first time you open kiro-cli in a project.") }

    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"]

    func file(_ home: URL) -> URL { home.appendingPathComponent(".kiro/hooks/yaak.json") }
    func settings(_ home: URL) -> URL { home.appendingPathComponent(".kiro/settings/cli.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".kiro").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(file(home)) }

    public func pendingSteps(home: URL) -> [String] {
        guard let root = try? JSONFile.load(settings(home)).root,
              let value = root["chat.agentEngine"] ?? (root["chat"] as? [String: Any])?["agentEngine"] else { return [] }
        let engine = "\(value)"
        guard engine.lowercased() != "v3" else { return [] }
        return [String(localized: "Kiro CLI uses the \(engine) engine (chat.agentEngine in ~/.kiro/settings/cli.json); only the V3 engine reads ~/.kiro/hooks."),
                String(localized: "Run kiro-cli settings chat.agentEngine v3 (or start it with --v3), then come back and click “Recheck”.")]
    }

    func source(yaak: String) throws -> String {
        let hooks: [[String: Any]] = Self.events.map { e in
            var h: [String: Any] = ["name": "yaak-\(e)", "trigger": e, "timeout": 5,
                                    "action": ["type": "command", "command": HookCommand.make(yaak: yaak, agent: agent, event: e)]]
            if e.hasSuffix("ToolUse") { h["matcher"] = "*" }
            return h
        }
        return try JSONFile.render(["version": "v1", "hooks": hooks])
    }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        let url = file(home)
        let before = Installer.read(url)
        if let before, !HookCommand.isOurs(before) {
            throw IntegrationError.refused("\(url.path) exists and is not managed by YaaKanban")
        }
        let after = install ? try source(yaak: yaak) : nil
        return before == after ? [] : [FileChange(path: url, before: before, after: after)]
    }
}
