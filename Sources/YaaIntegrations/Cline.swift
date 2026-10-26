import Foundation
import YaaCore

/// Cline runs a hook file named after each event from `~/Documents/Cline/Hooks`, both in its CLI and in
/// the VS Code extension (which needs the file executable, with no extension). YaaKanban owns one small
/// script per event there and refuses to replace a file someone else wrote.
public struct ClineIntegration: Integration {
    public let agent = AgentKind.cline
    public init() {}
    public var postInstallNote: String? {
        String(localized: "Cline's hooks in VS Code follow its “Enable Hooks” switch (on by default). Cline has no permission-request hook, so approvals still happen in Cline. A task that errors in VS Code fires no hook, so its card ends only when stuck detection kicks in.")
    }

    static let events = ["TaskStart", "TaskResume", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                         "TaskComplete", "TaskCancel", "TaskError"]
    static let marker = "# \(PluginSource.markerText)"

    func dir(_ home: URL) -> URL { home.appendingPathComponent("Documents/Cline/Hooks") }
    public func isDetected(home: URL) -> Bool {
        [".cline", "Documents/Cline"].contains { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) }
    }
    public func isInstalled(home: URL) -> Bool {
        Self.events.contains { Installer.read(dir(home).appendingPathComponent($0))?.contains(Self.marker) ?? false }
    }

    /// Prints `{}` so the extension does not log a missing JSON reply; never fails the tool.
    static func script(yaak: String, event: String) -> String {
        """
        #!/bin/sh
        \(marker) — `yaak uninstall --agent cline` removes this file.
        \(HookCommand.make(yaak: yaak, agent: .cline, event: event)) >/dev/null 2>&1
        echo '{}'
        exit 0

        """
    }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        try Self.events.compactMap { event in
            let url = dir(home).appendingPathComponent(event)
            let before = Installer.read(url)
            // An unreadable (binary) file is someone's hook too.
            if before.map({ !$0.contains(Self.marker) }) ?? FileManager.default.fileExists(atPath: url.path) {
                throw IntegrationError.refused("\(url.path) exists and is not managed by YaaKanban")
            }
            let after = install ? Self.script(yaak: yaak, event: event) : nil
            return before == after ? nil : FileChange(path: url, before: before, after: after, executable: true)
        }
    }
}
