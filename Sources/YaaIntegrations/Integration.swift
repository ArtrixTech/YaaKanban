import Foundation
import YaaCore

/// A pending edit to one file. `after == nil` deletes the file.
public struct FileChange: Equatable, Sendable {
    public var path: URL
    public var before: String?
    public var after: String?

    public var isNoop: Bool { before == after }
}

public enum IntegrationStatus: String, Sendable {
    case notDetected, notInstalled, installed
    /// Installed, but missing hooks a newer version adds (or pointing at another yaak).
    case outdated
    /// Installed, but the agent will not run the hooks until the user approves them there.
    case needsAuthorization
}

public protocol Integration: Sendable {
    var agent: AgentKind { get }
    /// Shown after install and under the agent in Settings: caveats the app cannot check.
    var postInstallNote: String? { get }
    /// What the user still has to do in the agent before it runs the installed hooks, one step per
    /// line. Empty when nothing is pending, or when the agent keeps no state we can read.
    func pendingSteps(home: URL) -> [String]
    func isDetected(home: URL) -> Bool
    func isInstalled(home: URL) -> Bool
    /// Changes needed to install (or uninstall) YaaKanban hooks. Empty when already in that state.
    func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange]
}

extension Integration {
    public var postInstallNote: String? { nil }
    public func pendingSteps(home: URL) -> [String] { [] }

    public func status(home: URL) -> IntegrationStatus {
        if isInstalled(home: home) { return .installed }
        return isDetected(home: home) ? .notInstalled : .notDetected
    }

    /// Like `status(home:)`, and `.outdated` when installing again would change something, or
    /// `.needsAuthorization` while the agent waits for the user to approve the hooks.
    public func status(home: URL, yaak: String) -> IntegrationStatus {
        let s = status(home: home)
        guard s == .installed else { return s }
        // A config we can no longer edit (comments added, layout refused): updating shows why.
        guard let plan = try? plan(install: true, home: home, yaak: yaak) else { return .outdated }
        if !plan.allSatisfy(\.isNoop) { return .outdated }
        return pendingSteps(home: home).isEmpty ? s : .needsAuthorization
    }
}

public enum Integrations {
    public static let all: [any Integration] = [ClaudeIntegration(), CodexIntegration(), CursorIntegration(),
                                                OpenCodeIntegration(), PiIntegration(), HermesIntegration(),
                                                DeepSeekIntegration(), QwenIntegration(), DroidIntegration(),
                                                CopilotIntegration(), GeminiIntegration()]

    public static func named(_ agent: AgentKind) -> (any Integration)? { all.first { $0.agent == agent } }

    /// Seconds a permission hook waits for the app; agent-side hook timeouts add headroom.
    public static let approvalTimeout = 20
}

public enum HookCommand {
    public static func make(yaak: String, agent: AgentKind, event: String) -> String {
        "\(shellQuote(yaak)) hook \(agent.rawValue) \(event)"
    }

    /// Recognises any YaaKanban hook command, whatever the yaak path (quoting included).
    public static func isOurs(_ command: String) -> Bool {
        command.contains("yaak' hook ") || command.contains("yaak hook ")
    }
}

public enum Installer {
    public static let backupSuffix = ".yaak.bak"

    /// Writes changes, backing up each existing file first.
    public static func apply(_ changes: [FileChange]) throws {
        let fm = FileManager.default
        for c in changes where !c.isNoop {
            // Write through symlinks (dotfile managers) instead of replacing the link with a file.
            let target = c.path.resolvingSymlinksInPath()
            if fm.fileExists(atPath: target.path) {
                let bak = URL(fileURLWithPath: c.path.path + backupSuffix)
                try? fm.removeItem(at: bak)
                try Data(contentsOf: target).write(to: bak)
            }
            if let after = c.after {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try after.write(to: target, atomically: true, encoding: .utf8)
            } else {
                try? fm.removeItem(at: c.path)
            }
        }
    }

    /// Human-readable description for `--dry-run`. Agent configs hold API keys next to the hooks,
    /// so values of secret-looking keys are masked.
    public static func describe(_ changes: [FileChange]) -> String {
        changes.filter { !$0.isNoop }.map { c in
            let verb = c.after == nil ? "delete" : (c.before == nil ? "create" : "modify")
            var s = "\(verb) \(c.path.path)\n"
            if let after = c.after { s += redact(after).split(separator: "\n", omittingEmptySubsequences: false).map { "  | \($0)" }.joined(separator: "\n") + "\n" }
            return s
        }.joined(separator: "\n")
    }

    /// Masks secrets: values of JSON, YAML, TOML and `export` keys naming a token, key, secret or
    /// password (not `max_tokens` or `author`), the lines of such a key's block scalar, the argument
    /// after a `--token`-like flag, `Bearer` credentials and well-known key prefixes.
    static func redact(_ text: String) -> String {
        let word = #"(?:[A-Za-z0-9]+[_.-])*(?:token|secret|password|passwd|pass|api[_-]?key|apikey|key|access[_-]?key|private[_-]?key|auth|authorization|credentials?|cookie)"#
        let key = #"["']?"# + word + #"(?:[_.-](?:id|value))?["']?"#
        let value = #"("(?:[^"\\\n]|\\.)*"|'[^'\n]*'|[^\s,{}\[\]"'][^,{}\[\]\n]*)"#
        let rules = [
            #"(?i)(?<![A-Za-z0-9_.-])"# + key + #"\s*[:=]\s*"# + value,
            #"(?i)--(?:[a-z0-9]+-)*(?:token|secret|password|api-?key|key|auth)(?![A-Za-z0-9-])(?:=|["\s,]+)("[^"\n]*"|[^\s"',\]]+)"#,
            #"(?i)\bbearer\s+([A-Za-z0-9._~+/=-]{8,})"#,
            #"\b((?:sk|pk|rk)-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|xox[abpr]-[A-Za-z0-9-]{8,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,})"#,
        ]
        var out = text
        for pattern in rules {
            let re = try! NSRegularExpression(pattern: pattern)
            for m in re.matches(in: out, range: NSRange(location: 0, length: (out as NSString).length)).reversed() {
                let r = m.range(at: 1)
                var v = (out as NSString).substring(with: r)
                // An unquoted value ends at a ` #` comment and before trailing spaces.
                if !v.hasPrefix("\""), !v.hasPrefix("'"), let c = v.range(of: " #") { v = String(v[..<c.lowerBound]) }
                v = v.trimmingCharacters(in: .whitespaces)
                let plain = v.lowercased()
                if ["true", "false", "null", "~", "|", ">", "|-", ">-", "|+", ">+", "<redacted>", "\"<redacted>\""].contains(plain)
                    || v.isEmpty || v.allSatisfy(\.isNumber) { continue }
                let masked = v.first == "\"" ? "\"<redacted>\"" : v.first == "'" ? "'<redacted>'" : "<redacted>"
                out = (out as NSString).replacingCharacters(in: NSRange(location: r.location, length: (v as NSString).length), with: masked)
            }
        }
        return redactBlockScalars(out, key: key)
    }

    /// `api_key: |` followed by indented lines: mask those lines.
    private static func redactBlockScalars(_ text: String, key: String) -> String {
        let head = try! NSRegularExpression(pattern: #"(?i)^\s*(?:-\s*)?"# + key + #"\s*:\s*[|>][-+]?\s*(#.*)?$"#)
        var lines = text.components(separatedBy: "\n"), i = 0
        while i < lines.count {
            let l = lines[i]
            guard head.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) != nil else { i += 1; continue }
            let ind = l.prefix { $0 == " " }.count
            i += 1
            while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty || lines[i].prefix(while: { $0 == " " }).count > ind {
                if !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    lines[i] = String(repeating: " ", count: ind + 2) + "<redacted>"
                }
                i += 1
            }
        }
        return lines.joined(separator: "\n")
    }

    static func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
}

/// Hooks call yaak through a fixed symlink to the app's binary, so moving or reinstalling the app does
/// not change the hook commands, which Codex and Hermes would then make the user approve again.
public enum StableYaak {
    public static func link(home: URL) -> URL { home.appendingPathComponent(".local/share/yaakanban/bin/yaak") }

    /// Points the link at `target` and returns its path. Leaves anything that is not a symlink alone.
    /// The new link is made beside it and renamed over it, so hooks never see the path missing.
    @discardableResult
    public static func ensure(home: URL, target: String) throws -> String {
        let fm = FileManager.default
        let link = link(home: home)
        if let dest = try? fm.destinationOfSymbolicLink(atPath: link.path) {
            if dest == target { return link.path }
        } else if fm.fileExists(atPath: link.path) {
            throw IntegrationError.refused("\(link.path) exists and is not a symlink")
        }
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = link.deletingLastPathComponent().appendingPathComponent(".yaak-\(UUID().uuidString)")
        try fm.createSymbolicLink(atPath: temp.path, withDestinationPath: target)
        guard rename(temp.path, link.path) == 0 else {
            try? fm.removeItem(at: temp)
            throw IntegrationError.refused("cannot update \(link.path)")
        }
        return link.path
    }

    /// Whether an app at `bundle` may take the link over: an installed copy may; a build folder,
    /// a mounted disk image or a translocated (quarantined) copy may only while the link points
    /// nowhere that exists, so ejecting or cleaning them does not break every hook.
    public static func mayClaim(bundle: URL, home: URL) -> Bool {
        let path = bundle.standardizedFileURL.path
        if path.hasPrefix("/Applications/") || path.hasPrefix(home.appendingPathComponent("Applications").path + "/") {
            return !path.contains("/AppTranslocation/")
        }
        let current = (try? FileManager.default.destinationOfSymbolicLink(atPath: link(home: home).path)) ?? ""
        return current.isEmpty || !FileManager.default.fileExists(atPath: current)
    }
}
