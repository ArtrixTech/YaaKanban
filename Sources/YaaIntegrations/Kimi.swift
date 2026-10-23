import Foundation
import YaaCore

/// Kimi Code (`kimi`) reads `[[hooks]]` tables from `~/.kimi-code/config.toml`, the user's whole
/// config. Unknown keys make the file fail to load, so each of our tables holds only `event`,
/// `command` and `timeout`, and is recognised by its command. The file is edited as text: our tables
/// are removed and appended at the end, where an array-of-tables header cannot swallow other keys.
/// Its PermissionRequest hook is notify-only, so approvals stay in the terminal.
public struct KimiIntegration: Integration {
    public let agent = AgentKind.kimi
    public init() {}
    public var postInstallNote: String? {
        String(localized: "Kimi Code hooks can't answer permission requests: the card shows it's waiting on you, but you approve in the terminal. If you changed KIMI_CODE_HOME, the hooks aren't installed there.")
    }

    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                         "PermissionRequest", "PermissionResult", "Stop", "Interrupt", "StopFailure", "SessionEnd"]

    func file(_ home: URL) -> URL { home.appendingPathComponent(".kimi-code/config.toml") }
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".kimi-code").path) }
    public func isInstalled(home: URL) -> Bool { Installer.read(file(home)).map(HookCommand.isOurs) ?? false }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        let url = file(home)
        let before = Installer.read(url)
        let tables = install ? Self.events.map { Self.table(event: $0, command: HookCommand.make(yaak: yaak, agent: agent, event: $0)) } : []
        let after = try Self.edit(before ?? "", tables: tables)
        if after == (before ?? "") { return [] }
        // A file left empty held only our hooks (we created it); remove it.
        let empty = after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty && before == nil { return [] }
        return [FileChange(path: url, before: before, after: empty ? nil : after)]
    }

    // MARK: TOML

    static func table(event: String, command: String) -> [String] {
        ["[[hooks]]", "event = \(quote(event))", "command = \(quote(command))", "timeout = 5"]
    }

    /// A TOML basic string.
    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case _ where u.value < 0x20 || u.value == 0x7f: out += String(format: "\\u%04X", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        return out + "\""
    }

    /// Removes our `[[hooks]]` tables, then appends `tables`. Keys the user added to a table of ours
    /// (`matcher`, `cwd`) move to the new table for the same event. Leaves the text alone when its
    /// tables of ours are already exactly those, at the end (the file is then rewritten to the same text).
    static func edit(_ text: String, tables: [[String]]) throws -> String {
        let crlf = text.contains("\r\n")
        var lines = text.isEmpty ? [] : text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        func joined(_ ls: [String]) -> String {
            ls.isEmpty ? "" : ls.joined(separator: crlf ? "\r\n" : "\n") + (crlf ? "\r\n" : "\n")
        }
        let topLevel = lines.prefix { !isHeader($0) }
        if topLevel.contains(where: { key($0).map { $0 == "hooks" || $0.hasPrefix("hooks.") } ?? false })
            || lines.contains(where: { header($0).map { $0 == "[hooks]" || $0.hasPrefix("[hooks.") || $0.hasPrefix("[[hooks.") } ?? false }) {
            throw IntegrationError.refused("hooks in Kimi config.toml is not written as [[hooks]] tables; refusing to edit it")
        }
        var (kept, extras) = strip(lines)
        while kept.last.map({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) == true { kept.removeLast() }
        for t in tables {
            if !kept.isEmpty { kept.append("") }
            kept += t
            if let event = t.first(where: { key($0) == "event" }).map(value) { kept += extras[event] ?? [] }
        }
        return joined(kept)
    }

    static func isHeader(_ l: String) -> Bool { l.trimmingCharacters(in: .whitespaces).hasPrefix("[") }

    /// Quotes and whitespace dropped, so `[ "hooks" ]` reads `[hooks]` and `"hooks" . a` reads `hooks.a`.
    static func bare<S: StringProtocol>(_ s: S) -> String { String(s.filter { !" \t\"'".contains($0) }) }

    /// A table header, normalised and without its comment.
    static func header(_ l: String) -> String? {
        let h = bare(l.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        return h.hasPrefix("[") ? h : nil
    }

    /// The key of a `key = value` line, normalised.
    static func key(_ l: String) -> String? {
        let b = l.trimmingCharacters(in: .whitespaces)
        guard !b.hasPrefix("#"), !b.hasPrefix("["), let eq = b.firstIndex(of: "=") else { return nil }
        return bare(b[..<eq])
    }

    /// The value of a `key = value` line, normalised; good for event names, which hold no `#`.
    static func value(_ l: String) -> String {
        l.firstIndex(of: "=").map { bare(l[l.index(after: $0)...].split(separator: "#", omittingEmptySubsequences: false)[0]) } ?? ""
    }

    /// The lines without our tables (each with the blank line we put before it), and the keys the user
    /// added to them, by event. Comments and blank lines after a table of ours belong to whatever
    /// follows, and stay.
    static func strip(_ lines: [String]) -> (lines: [String], extras: [String: [String]]) {
        var out: [String] = []
        var extras: [String: [String]] = [:]
        var i = 0
        while i < lines.count {
            guard header(lines[i]) == "[[hooks]]" else { out.append(lines[i]); i += 1; continue }
            var j = i + 1
            while j < lines.count, !isHeader(lines[j]) { j += 1 }
            let body = lines[(i + 1)..<j]
            let ours = body.contains { key($0) == "command" && HookCommand.isOurs($0) }
            if ours {
                if let event = body.first(where: { key($0) == "event" }).map(value) {
                    extras[event] = body.filter { key($0).map { !["event", "command", "timeout"].contains($0) } ?? false }
                }
                if out.last.map({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) == true { out.removeLast() }
                var end = j
                while end > i + 1, ["", "#"].contains(where: { p in
                    let b = lines[end - 1].trimmingCharacters(in: .whitespaces)
                    return p.isEmpty ? b.isEmpty : b.hasPrefix(p)
                }) { end -= 1 }
                out += lines[end..<j]
            } else {
                out += lines[i..<j]
            }
            i = j
        }
        return (out, extras)
    }
}
