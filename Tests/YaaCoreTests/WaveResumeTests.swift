import Foundation
import Testing
@testable import YaaCore

@Suite struct WaveResumeTests {
    /// The meta values `wsh createblock` would set, decoded the way `wsh` decodes them.
    private func meta(_ args: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for a in args.dropFirst(2) {
            let kv = a.split(separator: "=", maxSplits: 1).map(String.init)
            out[kv[0]] = kv[1].hasPrefix("\"") ? (try? JSONDecoder().decode(String.self, from: Data(kv[1].utf8))) : kv[1]
        }
        return out
    }

    private func check(_ shell: String, _ script: String) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-n", "-c", script]
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    @Test func shellBlockWithOneShotScripts() throws {
        let cmd = "claude --resume 'it'\\''s \"x\" $HOME'"
        let args = WaveResume.createBlockArgs(cmd, cwd: "/tmp/a b/\"c\"")
        #expect(Array(args.prefix(3)) == ["createblock", "term", "controller=shell"])
        let m = meta(args)
        #expect(m["cmd:cwd"] == "/tmp/a b/\"c\"")
        for key in WaveResume.keys {
            let script = try #require(m[key])
            // The command is quoted once and cleared from the block before it runs.
            #expect(script.contains(shellQuote(cmd)))
            #expect(script.contains("wsh setmeta -b \"$WAVETERM_BLOCKID\" cmd:initscript.zsh=null cmd:initscript.bash=null cmd:initscript.fish=null"))
        }
        #expect(try check("/bin/zsh", m["cmd:initscript.zsh"]!) == 0)
        #expect(try check("/bin/bash", m["cmd:initscript.bash"]!) == 0)
    }

    /// The bash hook runs the command once at the first prompt, then leaves precmd alone.
    @Test func bashHookRunsOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-wave-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("wsh")
        try "#!/bin/sh\necho \"$@\" >> \"\(dir.path)/wsh.log\"\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let script = meta(WaveResume.createBlockArgs("echo ran-$((1+1))", cwd: nil))["cmd:initscript.bash"]!
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Two prompts, as bash-preexec would run them.
        p.arguments = ["-c", script + "\nfor f in \"${precmd_functions[@]}\"; do $f; done\nfor f in \"${precmd_functions[@]}\"; do $f; done\nwait"]
        p.environment = ["PATH": "\(dir.path):/usr/bin:/bin", "WAVETERM_BLOCKID": "b1"]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        p.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(text == "echo ran-$((1+1))\nran-2\n")
        let log = try String(contentsOf: dir.appendingPathComponent("wsh.log"), encoding: .utf8)
        #expect(log == "setmeta -b b1 cmd:initscript.zsh=null cmd:initscript.bash=null cmd:initscript.fish=null\n")
    }
}
