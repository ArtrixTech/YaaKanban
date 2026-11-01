import Foundation

/// The blocks of an agent's Markdown reply, for drawing it instead of showing its source. Inline
/// marks (bold, code, links) stay in each block's text; the view parses those.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// `marker` is "•" or the item's number with its dot ("3.").
    case listItem(indent: Int, marker: String, text: String)
    case code(language: String?, text: String)
    case quote(String)
    case table(header: [String], rows: [[String]])
    case rule

    /// Characters a reader sees, for deciding where a long reply folds.
    public var length: Int {
        switch self {
        case .heading(_, let t), .paragraph(let t), .listItem(_, _, let t), .code(_, let t), .quote(let t): t.count
        case .table(let h, let r): (h + r.flatMap { $0 }).reduce(0) { $0 + $1.count }
        case .rule: 0
        }
    }
}

public enum Markdown {
    public static func blocks(_ source: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var para: [String] = []
        var quote: [String] = []
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] }
            if !quote.isEmpty { out.append(.quote(quote.joined(separator: "\n"))); quote = [] }
        }
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if let (mark, n) = fence(t) {
                flush()
                let lang = t.dropFirst(n).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                // Closed by a line of only the same mark, at least as long (so a longer fence can hold a shorter one).
                func closes(_ l: String) -> Bool {
                    let c = l.trimmingCharacters(in: .whitespaces)
                    return c.count >= n && c.allSatisfy { $0 == mark }
                }
                while i < lines.count, !closes(lines[i]) { code.append(lines[i]); i += 1 }
                out.append(.code(language: lang.isEmpty ? nil : lang, text: code.joined(separator: "\n")))
                i += 1
                continue
            }
            if t.isEmpty { flush(); i += 1; continue }
            if let h = heading(t) { flush(); out.append(h); i += 1; continue }
            if isRule(t) { flush(); out.append(.rule); i += 1; continue }
            if t.hasPrefix(">") {
                if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] }
                quote.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                i += 1
                continue
            }
            if let item = listItem(line) { flush(); out.append(item); i += 1; continue }
            if t.hasPrefix("|"), i + 1 < lines.count, isTableRule(lines[i + 1]) {
                flush()
                let header = cells(t)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                out.append(.table(header: header, rows: rows))
                continue
            }
            // A line under a list item, indented, carries on that item.
            if para.isEmpty, quote.isEmpty, line.hasPrefix("  "), case .listItem(let n, let m, let text)? = out.last {
                out[out.count - 1] = .listItem(indent: n, marker: m, text: text + "\n" + t)
                i += 1
                continue
            }
            if !quote.isEmpty { flush() }
            para.append(t)
            i += 1
        }
        flush()
        return out
    }

    /// The blocks a folded reply shows: whole blocks up to about `limit` characters; a first block
    /// far longer than that is cut.
    public static func folded(_ blocks: [MarkdownBlock], limit: Int) -> [MarkdownBlock] {
        var n = 0, out: [MarkdownBlock] = []
        for b in blocks {
            if !out.isEmpty, n + b.length > limit { break }
            out.append(out.isEmpty && b.length > limit * 2 ? cut(b, limit) : b)
            n += b.length
        }
        return out
    }

    static func cut(_ b: MarkdownBlock, _ n: Int) -> MarkdownBlock {
        func c(_ t: String) -> String { String(t.prefix(n)) + "…" }
        switch b {
        case .paragraph(let t): return .paragraph(c(t))
        case .quote(let t): return .quote(c(t))
        case .code(let l, let t): return .code(language: l, text: c(t))
        case .listItem(let i, let m, let t): return .listItem(indent: i, marker: m, text: c(t))
        case .table(let h, let r): return .table(header: h, rows: Array(r.prefix(max(1, n / 80))))
        case .heading, .rule: return b
        }
    }

    /// A fence opening a code block: its mark and length. A backtick fence whose info string has a
    /// backtick is not one (``` `x` ``` on one line is inline code).
    static func fence(_ t: String) -> (Character, Int)? {
        guard let mark = t.first, mark == "`" || mark == "~" else { return nil }
        let n = t.prefix { $0 == mark }.count
        guard n >= 3, mark == "~" || !t.dropFirst(n).contains("`") else { return nil }
        return (mark, n)
    }

    static func heading(_ t: String) -> MarkdownBlock? {
        let hashes = t.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), t.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: t.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
    }

    static func isRule(_ t: String) -> Bool {
        let c = t.replacingOccurrences(of: " ", with: "")
        return c.count >= 3 && (Set(c) == ["-"] || Set(c) == ["*"] || Set(c) == ["_"])
    }

    static func listItem(_ line: String) -> MarkdownBlock? {
        let lead = line.prefix { $0 == " " || $0 == "\t" }
        let t = line.dropFirst(lead.count)
        // A tab is a level of its own; more than a few levels draw as the deepest.
        let indent = min(6, lead.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2)
        for m in ["- ", "* ", "+ "] where t.hasPrefix(m) {
            var text = String(t.dropFirst(2))
            // Task lists: keep the box as a mark.
            if text.hasPrefix("[ ] ") { text = "☐ " + text.dropFirst(4) } else if text.lowercased().hasPrefix("[x] ") { text = "☑ " + text.dropFirst(4) }
            return .listItem(indent: indent, marker: "•", text: text)
        }
        let digits = t.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3, t.dropFirst(digits.count).hasPrefix(". ") || t.dropFirst(digits.count).hasPrefix(") ") {
            return .listItem(indent: indent, marker: digits + ".", text: String(t.dropFirst(digits.count + 2)))
        }
        return nil
    }

    static func isTableRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("|") && t.contains("-") && t.allSatisfy { "|-: ".contains($0) }
    }

    static func cells(_ row: String) -> [String] {
        var r = row
        if r.hasPrefix("|") { r.removeFirst() }
        if r.hasSuffix("|") { r.removeLast() }
        return r.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
