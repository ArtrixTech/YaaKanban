import Foundation

/// Token and tool totals of a session, as far as its transcript tells.
public struct Usage: Codable, Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheWrite = 0
    /// Tokens in the context at the latest request (input + cache), and the window when known.
    public var context = 0
    public var contextWindow: Int?
    public var toolCalls = 0
    /// Calls per tool name.
    public var tools: [String: Int] = [:]

    public init() {}

    public var total: Int { input + output + cacheRead + cacheWrite }
}

/// Reads a Claude Code or Codex transcript incrementally: each call consumes the lines appended
/// since the previous one, keeping totals and the latest assistant text of the current turn.
public struct TranscriptTally: Sendable {
    public enum Format: Sendable { case claude, codex }

    public let format: Format
    public private(set) var usage = Usage()
    /// Latest assistant text since the last prompt.
    public private(set) var lastReply: String?
    public private(set) var offset: UInt64 = 0
    /// Tool calls whose result is in the transcript, newest last (id, failed). A safety net for
    /// tool ends the hooks never reported, such as an interrupt.
    public private(set) var finishedTools: [(id: String, failed: Bool)] = []
    static let finishedLimit = 100
    /// Claude repeats one message's usage on each of its content-block lines.
    private var lastMessageId: String?

    public init(format: Format) { self.format = format }

    static let chunk = 8 * 1024 * 1024

    /// Consumes what was appended to the file. Returns false when nothing new was read.
    @discardableResult
    public mutating func update(from url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        if size < offset { self = TranscriptTally(format: format) }  // rewritten
        var changed = false
        while offset < size {
            try? h.seek(toOffset: offset)
            guard let data = try? h.read(upToCount: Self.chunk), !data.isEmpty else { break }
            // Only whole lines; a partial last line is read next time.
            guard let end = data.lastIndex(of: UInt8(ascii: "\n")) else { break }
            consume(data[data.startIndex...end])
            offset += UInt64(end - data.startIndex + 1)
            changed = true
        }
        return changed
    }

    public mutating func consume(_ data: Data) {
        for line in data.split(separator: UInt8(ascii: "\n")) {
            switch format {
            case .claude: claudeLine(line)
            case .codex: codexLine(line)
            }
        }
    }

    private mutating func claudeLine(_ line: Data.SubSequence) {
        let isAssistant = line.has("\"type\":\"assistant\"")
        if !isAssistant, line.has("\"tool_result\"") { noteResults(line) }
        // User lines are mostly (large) tool results; only parse ones that may be a typed prompt.
        let isPrompt = !isAssistant && line.has("\"type\":\"user\"") && !line.has("\"tool_result\"")
        guard isAssistant || isPrompt, let j = JSONValue.parse(Data(line)) else { return }
        if j["isSidechain"]?.bool == true || j["isMeta"]?.bool == true { return }
        let content = j["message"]?["content"]
        if isPrompt {
            if let p = TranscriptPeek.text(of: content), !p.hasPrefix("<") { lastReply = nil }
            return
        }
        let id = j["message"]?["id"]?.string
        if let u = j["message"]?["usage"], id == nil || id != lastMessageId {
            lastMessageId = id
            let input = int(u["input_tokens"]), read = int(u["cache_read_input_tokens"]), write = int(u["cache_creation_input_tokens"])
            usage.input += input
            usage.cacheRead += read
            usage.cacheWrite += write
            usage.output += int(u["output_tokens"])
            usage.context = input + read + write
        }
        for block in content?.array ?? [] where block["type"]?.string == "tool_use" {
            countTool(block["name"]?.string)
        }
        if let t = TranscriptPeek.clip(TranscriptPeek.text(of: content)) { lastReply = t }
    }

    private mutating func codexLine(_ line: Data.SubSequence) {
        let tokens = line.has("\"token_count\"")
        let message = line.has("\"type\":\"message\"")
        let call = line.has("\"type\":\"function_call\"") || line.has("\"type\":\"custom_tool_call\"")
        let started = line.has("\"task_started\"")
        guard tokens || message || call || started, let j = JSONValue.parse(Data(line)), let p = j["payload"] else { return }
        switch p["type"]?.string {
        case "token_count":
            // Totals are cumulative; the last record wins.
            guard let info = p["info"], let t = info["total_token_usage"] else { return }
            let cached = int(t["cached_input_tokens"])
            usage.cacheRead = cached
            usage.cacheWrite = int(t["cache_write_input_tokens"])
            usage.input = max(0, int(t["input_tokens"]) - cached)
            usage.output = int(t["output_tokens"])
            if let last = info["last_token_usage"] { usage.context = int(last["input_tokens"]) }
            usage.contextWindow = info["model_context_window"]?.number.map { Int($0) } ?? usage.contextWindow
        case "task_started":
            lastReply = nil
        case "message" where p["role"]?.string == "assistant":
            let parts = p["content"]?.array?.compactMap { $0["text"]?.string } ?? []
            if let t = TranscriptPeek.clip(parts.joined(separator: "\n")) { lastReply = t }
        case "function_call", "custom_tool_call":
            countTool(p["name"]?.string)
        default: break
        }
    }

    /// Result ids by byte search: result lines can be megabytes, too big to parse in bulk.
    private mutating func noteResults(_ line: Data.SubSequence) {
        let failed = line.has("\"is_error\":true")
        for id in line.stringValues(of: "tool_use_id") { finishedTools.append((id, failed)) }
        if finishedTools.count > Self.finishedLimit { finishedTools.removeFirst(finishedTools.count - Self.finishedLimit) }
    }

    private mutating func countTool(_ name: String?) {
        usage.toolCalls += 1
        usage.tools[name ?? "?", default: 0] += 1
    }

    private func int(_ v: JSONValue?) -> Int { v?.number.map { Int($0) } ?? 0 }
}

extension Data.SubSequence {
    /// Values of `"key":"…"` pairs, in order (no escape handling; meant for ids).
    func stringValues(of key: String) -> [String] {
        let needle = Array("\"\(key)\":\"".utf8)
        let quote = UInt8(ascii: "\"")
        var out: [String] = []
        withUnsafeBytes { (hay: UnsafeRawBufferPointer) in
            guard let base = hay.baseAddress else { return }
            var from = 0
            while from < hay.count {
                guard let hit = memmem(base + from, hay.count - from, needle, needle.count) else { break }
                let start = base.distance(to: UnsafeRawPointer(hit)) + needle.count
                guard let end = hay[start...].firstIndex(of: quote) else { break }
                out.append(String(decoding: UnsafeRawBufferPointer(rebasing: hay[start..<end]), as: UTF8.self))
                from = end
            }
        }
        return out
    }

    /// Byte substring test via memmem; the generic `contains` is far too slow for transcripts.
    func has(_ needle: String) -> Bool {
        var n = needle.utf8CString
        n.removeLast()  // NUL
        return withUnsafeBytes { hay in
            n.withUnsafeBytes { nd in memmem(hay.baseAddress, hay.count, nd.baseAddress, nd.count) != nil }
        }
    }
}
