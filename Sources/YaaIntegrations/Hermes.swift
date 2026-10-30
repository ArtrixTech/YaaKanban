import Foundation
import YaaCore

/// Hermes Agent: shell hooks under the top-level `hooks:` mapping of `~/.hermes/config.yaml`,
/// `event: [{command, timeout}]`. The file is the user's whole Hermes config (and other tools add
/// hooks there too), so it is edited line by line: each of our list items is one line tagged
/// `# yaakanban`, and a key we had to add is tagged the same way. Nothing else is rewritten.
///
/// Hermes asks before it runs a hook command it has not seen (`[y/N]` at the terminal) and keeps the
/// answers in `~/.hermes/shell-hooks-allowlist.json`, keyed by exact (event, command).
public struct HermesIntegration: Integration {
    public let agent = AgentKind.hermes
    public init() {}

    /// `pre_llm_call` fires once per turn with the prompt; `on_session_end` ends every turn
    /// (interrupted ones too); `on_session_finalize` is the real end of the session.
    static let events = ["pre_llm_call", "pre_tool_call", "post_tool_call", "post_llm_call",
                         "on_session_end", "on_session_finalize"]
    static let tag = "# yaakanban"

    func file(_ home: URL) -> URL { home.appendingPathComponent(".hermes/config.yaml") }
    func allowlist(_ home: URL) -> URL { home.appendingPathComponent(".hermes/shell-hooks-allowlist.json") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".hermes").path) }
    public func isInstalled(home: URL) -> Bool { !Self.ours(Installer.read(file(home)) ?? "").isEmpty }

    public var postInstallNote: String? { String(localized: "Before Hermes first runs a new hook, it asks you in the terminal to allow each one.") }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        let url = file(home)
        let before = Installer.read(url)
        let wanted = install ? Self.events.map { ($0, Self.item(HookCommand.make(yaak: yaak, agent: agent, event: $0))) } : []
        let after = try Self.edit(before ?? "", wanted: wanted)
        if after == (before ?? "") { return [] }
        // A file left empty held only our hooks (we created it); remove it.
        let empty = after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty && before == nil { return [] }
        return [FileChange(path: url, before: before, after: empty ? nil : after)]
    }

    public func pendingSteps(home: URL) -> [String] {
        guard let text = Installer.read(file(home)), !Self.autoAccepts(text) else { return [] }
        let approved = Self.approvals(Installer.read(allowlist(home)))
        let waiting = Self.ours(text).filter { !approved.contains("\($0.event)\n\($0.command)") }.count
        guard waiting > 0 else { return [] }
        return [String(localized: "Run hermes once in a terminal."),
                String(localized: "It asks about each YaaKanban hook (\(waiting) in total); answer y to all."),
                String(localized: "Come back here.")]
    }

    // MARK: YAML

    static func item(_ command: String) -> String { "- {command: \(PluginSource.jsString(command)), timeout: 5} \(tag)" }

    /// Our items in the `hooks:` block, with the event key they sit under.
    static func ours(_ text: String) -> [(event: String, command: String)] {
        let lines = split(text)
        guard let block = hooksBlock(lines) else { return [] }
        var out: [(String, String)] = []
        var keyIndent: Int?, key: String?
        for line in lines[block] {
            let body = line.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty, !body.hasPrefix("#") else { continue }
            if !body.hasPrefix("-") {
                if keyIndent == nil { keyIndent = indent(line) }
                if indent(line) == keyIndent, let k = keyName(body) { key = k }
                continue
            }
            if let command = commandValue(body), HookCommand.isOurs(command), let key { out.append((key, command)) }
        }
        return out
    }

    /// The key of a `key:` line, without quotes (`"on_session_end":` names on_session_end).
    static func keyName(_ body: String) -> String? {
        if let q = body.first, q == "\"" || q == "'" {
            guard let close = body.dropFirst().firstIndex(of: q),
                  body[body.index(after: close)...].hasPrefix(":") else { return nil }
            return String(body[body.index(after: body.startIndex)..<close])
        }
        return body.firstIndex(of: ":").map { String(body[..<$0]).trimmingCharacters(in: .whitespaces) }
    }

    /// The `command` of a one-line flow item, or of a block item's first line (`- command: "…"`).
    static func commandValue(_ item: String) -> String? {
        guard let r = item.range(of: "command:") else { return nil }
        let rest = item[r.upperBound...].trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("\"") {
            var out = "", escaped = false
            for c in rest.dropFirst() {
                if escaped { out.append(c == "n" ? "\n" : c); escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { return out }
                else { out.append(c) }
            }
            return nil
        }
        if rest.hasPrefix("'"), let end = rest.dropFirst().range(of: "'", options: .literal) {
            return String(rest[rest.index(after: rest.startIndex)..<end.lowerBound])
        }
        return rest.split(whereSeparator: { $0 == "," || $0 == "}" || $0 == "#" }).first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// `hooks_auto_accept: true` at the top level of the config.
    static func autoAccepts(_ text: String) -> Bool {
        split(text).contains { line in
            guard line.hasPrefix("hooks_auto_accept:") else { return false }
            var v = line.dropFirst("hooks_auto_accept:".count)
            if let hash = v.firstIndex(of: "#") { v = v[..<hash] }
            let value = v.trimmingCharacters(in: .whitespaces).lowercased()
            return ["true", "yes", "on", "\"true\"", "'true'"].contains(value)
        }
    }

    static func approvals(_ text: String?) -> Set<String> {
        guard let data = text.map({ Data($0.utf8) }),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["approvals"] as? [[String: Any]] else { return [] }
        return Set(list.compactMap { e in
            guard let ev = e["event"] as? String, let cmd = e["command"] as? String else { return nil }
            return "\(ev)\n\(cmd)"
        })
    }

    private static func split(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }
    private static func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }
    private static func isBlank(_ line: String) -> Bool {
        let b = line.trimmingCharacters(in: .whitespaces)
        return b.isEmpty || b.hasPrefix("#")
    }
    private static func isTopLevelKey(_ line: String) -> Bool {
        guard let c = line.first, c != " ", c != "#", c != "-" else { return false }
        return line.contains(":")
    }
    private static func isHooksKey(_ line: String) -> Bool { keyName(line) == "hooks" && line.first != " " }

    /// Lines under the top-level `hooks:` key, up to the next top-level key.
    private static func hooksBlock(_ lines: [String]) -> Range<Int>? {
        guard let h = lines.firstIndex(where: isHooksKey) else { return nil }
        let end = lines[(h + 1)...].firstIndex(where: isTopLevelKey) ?? lines.count
        return (h + 1)..<end
    }

    /// Past a run of blank and comment lines from `i` that closes another tool's managed section
    /// (`# <<< …`), so what we add stays outside it; otherwise `i`.
    private static func pastMarkers(_ lines: [String], from i: Int, limit: Int) -> Int {
        var at = i, k = i
        while k < limit, isBlank(lines[k]) {
            if lines[k].trimmingCharacters(in: .whitespaces).hasPrefix("# <<<") { at = k + 1 }
            k += 1
        }
        return at
    }

    /// Removes our lines (and keys we added that are left empty), then adds `wanted` items, each
    /// under its event key inside `hooks:`. Leaves the text alone when it already holds exactly them.
    static func edit(_ text: String, wanted: [(event: String, item: String)]) throws -> String {
        let crlf = text.contains("\r\n")
        let have = ours(text).map { "\($0.event)\n\($0.command)" }.sorted()
        let want = wanted.map { "\($0.event)\n\(commandValue($0.item) ?? "")" }.sorted()
        let tagged = split(text).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("-") && $0.hasSuffix(tag) }
        if have == want, tagged.allSatisfy({ line in wanted.contains { $0.item == line } }) { return text }
        var lines = strip(split(text))
        func joined() -> String { lines.joined(separator: crlf ? "\r\n" : "\n") }
        guard !wanted.isEmpty else { return joined() }

        if let h = lines.firstIndex(where: isHooksKey) {
            let value = lines[h][lines[h].range(of: ":")!.upperBound...].trimmingCharacters(in: .whitespaces)
            if ["{}", "null", "~"].contains(value) {
                // An empty mapping written inline; open it as a block (strip puts it back).
                lines[h] = "hooks: \(tag) was: \(value)"
            } else if !value.isEmpty && !value.hasPrefix("#") {
                throw IntegrationError.refused("hooks: in Hermes config.yaml is written inline; refusing to edit it")
            }
        } else {
            if let last = lines.last, last.isEmpty { lines.removeLast() }
            lines.append("hooks: \(tag)")
            lines.append("")
        }
        let start = lines.firstIndex(where: isHooksKey)!
        let blockEnd = hooksBlock(lines)!.upperBound
        if let first = lines[(start + 1)..<blockEnd].first(where: { !isBlank($0) }),
           first.trimmingCharacters(in: .whitespaces).hasPrefix("-") || first.contains("\t") {
            throw IntegrationError.refused("hooks: in Hermes config.yaml is not a mapping of events; refusing to edit it")
        }
        // New keys go after the last content line; trailing blank lines and comments stay outside.
        var end = blockEnd
        while end > start + 1, isBlank(lines[end - 1]) { end -= 1 }
        end = pastMarkers(lines, from: end, limit: blockEnd)
        let keyIndent = lines[(start + 1)..<end].first { !isBlank($0) && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("-") }
            .map(indent) ?? 2

        for (event, item) in wanted {
            let keyAt = lines[(start + 1)..<end].firstIndex { l in
                indent(l) == keyIndent && !isBlank(l) && keyName(l.trimmingCharacters(in: .whitespaces)) == event
            }
            if let k = keyAt {
                let value = lines[k].trimmingCharacters(in: .whitespaces).range(of: ":").map {
                    lines[k].trimmingCharacters(in: .whitespaces)[$0.upperBound...].trimmingCharacters(in: .whitespaces)
                } ?? ""
                if !value.isEmpty && !value.hasPrefix("#") {
                    throw IntegrationError.refused("hooks.\(event) in Hermes config.yaml is written inline; refusing to edit it")
                }
                var j = k + 1, itemIndent = keyIndent + 2
                while j < end {
                    let l = lines[j], b = l.trimmingCharacters(in: .whitespaces)
                    if b.isEmpty || b.hasPrefix("#") { j += 1; continue }
                    if indent(l) > keyIndent || (indent(l) == keyIndent && b.hasPrefix("-")) {
                        if b.hasPrefix("-") { itemIndent = indent(l) }
                        j += 1; continue
                    }
                    break
                }
                // Insert after the last content line, before trailing comments of the next key.
                var at = j
                while at > k + 1, isBlank(lines[at - 1]) { at -= 1 }
                at = pastMarkers(lines, from: at, limit: j)
                lines.insert(String(repeating: " ", count: itemIndent) + item, at: at)
                end += 1
            } else {
                let pad = String(repeating: " ", count: keyIndent)
                lines.insert(contentsOf: ["\(pad)\(event): \(tag)", "\(pad)  \(item)"], at: end)
                end += 2
            }
        }
        return joined()
    }

    /// The lines without our items, with keys we added dropped once empty, and `hooks:` restored.
    /// Only the `hooks:` block is touched.
    static func strip(_ input: [String]) -> [String] {
        var lines = input
        guard let block = hooksBlock(lines) else { return lines }
        let hooksAt = block.lowerBound - 1
        var end = block.upperBound
        // Our items, each with its continuation lines (a block-style item's other keys).
        var i = block.lowerBound
        while i < end {
            let b = lines[i].trimmingCharacters(in: .whitespaces)
            guard b.hasPrefix("-"), commandValue(b).map(HookCommand.isOurs) ?? false else { i += 1; continue }
            let ind = indent(lines[i])
            var n = 1
            while i + n < end, !lines[i + n].trimmingCharacters(in: .whitespaces).isEmpty, indent(lines[i + n]) > ind { n += 1 }
            lines.removeSubrange(i..<(i + n))
            end -= n
        }
        // Keys we added: keep them (untagged) if the user put their own items under them.
        // Bottom-up, so event keys are settled before `hooks:` looks at what is left under it.
        for i in (hooksAt..<end).reversed() {
            let line = lines[i]
            guard line.hasSuffix(tag) || line.contains("\(tag) was: "), line.first == " " || i == hooksAt else { continue }
            let ind = indent(line)
            let hasChildren = lines[(i + 1)...].prefix { l in
                let b = l.trimmingCharacters(in: .whitespaces)
                return b.isEmpty || indent(l) > ind || (indent(l) == ind && b.hasPrefix("-"))
            }.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if hasChildren {
                lines[i] = line.components(separatedBy: " \(tag)").first!
            } else if i == hooksAt, let was = line.components(separatedBy: "\(tag) was: ").dropFirst().first {
                lines[i] = "hooks: \(was)"
            } else {
                lines.remove(at: i)
            }
        }
        return lines
    }
}
