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
