import Foundation

/// A release version, `major.minor.patch` (a leading `v` and missing parts allowed), ordered numerically.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    public init?(_ s: String) {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.first == "v" || t.first == "V" { t.removeFirst() }
        let p = t.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !p.isEmpty, p.count <= 4, p.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        parts = p.map { $0! }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

/// The parts of GitHub's "latest release" answer the updater uses.
public struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browserDownloadURL: URL
        public let size: Int?
        enum CodingKeys: String, CodingKey { case name, size, browserDownloadURL = "browser_download_url" }
    }

    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", name, body, htmlURL = "html_url", draft, prerelease, assets
    }

    public var version: AppVersion? { AppVersion(tagName) }

    /// The app archive: `YaaKanban-<version>.zip` by the release script's naming, else any zip.
    public var archive: Asset? {
        assets.first { $0.name.hasPrefix("YaaKanban") && $0.name.hasSuffix(".zip") }
            ?? assets.first { $0.name.hasSuffix(".zip") }
    }

    /// This release, if it is a published, final release newer than `current` with an archive.
    public func offer(over current: AppVersion) -> GitHubRelease? {
        guard !draft, !prerelease, let v = version, v > current, archive != nil else { return nil }
        return self
    }
}

public enum ReleaseNotes {
    /// The notes of one version from a Keep a Changelog file (`## [0.1.1] - date` or `## 0.1.1`),
    /// without its heading; nil when the version has no section or the section is empty.
    public static func section(_ version: String, in changelog: String) -> String? {
        var out: [Substring] = []
        var inside = false
        for line in changelog.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                if inside { break }
                let head = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                let name = head.split(separator: " ").first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) }
                inside = name.flatMap(AppVersion.init) == AppVersion(version) && AppVersion(version) != nil
                continue
            }
            if inside { out.append(line) }
        }
        let text = out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// A short plain-text excerpt of Markdown notes for an alert: headings and emphasis dropped,
    /// at most `lines` lines.
    public static func excerpt(_ markdown: String, lines: Int = 12) -> String {
        var kept: [String] = []
        for raw in markdown.split(separator: "\n") {
            var l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("<!--") { continue }
            if l.hasPrefix("#") { l = l.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }
            if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
            l = l.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            kept.append(l)
        }
        if kept.count > lines { kept = Array(kept.prefix(lines)) + ["…"] }
        return kept.joined(separator: "\n")
    }
}
