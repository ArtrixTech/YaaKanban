import Foundation
import YaaCore

/// Discovers live Claude Code sessions from `~/.claude/sessions/<pid>.json`, including ones
/// started before hooks were installed. Status there is coarse; hooks take precedence.
struct ClaudeSessionScanner {
    let dir = Paths.home().appendingPathComponent(".claude/sessions")

    func scan() -> [AgentEvent] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                  let j = JSONValue.parse(data),
                  let sid = j["sessionId"]?.string,
                  let pid = j["pid"]?.number.map({ Int32($0) }), ProcessUtil.isAlive(pid) else { return nil }
            let status: SessionStatus
            switch j["status"]?.string {
            case "busy", "shell": status = .running
            case "waiting": status = .needsInput
            default: status = .idle
            }
            let at = j["statusUpdatedAt"]?.number.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            return AgentEvent(agent: .claudeCode, sessionId: sid, at: at, kind: .statusSnapshot(status),
                              cwd: j["cwd"]?.string, agentPid: pid)
        }
    }
}
