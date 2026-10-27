import Foundation

/// Latest prompt / reply / recap read from a Claude Code transcript (`~/.claude/projects/*/<id>.jsonl`).
/// Used for sessions started before hooks were installed, which otherwise show no content.
public struct TranscriptPeek: Codable, Equatable, Sendable {
    public var lastPrompt: String?
    public var lastReply: String?
    /// Claude's own "away summary" recap of the session goal and next step.
    public var recap: String?
    /// The session's short title: one set with /rename, else the agent's generated one.
    public var title: String?

    public init(lastPrompt: String? = nil, lastReply: String? = nil, recap: String? = nil, title: String? = nil) {
        self.lastPrompt = lastPrompt
        self.lastReply = lastReply
        self.recap = recap
        self.title = title
    }

    public static let tailBytes = 256 * 1024
    static let textLimit = 600

    /// Reads the tail of the transcript. Returns nil when nothing useful was found.
    public static func read(_ url: URL) -> TranscriptPeek? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        guard let data = try? h.readToEnd() else { return nil }
        var peek = parse(data)
        // Titles are written early and not always repeated; look at the head of long files too.
        if peek?.title == nil, size > UInt64(tailBytes) {
            try? h.seek(toOffset: 0)
            if let head = try? h.read(upToCount: tailBytes), let t = titles(head) {
                peek = peek ?? TranscriptPeek()
                peek?.title = t
            }
        }
        return peek
    }

    /// Latest title in the data; a user-set title beats a generated one.
    static func titles(_ data: Data) -> String? {
        var custom: String?, ai: String?
        for line in data.split(separator: UInt8(ascii: "\n")) where line.has("-title\"") {
            guard let j = JSONValue.parse(Data(line)) else { continue }
            switch j["type"]?.string {
            case "custom-title": custom = j["customTitle"]?.string ?? custom
            case "ai-title": ai = j["aiTitle"]?.string ?? ai
            default: break
            }
        }
        return clip(custom ?? ai)
    }

    /// Scans JSONL lines newest first. The reply only counts if it came after the last prompt.
    public static func parse(_ data: Data) -> TranscriptPeek? {
        var peek = TranscriptPeek()
        var replyDone = false
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let j = JSONValue.parse(Data(line)) else { continue }
            if j["isSidechain"]?.bool == true || j["isMeta"]?.bool == true { continue }
            switch j["type"]?.string {
            case "system" where j["subtype"]?.string == "away_summary":
                if peek.recap == nil { peek.recap = clip(j["content"]?.string) }
            case "assistant" where !replyDone && peek.lastReply == nil:
                peek.lastReply = clip(text(of: j["message"]?["content"]))
            case "user" where peek.lastPrompt == nil:
                // Tool results are user-role messages too; only typed text is a prompt.
                if let p = clip(text(of: j["message"]?["content"])), !p.hasPrefix("<") {
                    peek.lastPrompt = p
                    replyDone = true
                }
            default: break
            }
            if peek.lastPrompt != nil && peek.recap != nil { break }
        }
        peek.title = titles(data)
        return peek == TranscriptPeek() ? nil : peek
    }

    static func text(of content: JSONValue?) -> String? {
        if let s = content?.string { return s }
        let parts = content?.array?.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil } ?? []
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func clip(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t.count > textLimit ? String(t.prefix(textLimit)) + "…" : t
    }
}

/// Sub-agents that run as sessions of their own name their parent in the transcript's header line
/// (pi: `{"type":"session",…,"parentSession":"<parent transcript>"}`).
public enum SubagentLink {
    public struct Header: Sendable { public let parentSession: String? }

    /// The transcript's header, or nil while it is not written yet (no file, or no whole first line).
    public static func header(transcript url: URL) -> Header? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 4096) else { return nil }
        guard let nl = head.firstIndex(of: UInt8(ascii: "\n")) else {
            // A first line this long is not a pi header; there is nothing to wait for.
            return head.count >= 4096 ? Header(parentSession: nil) : nil
        }
        guard let j = JSONValue.parse(Data(head[head.startIndex..<nl])), j["type"]?.string == "session" else {
            return Header(parentSession: nil)
        }
        return Header(parentSession: j["parentSession"]?.string)
    }
}

