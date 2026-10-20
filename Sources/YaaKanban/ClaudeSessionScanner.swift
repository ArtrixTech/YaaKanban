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

/// Token / tool totals and the live reply from Claude and Codex transcripts, read incrementally
/// off the main thread.
final class UsageTracker: @unchecked Sendable {
    struct Target: Sendable {
        var key: String
        var agent: AgentKind
        var sessionId: String
        var transcriptPath: String?
    }

    struct Result: Sendable {
        var usage: Usage
        var lastReply: String?
    }

    private let queue = DispatchQueue(label: "yaak.usage", qos: .utility)
    private var tallies: [String: (url: URL, tally: TranscriptTally, mtime: Date?)] = [:]
    /// Codex sessions whose rollout file was looked for and not found, with when.
    private var missing: [String: Date] = [:]
    private var busy = false

    /// Reads what changed; `done` gets only the sessions whose result changed.
    func refresh(_ targets: [Target], done: @escaping @MainActor ([String: Result]) -> Void) {
        queue.async { [self] in
            guard !busy else { return }
            busy = true
            defer { busy = false }
            var out: [String: Result] = [:]
            for t in targets {
                guard let format: TranscriptTally.Format = t.agent == .claudeCode ? .claude : t.agent == .codex ? .codex : nil
                else { continue }
                var entry = tallies[t.key]
                if entry == nil {
                    guard let url = url(t) else { continue }
                    entry = (url, TranscriptTally(format: format), nil)
                }
                guard var e = entry else { continue }
                let mtime = (try? e.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                guard mtime != e.mtime else { continue }
                e.mtime = mtime
                let changed = e.tally.update(from: e.url)
                tallies[t.key] = e
                if changed { out[t.key] = Result(usage: e.tally.usage, lastReply: e.tally.lastReply) }
            }
            if !out.isEmpty { DispatchQueue.main.async { MainActor.assumeIsolated { done(out) } } }
        }
    }

    private func url(_ t: Target) -> URL? {
        let fm = FileManager.default
        if let p = t.transcriptPath, fm.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        let home = Paths.home()
        switch t.agent {
        case .claudeCode:
            let projects = home.appendingPathComponent(".claude/projects")
            let file = "\(t.sessionId).jsonl"
            return ((try? fm.contentsOfDirectory(atPath: projects.path)) ?? []).lazy
                .map { projects.appendingPathComponent($0).appendingPathComponent(file) }
                .first { fm.fileExists(atPath: $0.path) }
        case .codex:
            // rollout-<time>-<session id>.jsonl under sessions/YYYY/MM/DD; walk it at most once a minute.
            if let m = missing[t.key], Date().timeIntervalSince(m) < 60 { return nil }
            let root = home.appendingPathComponent(".codex/sessions")
            let e = fm.enumerator(at: root, includingPropertiesForKeys: nil)
            while let u = e?.nextObject() as? URL {
                if u.pathExtension == "jsonl", u.lastPathComponent.contains(t.sessionId) { return u }
            }
            missing[t.key] = Date()
            return nil
        default:
            return nil
        }
    }
}
