import Foundation
import Testing
@testable import YaaIntegrations
import YaaCore

private func tempHome() throws -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-home-\(UUID().uuidString)")
    for d in [".claude", ".codex", ".cursor", ".config/opencode", ".pi/agent"] {
        try FileManager.default.createDirectory(at: u.appendingPathComponent(d), withIntermediateDirectories: true)
    }
    return u
}

private let yaak = "/Apps/YaaKanban.app/Contents/Helpers/yaak"
private let adrafinil = "/Applications/Adrafinil.app/Contents/Helpers/adrafinil release --tool codex"

private func json(_ url: URL) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
}

@Suite struct InstallerTests {
    /// Failed calls only fire PostToolUseFailure; without it they look running forever.
    @Test func claudeGetsToolFailureHook() throws {
        let home = try tempHome()
        try Installer.apply(try ClaudeIntegration().plan(install: true, home: home, yaak: yaak))
        let text = try String(contentsOf: home.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
        #expect(text.contains("PostToolUseFailure"))
        #expect(ClaudeIntegration().status(home: home, yaak: yaak) == .installed)
        #expect(ClaudeIntegration().status(home: home, yaak: "/other/yaak") == .outdated)
    }

    @Test func claudePreservesForeignHooksAndIsIdempotent() throws {
        let home = try tempHome()
        let f = home.appendingPathComponent(".claude/settings.json")
        try #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"other"}]}]}}"#.write(to: f, atomically: true, encoding: .utf8)
        let i = ClaudeIntegration()
        #expect(i.status(home: home) == .notInstalled)

        try Installer.apply(try i.plan(install: true, home: home, yaak: yaak))
        #expect(i.status(home: home) == .installed)
        let root = try json(f)
        #expect(root["model"] as? String == "opus")
        let stop = (root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(stop.count == 2)
        #expect(((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String) == "other")
        let ours = (stop[1]["hooks"] as! [[String: Any]])[0]
        #expect(ours["command"] as? String == "'\(yaak)' hook claude-code Stop")
        let perm = ((root["hooks"] as! [String: Any])["PermissionRequest"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]]
        #expect(perm[0]["timeout"] as? Int == 30)
        #expect(FileManager.default.fileExists(atPath: f.path + Installer.backupSuffix))

        #expect(try i.plan(install: true, home: home, yaak: yaak).isEmpty)

        try Installer.apply(try i.plan(install: false, home: home, yaak: yaak))
        #expect(i.status(home: home) == .notInstalled)
        let back = try json(f)
        #expect(NSDictionary(dictionary: back).isEqual(to: try JSONSerialization.jsonObject(with: Data(#"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"other"}]}]}}"#.utf8)) as! [String: Any]))
    }

    @Test func codexAppendsAfterExistingEntries() throws {
        let home = try tempHome()
        let f = home.appendingPathComponent(".codex/hooks.json")
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\#(adrafinil)"}]}]}}"#.write(to: f, atomically: true, encoding: .utf8)
        try Installer.apply(try CodexIntegration().plan(install: true, home: home, yaak: yaak))
        let stop = (try json(f)["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String) == adrafinil)
        #expect(stop.count == 2)
        #expect(((stop[1]["hooks"] as! [[String: Any]])[0]["_yaakanban"]) == nil)
    }

    @Test func quotedPathRunsUnderSh() throws {
        let cmd = HookCommand.make(yaak: "/tmp/o'neil/yaak", agent: .claudeCode, event: "Stop")
        #expect(HookCommand.isOurs(cmd))
        #expect(HookCommand.isOurs("'\(yaak)' hook claude-code Stop"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-n", "-c", cmd]
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }

    /// Codex trust is keyed by index: a reinstall (even with a new yaak path) must not move our entry.
    @Test func codexReinstallKeepsOrder() throws {
        let home = try tempHome()
        let f = home.appendingPathComponent(".codex/hooks.json")
        try Installer.apply(try CodexIntegration().plan(install: true, home: home, yaak: yaak))
        var root = try json(f)
        var hooks = root["hooks"] as! [String: Any]
        var stop = hooks["Stop"] as! [[String: Any]]
        stop.append(["hooks": [["type": "command", "command": "user-hook"]]])
        hooks["Stop"] = stop
        root["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: root).write(to: f)

        try Installer.apply(try CodexIntegration().plan(install: true, home: home, yaak: "/New/yaak"))
        let after = (try json(f)["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(after.count == 2)
        #expect(((after[0]["hooks"] as! [[String: Any]])[0]["command"] as? String) == "'/New/yaak' hook codex Stop")
        #expect(((after[1]["hooks"] as! [[String: Any]])[0]["command"] as? String) == "user-hook")
    }

    /// Duplicates of ours and empty groups must not be dropped on Codex reinstall: that would shift
    /// the indexes of the foreign hooks after them.
    @Test func codexReinstallNeverDropsEntries() throws {
        let home = try tempHome()
        let f = home.appendingPathComponent(".codex/hooks.json")
        let old = "'/Old/yaak' hook codex"
        try """
        {"hooks":{
          "Stop":[{"hooks":[{"type":"command","command":"\(old) Stop"},{"type":"command","command":"\(old) Stop"},
                            {"type":"command","command":"a"}]},
                  {"hooks":[{"type":"command","command":"\(old) Stop"}]},
                  {"hooks":[]},
                  {"hooks":[{"type":"command","command":"b"}]}],
          "SessionEnd":[{"hooks":[{"type":"command","command":"\(old) SessionEnd"}]},
                        {"hooks":[{"type":"command","command":"c"}]}]}}
        """.write(to: f, atomically: true, encoding: .utf8)

        try Installer.apply(try CodexIntegration().plan(install: true, home: home, yaak: yaak))
        let hooks = try json(f)["hooks"] as! [String: Any]
        let cmds = { (e: String) in (hooks[e] as! [[String: Any]]).map { ($0["hooks"] as! [[String: Any]]).map { $0["command"] as! String } } }
        let new = "'\(yaak)' hook codex"
        #expect(cmds("Stop") == [["\(new) Stop", "\(new) Stop", "a"], ["\(new) Stop"], [], ["b"]])
        #expect(cmds("SessionEnd") == [["\(new) SessionEnd"], ["c"]])
        #expect(try CodexIntegration().plan(install: true, home: home, yaak: yaak).isEmpty)

        // Uninstall removes ours; the user re-trusts what moved.
        try Installer.apply(try CodexIntegration().plan(install: false, home: home, yaak: yaak))
        let back = try json(f)["hooks"] as! [String: Any]
        #expect((back["Stop"] as! [[String: Any]]).count == 3)
        #expect(!HookCommand.isOurs(try String(contentsOf: f, encoding: .utf8)))
    }

    @Test func symlinkedConfigIsEditedInPlace() throws {
        let home = try tempHome()
        let real = home.appendingPathComponent("dotfiles-settings.json")
        try #"{"model":"opus"}"#.write(to: real, atomically: true, encoding: .utf8)
        let link = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try Installer.apply(try ClaudeIntegration().plan(install: true, home: home, yaak: yaak))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == real.path)
        #expect(try json(real)["hooks"] != nil)
        let bak = link.path + Installer.backupSuffix
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: bak)) == nil)
        #expect(try String(contentsOfFile: bak, encoding: .utf8) == #"{"model":"opus"}"#)
    }

    @Test func cursorCreatesVersionedFile() throws {
        let home = try tempHome()
        let i = CursorIntegration()
        try Installer.apply(try i.plan(install: true, home: home, yaak: yaak))
        let root = try json(home.appendingPathComponent(".cursor/hooks.json"))
        #expect(root["version"] as? Int == 1)
        #expect(((root["hooks"] as! [String: Any])["stop"] as! [[String: Any]]).count == 1)
        try Installer.apply(try i.plan(install: false, home: home, yaak: yaak))
        #expect(i.status(home: home) == .notInstalled)
    }

    @Test func pluginFilesRoundTrip() throws {
        let home = try tempHome()
        for i: any Integration in [OpenCodeIntegration(), PiIntegration()] {
            try Installer.apply(try i.plan(install: true, home: home, yaak: yaak))
            #expect(i.status(home: home) == .installed)
            #expect(try i.plan(install: true, home: home, yaak: yaak).isEmpty)
            try Installer.apply(try i.plan(install: false, home: home, yaak: yaak))
            #expect(i.status(home: home) == .notInstalled)
        }
    }

    @Test func refusesForeignPluginFileAndBadJSON() throws {
        let home = try tempHome()
        let p = home.appendingPathComponent(".pi/agent/extensions/yaakanban.ts")
        try FileManager.default.createDirectory(at: p.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "export default 1".write(to: p, atomically: true, encoding: .utf8)
        #expect(throws: IntegrationError.self) { try PiIntegration().plan(install: true, home: home, yaak: yaak) }
        try "[1,2]".write(to: home.appendingPathComponent(".claude/settings.json"), atomically: true, encoding: .utf8)
        #expect(throws: IntegrationError.self) { try ClaudeIntegration().plan(install: true, home: home, yaak: yaak) }
    }

    @Test func notDetectedWithoutAgentDir() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString)")
        #expect(Integrations.all.allSatisfy { $0.status(home: home) == .notDetected })
    }
}

@Suite struct AuthorizationTests {
    private func home(_ dirs: [String]) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-auth-\(UUID().uuidString)")
        for d in dirs { try FileManager.default.createDirectory(at: u.appendingPathComponent(d), withIntermediateDirectories: true) }
        return u
    }

    /// Values from codex-rs core/tests/suite/hooks.rs (declaration-only plugin hook approvals).
    @Test func codexHashMatchesCodex() {
        let c = "python3 -I -S ${PLUGIN_ROOT}/hooks/pre_tool_use_hook.py"
        #expect(CodexTrust.hash(label: "pre_tool_use", matcher: "^Bash$", handler: ["type": "command", "command": c])
                == "sha256:c9ee1aca1b5d8c72b99df6571c87d61350b09f7f4594ae30e7250a2027e9d76b")
        #expect(CodexTrust.hash(label: "post_tool_use", matcher: "^Bash$", handler: ["type": "command", "command": c])
                == "sha256:9eef43ad6f26b1f9b94f318a50445f8bb62c363da08152a2966b73d308bf42ba")
        // Same as the reference implementation for one of our own hooks.
        #expect(CodexTrust.hash(label: "stop", matcher: nil, handler: ["command": "'/x/yaak' hook codex Stop", "timeout": 5])
                == "sha256:5adc37758d7b3dd3d80c15b9fced3fd820b64b88e51c98f29215de22ddcb292e")
    }

    @Test func codexTrustStates() throws {
        let h = try home([".codex"])
        let i = CodexIntegration()
        try Installer.apply(try i.plan(install: true, home: h, yaak: yaak))
        #expect(i.status(home: h, yaak: yaak) == .needsAuthorization)
        #expect(i.pendingSteps(home: h).contains { $0.contains("8 条未信任") })

        // Trust every hook as Codex would, then change one, disable one.
        let hooks = try json(h.appendingPathComponent(".codex/hooks.json"))["hooks"] as! [String: Any]
        let path = h.appendingPathComponent(".codex/hooks.json").path
        var toml = "[features]\nhooks = true\n\n[hooks.state]\n"
        for (event, groups) in hooks {
            let label = CodexTrust.labels[event]!
            let handler = ((groups as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
            let hash = event == "Stop" ? "sha256:old" : CodexTrust.hash(label: label, matcher: nil, handler: handler)
            toml += "\n[hooks.state.\"\(path):\(label):0:0\"]\ntrusted_hash = \"\(hash)\"\n"
            if event == "PreToolUse" { toml += "enabled = false\n" }
        }
        try toml.write(to: h.appendingPathComponent(".codex/config.toml"), atomically: true, encoding: .utf8)
        let states = Dictionary(uniqueKeysWithValues: CodexTrust.states(home: h).map { ($0.event, $0.state) })
        #expect(states["Stop"] == .modified)
        #expect(states["PreToolUse"] == .disabled)
        #expect(states["SessionStart"] == .trusted)
        let steps = i.pendingSteps(home: h)
        #expect(steps.contains { $0.contains("1 条 yaak hook 在你信任之后变了") })
        #expect(steps.contains { $0.contains("重新启用 1 条") })

        // All trusted.
        try toml.replacingOccurrences(of: "sha256:old", with: CodexTrust.hash(label: "stop", matcher: nil,
            handler: ((hooks["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]))
            .replacingOccurrences(of: "enabled = false\n", with: "")
            .write(to: h.appendingPathComponent(".codex/config.toml"), atomically: true, encoding: .utf8)
        #expect(i.pendingSteps(home: h).isEmpty)
        #expect(i.status(home: h, yaak: yaak) == .installed)

        // Trusted but the feature is off: nothing runs.
        let config = h.appendingPathComponent(".codex/config.toml")
        try (try String(contentsOf: config, encoding: .utf8)).replacingOccurrences(of: "hooks = true", with: "hooks = false  # off")
            .write(to: config, atomically: true, encoding: .utf8)
        #expect(i.status(home: h, yaak: yaak) == .needsAuthorization)
        #expect(i.pendingSteps(home: h)[0].contains("hooks = false"))
    }

    @Test func codexStateHeaderWithComment() {
        let s = CodexTrust.readState("[hooks.state.\"/h/.codex/hooks.json:stop:0:0\"] # note\ntrusted_hash = \"sha256:x\"\nenabled = false\n")
        #expect(s["/h/.codex/hooks.json:stop:0:0"]?.trustedHash == "sha256:x")
        #expect(s["/h/.codex/hooks.json:stop:0:0"]?.enabled == false)
    }

    private let adrafinilBlock = """
    model: x
    hooks:
      # >>> adrafinil (managed)
      on_session_start:
        - command: "'/A/adrafinil' acquire --tool hermes"
      on_session_end:
        - command: "'/A/adrafinil' release --tool hermes"
      # <<< adrafinil

    # trailing comment
    display:
      skin: default

    """

    @Test func hermesMergesIntoExistingHooks() throws {
        let h = try home([".hermes"])
        let f = h.appendingPathComponent(".hermes/config.yaml")
        try adrafinilBlock.write(to: f, atomically: true, encoding: .utf8)
        let i = HermesIntegration()
        #expect(i.status(home: h) == .notInstalled)
        try Installer.apply(try i.plan(install: true, home: h, yaak: yaak))
        let text = try String(contentsOf: f, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        // on_session_end keeps one key, adrafinil's item first, ours after it.
        #expect(lines.filter { $0.hasPrefix("  on_session_end:") }.count == 1)
        let end = lines.firstIndex(of: "  on_session_end:")!
        #expect(lines[end + 1].contains("adrafinil"))
        // Ours goes after adrafinil's closing marker, so rewriting its section leaves ours alone.
        #expect(lines[end + 2] == "  # <<< adrafinil")
        #expect(lines[end + 3].contains("hook hermes on_session_end"))
        #expect(lines.contains("  pre_llm_call: \(HermesIntegration.tag)"))
        #expect(text.contains("display:\n  skin: default"))
        #expect(lines.firstIndex { $0.contains("pre_llm_call") }! < lines.firstIndex(of: "# trailing comment")!)
        #expect(HermesIntegration.ours(text).count == HermesIntegration.events.count)
        #expect(Set(HermesIntegration.ours(text).map(\.event)) == Set(HermesIntegration.events))
        #expect(i.status(home: h, yaak: yaak) == .needsAuthorization)
        #expect(try i.plan(install: true, home: h, yaak: yaak).isEmpty)

        // A new yaak path rewrites our lines in place.
        try Installer.apply(try i.plan(install: true, home: h, yaak: "/New/yaak"))
        let moved = try String(contentsOf: f, encoding: .utf8)
        #expect(!moved.contains(yaak) && moved.components(separatedBy: "/New/yaak").count - 1 == HermesIntegration.events.count)

        try Installer.apply(try i.plan(install: false, home: h, yaak: yaak))
        #expect(try String(contentsOf: f, encoding: .utf8) == adrafinilBlock)
    }

    @Test func hermesWithoutHooksOrFile() throws {
        let h = try home([".hermes"])
        let f = h.appendingPathComponent(".hermes/config.yaml")
        let i = HermesIntegration()
        for original in ["model: x\nhooks: {}\nother: 1\n", "model: x\n", nil] {
            if let original { try original.write(to: f, atomically: true, encoding: .utf8) } else { try? FileManager.default.removeItem(at: f) }
            try Installer.apply(try i.plan(install: true, home: h, yaak: yaak))
            let text = try String(contentsOf: f, encoding: .utf8)
            #expect(HermesIntegration.ours(text).count == HermesIntegration.events.count, "\(original ?? "nil")")
            #expect(try i.plan(install: true, home: h, yaak: yaak).isEmpty)
            try Installer.apply(try i.plan(install: false, home: h, yaak: yaak))
            #expect(Installer.read(f) == original, "\(original ?? "nil")")
        }
        try "hooks: {on_session_start: []}\n".write(to: f, atomically: true, encoding: .utf8)
        #expect(throws: IntegrationError.self) { try i.plan(install: true, home: h, yaak: yaak) }
    }

    @Test func hermesAllowlist() throws {
        let h = try home([".hermes"])
        let i = HermesIntegration()
        try Installer.apply(try i.plan(install: true, home: h, yaak: yaak))
        #expect(i.pendingSteps(home: h).contains { $0.contains("共 6 条") })
        let text = try String(contentsOf: h.appendingPathComponent(".hermes/config.yaml"), encoding: .utf8)
        // Hermes keys consent on the exact (event, command) it parsed from YAML.
        let approvals = HermesIntegration.ours(text).dropLast().map { ["event": $0.event, "command": $0.command] }
        #expect(approvals.allSatisfy { $0["command"] == HookCommand.make(yaak: yaak, agent: .hermes, event: $0["event"]!) })
        let data = try JSONSerialization.data(withJSONObject: ["approvals": approvals])
        try data.write(to: h.appendingPathComponent(".hermes/shell-hooks-allowlist.json"))
        #expect(i.pendingSteps(home: h).contains { $0.contains("共 1 条") })
        try (text + "hooks_auto_accept: true\n").write(to: h.appendingPathComponent(".hermes/config.yaml"), atomically: true, encoding: .utf8)
        #expect(i.pendingSteps(home: h).isEmpty)
    }

    @Test func deepseekBundleAndProfiles() throws {
        let h = try home([".dsh/profiles/web"])
        let i = DeepSeekIntegration()
        #expect(i.status(home: h) == .notInstalled)
        try Installer.apply(try i.plan(install: true, home: h, yaak: yaak))
        let dir = h.appendingPathComponent(".dsh/yaakanban")
        let pkg = try json(dir.appendingPathComponent("bundle/package.json"))
        #expect((pkg["dsh"] as? [String: Any]) != nil)
        #expect(((pkg["dependencies"] as! [String: Any])["@deepseek-ai/dsh-hooks-claude-code"] as? String) == DeepSeekIntegration.fallbackVersion)
        let patch = try String(contentsOf: dir.appendingPathComponent("bundle/cordis.patch.yml"), encoding: .utf8)
        #expect(patch.contains("configPath: \"\(dir.path)/hooks.json\""))
        let hooks = try json(dir.appendingPathComponent("hooks.json"))["hooks"] as! [String: Any]
        #expect(Set(hooks.keys) == Set(DeepSeekIntegration.events))
        #expect(i.status(home: h, yaak: yaak) == .needsAuthorization)
        #expect(i.pendingSteps(home: h)[0].contains("file:\(dir.path)/bundle"))

        let profile = h.appendingPathComponent(".dsh/profiles/web/package.json")
        try #"{"dependencies":{"yaakanban-dsh":"file:/x"}}"#.write(to: profile, atomically: true, encoding: .utf8)
        #expect(i.status(home: h, yaak: yaak) == .installed)
        // The profile still depends on the bundle: uninstall says how to detach it first.
        #expect(throws: IntegrationError.self) { try i.plan(install: false, home: h, yaak: yaak) }
        try #"{"dependencies":{}}"#.write(to: profile, atomically: true, encoding: .utf8)

        try Installer.apply(try i.plan(install: false, home: h, yaak: yaak))
        for f in ["hooks.json", "bundle/package.json", "bundle/cordis.patch.yml"] {
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(f).path))
        }
        #expect(i.status(home: h) == .notInstalled)
    }

    @Test func stableLink() throws {
        let h = try home([])
        let a = try StableYaak.ensure(home: h, target: "/A.app/Contents/Helpers/yaak")
        #expect(a == StableYaak.link(home: h).path)
        #expect(HookCommand.isOurs(HookCommand.make(yaak: a, agent: .codex, event: "Stop")))
        try StableYaak.ensure(home: h, target: "/B.app/Contents/Helpers/yaak")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: a) == "/B.app/Contents/Helpers/yaak")
        // Only an installed app takes over a working link; a build folder or disk image does not.
        let apps = h.appendingPathComponent("Applications/YaaKanban.app")
        let live = h.appendingPathComponent("live-yaak")
        try "x".write(to: live, atomically: true, encoding: .utf8)
        try StableYaak.ensure(home: h, target: live.path)
        #expect(StableYaak.mayClaim(bundle: apps, home: h))
        #expect(!StableYaak.mayClaim(bundle: URL(fileURLWithPath: "/Volumes/YaaKanban/YaaKanban.app"), home: h))
        #expect(!StableYaak.mayClaim(bundle: h.appendingPathComponent("GitHub/YaaKanban/build/YaaKanban.app"), home: h))
        try FileManager.default.removeItem(at: live)
        #expect(StableYaak.mayClaim(bundle: URL(fileURLWithPath: "/Volumes/YaaKanban/YaaKanban.app"), home: h))
        // Concurrent writers never leave the link missing or throw.
        DispatchQueue.concurrentPerform(iterations: 32) { n in _ = try? StableYaak.ensure(home: h, target: "/C\(n % 2)") }
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: a))?.hasPrefix("/C") == true)
        try FileManager.default.removeItem(atPath: a)
        try "x".write(toFile: a, atomically: true, encoding: .utf8)
        #expect(throws: IntegrationError.self) { try StableYaak.ensure(home: h, target: "/B") }
    }

    @Test func dryRunRedactsSecrets() {
        let text = """
        {
          "env" : {
            "ANTHROPIC_AUTH_TOKEN" : "sk-ant-123",
            "OPENAI_API_KEY": "s1",
            "PATH" : "/bin",
            "max_tokens" : 4096
          },
          "headers": {"Authorization": "Bearer abcdefgh123", "x-api-key": "s2"},
          "args": ["--token", "s3", "--api-key=s4", "--verbose"],
          "command": "run --password s5",
          "hooks" : {}
        }
        api_key: s6#tail
        key: s7  # comment
        env: {OPENAI_API_KEY: s8, MODE: fast}
        private_key: |
          s9
          s10
        author: Artrix
        tokenizer: bpe
        export GITHUB_TOKEN=s11
        password = "s12"
        note: uses ghp_abcdefghijklmnopqrstu
        """
        let out = Installer.describe([FileChange(path: URL(fileURLWithPath: "/x"), before: nil, after: text)])
        for n in 1...12 { #expect(!out.contains("s\(n)\"") && !out.contains("s\(n) ") && !out.contains("s\(n),") && !out.contains("s\(n)\n"), "s\(n)") }
        #expect(!out.contains("sk-ant-123") && !out.contains("abcdefgh123") && !out.contains("ghp_abc"))
        for kept in ["\"/bin\"", "4096", "Artrix", "tokenizer: bpe", "MODE: fast", "\"--verbose\"", "\"hooks\" : {}"] {
            #expect(out.contains(kept), "\(kept)")
        }
    }

    @Test func hermesEdgeLayouts() throws {
        let i = HermesIntegration()
        func roundTrip(_ original: String, file: String = #fileID, line: Int = #line) throws -> String {
            let h = try home([".hermes"])
            let f = h.appendingPathComponent(".hermes/config.yaml")
            try original.write(to: f, atomically: true, encoding: .utf8)
            try Installer.apply(try i.plan(install: true, home: h, yaak: yaak))
            let installed = try String(contentsOf: f, encoding: .utf8)
            #expect(HermesIntegration.ours(installed).count == HermesIntegration.events.count)
            #expect(try i.plan(install: true, home: h, yaak: yaak).isEmpty)
            try Installer.apply(try i.plan(install: false, home: h, yaak: yaak))
            #expect(try String(contentsOf: f, encoding: .utf8) == original)
            return installed
        }
        // A quoted event key takes our item; no duplicate key.
        let quoted = try roundTrip("hooks:\n  \"on_session_end\":\n    - command: /usr/bin/true\n")
        #expect(quoted.components(separatedBy: "on_session_end\":").count == 2)
        #expect(!quoted.contains("  on_session_end:"))
        // CRLF stays CRLF.
        let crlf = try roundTrip("model: x\r\nhooks:\r\n  on_session_start:\r\n    - command: /usr/bin/true\r\n")
        #expect(!crlf.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        // A yaak item elsewhere in the file is not ours to remove.
        _ = try roundTrip("mcp_servers:\n  x:\n    args:\n      - command: /opt/yaak hook hermes x\nhooks: {}\n")

        // An old block-style item of ours goes with its continuation lines.
        let h = try home([".hermes"])
        let f = h.appendingPathComponent(".hermes/config.yaml")
        try "hooks:\n  on_session_end:\n    - command: /opt/yaak hook hermes on_session_end\n      timeout: 9\n    - command: /usr/bin/true\n"
            .write(to: f, atomically: true, encoding: .utf8)
        try Installer.apply(try i.plan(install: false, home: h, yaak: yaak))
        #expect(try String(contentsOf: f, encoding: .utf8) == "hooks:\n  on_session_end:\n    - command: /usr/bin/true\n")

        // A list under hooks: is not something we can merge into.
        try "hooks:\n  - foo\n".write(to: f, atomically: true, encoding: .utf8)
        #expect(throws: IntegrationError.self) { try i.plan(install: true, home: h, yaak: yaak) }

        // Auto-accept only at the top level, only for a true value.
        #expect(HermesIntegration.autoAccepts("hooks_auto_accept: true  # yes\n"))
        #expect(!HermesIntegration.autoAccepts("display:\n  hooks_auto_accept: true\n"))
        #expect(!HermesIntegration.autoAccepts("hooks_auto_accept: trueish\n"))
    }

}
