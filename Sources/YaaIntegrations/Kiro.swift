import Foundation
import YaaCore

/// Kiro CLI's V3 engine loads every `~/.kiro/hooks/*.json`; YaaKanban owns `yaak.json`. Payloads use
/// Claude's field names (no tool id). The V2 engine reads hooks only from agent profiles, so it is not
/// supported; `chat.agentEngine` in `~/.kiro/settings/cli.json` says which engine runs.
public struct KiroIntegration: Integration {
    public let agent = AgentKind.kiro
    public init() {}
    public var postInstallNote: String? { "Kiro CLI 在没信任过的工作区里不运行 hook：第一次在某个项目里打开 kiro-cli 时选择信任。" }

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
        return ["Kiro CLI 用的是 \(engine) 引擎（~/.kiro/settings/cli.json 的 chat.agentEngine），只有 V3 引擎读取 ~/.kiro/hooks。",
                "运行 kiro-cli settings chat.agentEngine v3（或启动时加 --v3），再回到这里点「重新检查」。"]
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
