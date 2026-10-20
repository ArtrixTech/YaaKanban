import Foundation
import YaaCore

/// Discovers live Claude Code sessions from `~/.claude/sessions/<pid>.json`, including ones
/// started before hooks were installed. Status there is coarse; hooks take precedence.
final class ClaudeSessionScanner {
    let dir = Paths.home().appendingPathComponent(".claude/sessions")
    let projects = Paths.home().appendingPathComponent(".claude/projects")
    /// Transcript location and the mtime it was last read at, per session id.
    private var transcripts: [String: (url: URL, mtime: Date)] = [:]

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

    /// Reads the transcript of a session when it changed since the last call; nil otherwise.
    func peek(_ s: SessionState) -> TranscriptPeek? {
        guard let url = transcriptURL(s),
              let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              transcripts[s.sessionId]?.mtime != mtime else { return nil }
        transcripts[s.sessionId] = (url, mtime)
        return TranscriptPeek.read(url)
    }

    /// Codex thread names (`~/.codex/session_index.jsonl`), reloaded when the file changes.
    private var codexTitles: [String: String] = [:]
    private var codexIndexMtime: Date?

    func codexTitle(_ sessionId: String) -> String? {
        let url = Paths.home().appendingPathComponent(".codex/session_index.jsonl")
        if let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, m != codexIndexMtime,
           let data = try? Data(contentsOf: url) {
            codexIndexMtime = m
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let j = JSONValue.parse(Data(line)), let id = j["id"]?.string, let name = j["thread_name"]?.string else { continue }
                codexTitles[id] = name
            }
        }
        return codexTitles[sessionId]
    }

    private func transcriptURL(_ s: SessionState) -> URL? {
        if let p = s.transcriptPath { return URL(fileURLWithPath: p) }
        if let known = transcripts[s.sessionId]?.url { return known }
        // Project directory names encode the cwd lossily, so search for the session id instead.
        let file = "\(s.sessionId).jsonl"
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        return dirs.lazy.map { self.projects.appendingPathComponent($0).appendingPathComponent(file) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
