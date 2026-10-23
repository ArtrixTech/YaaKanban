import Foundation
import YaaCore

/// DeepSeek Harness (`dsh`) runs Claude-shaped command hooks through its bridge plugin
/// `@deepseek-ai/dsh-hooks-claude-code`, which dsh does not ship. YaaKanban writes, under
/// `~/.dsh/yaakanban/`, the hooks file and a small dsh bundle that depends on the bridge and mounts it
/// with that file. dsh loads bundles per profile, so adding the bundle to a profile is the user's
/// step (`dsh plugin --profile <name> add …`, which runs pnpm); the app checks the profiles for it.
public struct DeepSeekIntegration: Integration {
    public let agent = AgentKind.deepseek
    public init() {}

    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop",
                         "SubagentStart", "SubagentStop"]
    static let bundleName = "yaakanban-dsh"
    /// Used when no dsh installation is found; the bridge's peers must match dsh's own version.
    static let fallbackVersion = "0.2.1-rc.2"

    func dir(_ home: URL) -> URL { home.appendingPathComponent(".dsh/yaakanban") }
    func hooksFile(_ home: URL) -> URL { dir(home).appendingPathComponent("hooks.json") }
    func bundle(_ home: URL) -> URL { dir(home).appendingPathComponent("bundle") }

    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".dsh").path) }
    public func isInstalled(home: URL) -> Bool { JSONFile.containsOurs(hooksFile(home)) }
    public var postInstallNote: String? { "dsh 的 hook 是实验性接口：没有审批、会话结束事件，也没有 transcript。" }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        // Deleting the bundle under a profile that depends on it would break that profile's installs.
        let users = Self.profilesWithBundle(home: home)
        if !install, !users.isEmpty {
            throw IntegrationError.refused("dsh profile \(users.joined(separator: ", ")) still uses the YaaKanban bundle; first run "
                + users.map { "dsh plugin --profile \($0) remove \(Self.bundleName)" }.joined(separator: "; "))
        }
        var changes = try JSONFile.plan(hooksFile(home)) { root in
            ClaudeShapedHooks.edit(&root, events: Self.events.map { ($0, 5) },
                                   command: { HookCommand.make(yaak: yaak, agent: agent, event: $0) },
                                   install: install, marker: ["_yaakanban": true])
        }
        // An emptied hooks file is ours alone: remove it rather than leave `{}`.
        if !install, let i = changes.indices.first { changes[i].after = nil }
        let version = Self.installedVersion(home: home) ?? Self.fallbackVersion
        let files: [(String, String)] = [
            ("package.json", Self.packageJSON(version: version)),
            ("cordis.patch.yml", Self.patch(hooks: hooksFile(home).path)),
        ]
        for (name, text) in files {
            let url = bundle(home).appendingPathComponent(name)
            let before = Installer.read(url)
            if let before, !before.contains(PluginSource.markerText) {
                throw IntegrationError.refused("\(url.path) exists and is not managed by YaaKanban")
            }
            let after = install ? text : nil
            if before != after { changes.append(FileChange(path: url, before: before, after: after)) }
        }
        return changes
    }

    public func pendingSteps(home: URL) -> [String] {
        guard isInstalled(home: home), Self.profilesWithBundle(home: home).isEmpty else { return [] }
        return ["在终端里运行：dsh plugin --profile web add file:\(bundle(home).path)",
                "用别的 profile 就把 web 换成它的名字（headless、acp…）；每个要用的 profile 都加一次。",
                "重启 dsh，回到这里点「重新检查」。"]
    }

    static func packageJSON(version: String) -> String {
        """
        {
          "name": "\(bundleName)",
          "version": "1.0.0",
          "private": true,
          "description": "\(PluginSource.markerText): mounts the Claude hooks bridge with YaaKanban's hooks",
          "dependencies": {
            "@deepseek-ai/dsh-hooks-claude-code": "\(version)",
            "@deepseek-ai/dsh-hook-protocol": "\(version)"
          },
          "dsh": { "bundle": { "patch": "./cordis.patch.yml" } }
        }

        """
    }

    static func patch(hooks: String) -> String {
        """
        # \(PluginSource.markerText). Mounts the Claude hooks bridge with YaaKanban's hooks file.
        - insert:
            - id: yaakanban-hooks
              name: '@deepseek-ai/dsh-hooks-claude-code'
              config:
                configPath: \(PluginSource.jsString(hooks))

        """
    }

    /// Profiles (`~/.dsh/profiles/<name>/package.json`) that depend on our bundle.
    static func profilesWithBundle(home: URL) -> [String] {
        let profiles = home.appendingPathComponent(".dsh/profiles")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: profiles.path)) ?? []
        return names.filter { name in
            let pkg = profiles.appendingPathComponent(name).appendingPathComponent("package.json")
            guard let root = try? JSONFile.load(pkg).root else { return false }
            return (root["dependencies"] as? [String: Any])?[bundleName] != nil
        }.sorted()
    }

    /// Version of the installed `@deepseek-ai/dsh`, found from a `dsh` launcher in the usual places.
    static func installedVersion(home: URL) -> String? {
        let bins = [".local/bin/dsh", ".npm-global/bin/dsh", ".bun/bin/dsh", ".volta/bin/dsh"].map { home.appendingPathComponent($0).path }
            + ["/opt/homebrew/bin/dsh", "/usr/local/bin/dsh"]
        for bin in bins where FileManager.default.fileExists(atPath: bin) {
            var dir = URL(fileURLWithPath: bin).resolvingSymlinksInPath().deletingLastPathComponent()
            for _ in 0..<4 {
                let pkg = dir.appendingPathComponent("package.json")
                if let root = try? JSONFile.load(pkg).root, root["name"] as? String == "@deepseek-ai/dsh" {
                    return root["version"] as? String
                }
                dir.deleteLastPathComponent()
            }
        }
        return nil
    }
}
