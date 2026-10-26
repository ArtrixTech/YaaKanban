import Foundation
import YaaCore

/// GitHub Copilot CLI loads every `~/.copilot/hooks/*.json`; YaaKanban owns `yaak.json`.
/// Events and payloads are camelCase (`Normalizer.copilotAsClaude`). A failing preToolUse hook blocks
/// the tool, so each command ends in `|| true`.
public struct CopilotIntegration: Integration {
    public let agent = AgentKind.copilot
    public init() {}

    static let events: [(name: String, timeout: Int)] = [
        "sessionStart", "sessionEnd", "userPromptSubmitted", "preToolUse", "postToolUse", "postToolUseFailure",
        "agentStop", "notification",
    ].map { ($0, 5) } + [("permissionRequest", Integrations.approvalTimeout + 10)]

    func file(_ home: URL) -> URL { home.appendingPathComponent(".copilot/hooks/yaak.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".copilot").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(file(home)) }

    func source(yaak: String) throws -> String {
        let hooks = Dictionary(uniqueKeysWithValues: Self.events.map { e in
            (e.name, [["type": "command", "bash": HookCommand.make(yaak: yaak, agent: agent, event: e.name) + " || true",
                       "timeoutSec": e.timeout]])
        })
        return try JSONFile.render(["version": 1, "hooks": hooks])
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
