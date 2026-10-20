import AppKit
import Foundation
import YaaCore

/// Brings the user back to where a session runs. One adapter per terminal; fallback copies context.
@MainActor
struct TerminalJumper {
    static let waveBundleId = "dev.commandline.waveterm"
    let settings: Preferences

    enum Outcome { case activated(String), copied }

    @discardableResult
    func jump(to s: SessionState) -> Outcome {
        if let t = s.terminal, t.isWave, let wave = NSRunningApplication.runningApplications(withBundleIdentifier: Self.waveBundleId).first {
            WaveAdapter(terminal: t, switchTabs: settings.waveTabSwitching).jump(app: wave)
            return .activated("Wave")
        }
        if let name = s.terminal?.termProgram, let app = Self.app(forTermProgram: name) {
            app.activate()
            copyContext(s)
            return .activated(app.localizedName ?? name)
        }
        copyContext(s)
        return .copied
    }

    /// Marks the session's Wave block so it is easy to spot (used when it needs attention).
    func badge(_ s: SessionState, on: Bool) {
        guard let t = s.terminal, t.isWave else { return }
        WaveAdapter(terminal: t, switchTabs: false).badge(on: on)
    }

    func copyContext(_ s: SessionState) {
        let text = [s.cwd.map { "cd \(shellQuote($0))" }, "# \(s.agent.displayName) session \(s.sessionId)"]
            .compactMap { $0 }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func app(forTermProgram p: String) -> NSRunningApplication? {
        let ids: [String: String] = [
            "iTerm.app": "com.googlecode.iterm2", "Apple_Terminal": "com.apple.Terminal",
            "ghostty": "com.mitchellh.ghostty", "WezTerm": "com.github.wez.wezterm", "vscode": "com.microsoft.VSCode",
            "waveterm": waveBundleId,
        ]
        guard let id = ids[p] else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
    }
}

/// Wave Terminal: `wsh` with the JWT captured by the hook. Wave has no external tab switching yet
/// (wavetermdev/waveterm#2738, PR #3333), so tab switching is an opt-in Cmd+N keystroke hack.
struct WaveAdapter {
    let terminal: TerminalContext
    let switchTabs: Bool

    static var wsh: String {
        Paths.home().appendingPathComponent("Library/Application Support/waveterm/bin/wsh").path
    }

    func jump(app: NSRunningApplication) {
        app.activate()
        badge(on: true)
        guard switchTabs, let tab = terminal.waveTabId, let index = tabIndex(tab), index < 9 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            sendCommandDigit(index + 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if let block = terminal.waveBlockId { run(["focusblock", "-b", block]) }
            }
        }
    }

    func badge(on: Bool) {
        guard let block = terminal.waveBlockId else { return }
        run(on ? ["badge", "bell", "--color", "#f59e0b", "-b", block] : ["badge", "--clear", "-b", block])
    }

    private func run(_ args: [String]) {
        guard let jwt = terminal.waveJWT, FileManager.default.isExecutableFile(atPath: Self.wsh) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.wsh)
        p.arguments = args
        var env = ["HOME": Paths.home().path, "WAVETERM_JWT": jwt]
        if let t = terminal.waveTabId { env["WAVETERM_TABID"] = t }
        if let b = terminal.waveBlockId { env["WAVETERM_BLOCKID"] = b }
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Position of the tab within its workspace, read from Wave's database (read-only).
    private func tabIndex(_ tab: String) -> Int? {
        let db = Paths.home().appendingPathComponent("Library/Application Support/waveterm/db/waveterm.db").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = ["-readonly", "file:\(db)?mode=ro", "SELECT data FROM db_workspace"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let ids = JSONValue.parse(Data(line.utf8))?["tabids"]?.array?.compactMap(\.string) else { continue }
            if let i = ids.firstIndex(of: tab) { return i }
        }
        return nil
    }

    /// Requires Accessibility permission; silently does nothing without it.
    private func sendCommandDigit(_ n: Int) {
        let keyCodes: [Int: CGKeyCode] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25]
        guard let code = keyCodes[n] else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }
}
