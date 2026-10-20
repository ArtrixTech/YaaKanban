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
}

public protocol Integration: Sendable {
    var agent: AgentKind { get }
    /// Shown after install, e.g. a manual trust step.
    var postInstallNote: String? { get }
    func isDetected(home: URL) -> Bool
    func isInstalled(home: URL) -> Bool
    /// Changes needed to install (or uninstall) YaaKanban hooks. Empty when already in that state.
    func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange]
}

extension Integration {
    public var postInstallNote: String? { nil }

    public func status(home: URL) -> IntegrationStatus {
        if isInstalled(home: home) { return .installed }
        return isDetected(home: home) ? .notInstalled : .notDetected
    }
}

public enum Integrations {
    public static let all: [any Integration] = [ClaudeIntegration(), CodexIntegration(), CursorIntegration(),
                                                OpenCodeIntegration(), PiIntegration()]

    public static func named(_ agent: AgentKind) -> (any Integration)? { all.first { $0.agent == agent } }

    /// Seconds a permission hook waits for the app; agent-side hook timeouts add headroom.
    public static let approvalTimeout = 20
}

public enum HookCommand {
    public static func make(yaak: String, agent: AgentKind, event: String) -> String {
        "'\(yaak)' hook \(agent.rawValue) \(event)"
    }

    /// Recognises any YaaKanban hook command, whatever the yaak path.
    public static func isOurs(_ command: String) -> Bool {
        command.contains("yaak' hook ")
    }
}

public enum Installer {
    public static let backupSuffix = ".yaak.bak"

    /// Writes changes, backing up each existing file first.
    public static func apply(_ changes: [FileChange]) throws {
        let fm = FileManager.default
        for c in changes where !c.isNoop {
            if fm.fileExists(atPath: c.path.path) {
                let bak = URL(fileURLWithPath: c.path.path + backupSuffix)
                try? fm.removeItem(at: bak)
                try fm.copyItem(at: c.path, to: bak)
            }
            if let after = c.after {
                try fm.createDirectory(at: c.path.deletingLastPathComponent(), withIntermediateDirectories: true)
                try after.write(to: c.path, atomically: true, encoding: .utf8)
            } else {
                try? fm.removeItem(at: c.path)
            }
        }
    }

    /// Human-readable description for `--dry-run`.
    public static func describe(_ changes: [FileChange]) -> String {
        changes.filter { !$0.isNoop }.map { c in
            let verb = c.after == nil ? "delete" : (c.before == nil ? "create" : "modify")
            var s = "\(verb) \(c.path.path)\n"
            if let after = c.after { s += after.split(separator: "\n", omittingEmptySubsequences: false).map { "  | \($0)" }.joined(separator: "\n") + "\n" }
            return s
        }.joined(separator: "\n")
    }

    static func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
}
