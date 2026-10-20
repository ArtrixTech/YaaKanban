import Foundation

/// Latest prompt / reply / recap read from a Claude Code transcript (`~/.claude/projects/*/<id>.jsonl`).
/// Used for sessions started before hooks were installed, which otherwise show no content.
public struct TranscriptPeek: Codable, Equatable, Sendable {
    public var lastPrompt: String?
    public var lastReply: String?
    /// Claude's own "away summary" recap of the session goal and next step.
    public var recap: String?

    public init(lastPrompt: String? = nil, lastReply: String? = nil, recap: String? = nil) {
        self.lastPrompt = lastPrompt
        self.lastReply = lastReply
        self.recap = recap
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
        return parse(data)
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
        return peek == TranscriptPeek() ? nil : peek
    }

    private static func text(of content: JSONValue?) -> String? {
        if let s = content?.string { return s }
        let parts = content?.array?.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil } ?? []
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static func clip(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t.count > textLimit ? String(t.prefix(textLimit)) + "…" : t
    }
}
