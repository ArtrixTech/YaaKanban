import AppKit
import Darwin
import Foundation
import SwiftUI
import YaaCore

/// Reads which pane the user has in front in the frontmost terminal (`TerminalFocus`), so a
/// finished turn counts as reviewed once its pane is shown. Experimental; terminals: Wave (its
/// database), iTerm2 and Terminal (AppleScript, only once Automation is allowed: never a prompt
/// out of the blue), WezTerm (its CLI) and tmux inside any of them.
enum FocusWatcher {
    static let itermBundleId = "com.googlecode.iterm2"
    static let terminalBundleId = "com.apple.Terminal"
    static let weztermBundleId = "com.github.wez.wezterm"
    /// Frontmost apps worth asking about. tmux counts only inside these: elsewhere the terminal
    /// around it cannot say whether its window is the one in front.
    static let terminals: Set<String> = [TerminalJumper.waveBundleId, itermBundleId, terminalBundleId, weztermBundleId]

    /// Off the main thread; `done` runs on the main queue. `wanted` are the sessions' terminals.
    static func probe(front: NSRunningApplication, wanted: [TerminalContext], done: @escaping @MainActor (TerminalFocus) -> Void) {
        let bundle = front.bundleIdentifier ?? ""
        let app = front.bundleURL
        let sockets = Set(wanted.compactMap(\.tmuxSocket))
        let wants = (wave: wanted.contains { $0.isWave }, iterm: wanted.contains { $0.itermSession != nil || $0.tmuxSocket != nil },
                     tty: wanted.contains { $0.tty != nil }, wezterm: wanted.contains { $0.weztermPane != nil || $0.tmuxSocket != nil })
        DispatchQueue.global(qos: .utility).async {
            var f = TerminalFocus()
            switch bundle {
            case TerminalJumper.waveBundleId where wants.wave || !sockets.isEmpty:
                f.waveBlocks = waveBlocks()
            case itermBundleId where wants.iterm || wants.tty:
                if let (id, tty) = iterm() { f.itermSession = id; f.tty = tty }
            case terminalBundleId where wants.tty || !sockets.isEmpty:
                f.tty = terminalTTY()
            case weztermBundleId where wants.wezterm:
                f.weztermPane = app.flatMap(weztermPane)
            default: break
            }
            f.tmuxClients = sockets.flatMap(tmuxClients)
            DispatchQueue.main.async { MainActor.assumeIsolated { done(f) } }
        }
    }

    // MARK: Wave

    /// The focused block of the active tab, with one Wave window open. With several, which one is
    /// in front is not in the database, so none counts.
    static func waveBlocks() -> Set<String> {
        guard WaveDB.query("SELECT json_object('n', count(*)) FROM db_window").first?["n"]?.number == 1 else { return [] }
        let sql = "SELECT l.data FROM db_window w"
            + " JOIN db_workspace ws ON ws.oid = json_extract(w.data, '$.workspaceid')"
            + " JOIN db_tab t ON t.oid = json_extract(ws.data, '$.activetabid')"
            + " JOIN db_layout l ON l.oid = json_extract(t.data, '$.layoutstate')"
        return Set(WaveDB.query(sql).compactMap(TerminalFocus.waveFocusedBlock(layout:)))
    }

    // MARK: AppleScript (iTerm2, Terminal)

    /// Whether AppleScript may drive the app; asks only when `prompt` (the user pressed Allow).
    static func automationAllowed(_ bundleId: String, prompt: Bool = false) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        guard let desc = target.aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, prompt) == noErr
    }

    static func iterm() -> (String, String)? {
        guard automationAllowed(itermBundleId) else { return nil }
        let out = osascript("tell application id \"\(itermBundleId)\" to tell current session of current tab of current window to return (unique id) & \"\\t\" & (tty)")
        let f = out.split(separator: "\t").map(String.init)
        return f.count == 2 ? (f[0], f[1]) : nil
    }

    static func terminalTTY() -> String? {
        guard automationAllowed(terminalBundleId) else { return nil }
        let out = osascript("tell application id \"\(terminalBundleId)\" to return tty of selected tab of front window")
        return out.isEmpty ? nil : out
    }

    // MARK: WezTerm

    static func weztermPane(app: URL) -> String? {
        let cli = app.appendingPathComponent("Contents/MacOS/wezterm").path
        guard let json = JSONValue.parse(Data(run(cli, ["cli", "list-clients", "--format", "json"]).utf8)) else { return nil }
        return TerminalFocus.weztermFocusedPane(listClients: json)
    }

    // MARK: tmux

    static let tmuxPaths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/opt/local/bin/tmux", "/usr/bin/tmux"]

    /// The clients of the server at `socket`, each with where it runs: its tty, and the terminal
    /// ids in its own environment (read from the client process).
    static func tmuxClients(socket: String) -> [TerminalFocus.TmuxClient] {
        guard let tmux = tmuxPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else { return [] }
        let out = run(tmux, ["-S", socket, "list-clients", "-F", "#{client_tty}\t#{client_pid}\t#{client_flags}\t#{pane_id}"])
        return TerminalFocus.tmuxClients(listClients: out).map { c in
            let outer = environment(of: c.pid).map { TerminalContext(environment: $0, tty: c.tty) }
            return TerminalFocus.TmuxClient(socket: socket, pane: c.pane, focused: c.focused, outer: outer)
        }
    }

    /// The environment of another process of this user (`KERN_PROCARGS2`): argc, the executable
    /// path, the arguments, then `KEY=value` strings.
    static func environment(of pid: Int32) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = buf.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        // NUL-separated strings after argc; empty ones are padding after the executable path.
        let strings = buf[MemoryLayout<Int32>.size..<size].split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        guard strings.count > argc else { return nil }
        var env: [String: String] = [:]
        for s in strings.dropFirst(1 + argc) {
            guard let eq = s.firstIndex(of: "="), eq != s.startIndex else { continue }
            env[String(s[..<eq])] = String(s[s.index(after: eq)...])
        }
        return env
    }

    // MARK: Processes

    private static func osascript(_ source: String) -> String { run("/usr/bin/osascript", ["-e", source]) }

    /// Runs a short command and returns its trimmed output; empty if it fails or takes over 2 s.
    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: timer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        timer.cancel()
        guard p.terminationStatus == 0 else { return "" }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Under the auto review setting: which terminals it covers, and an Allow… button for iTerm2 and
/// Terminal while they run without Automation access (asked only from that button).
struct AutomationAccessRows: View {
    @State private var missing: [(id: String, name: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Works in Wave, iTerm2, Terminal, WezTerm and tmux inside them. Opening the pane counts, like clicking its card.")
                .font(.ui(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(missing, id: \.id) { app in
                HStack(spacing: Space.m) {
                    Text("\(app.name) needs Automation access to tell which tab is in front").font(.ui(.footnote))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.m)
                    Button("Allow…") { allow(app.id) }.buttonStyle(.action(.primary, size: .small))
                }
            }
        }
        .onAppear(perform: refresh)
        .onComeBack(perform: refresh)
    }

    private func refresh() {
        let apps = [(FocusWatcher.itermBundleId, "iTerm2"), (FocusWatcher.terminalBundleId, "Terminal")]
        DispatchQueue.global(qos: .userInitiated).async {
            // Only apps that are running can be asked about.
            let out = apps.filter { a in
                !NSRunningApplication.runningApplications(withBundleIdentifier: a.0).isEmpty && !FocusWatcher.automationAllowed(a.0)
            }.map { (id: $0.0, name: $0.1) }
            DispatchQueue.main.async { missing = out }
        }
    }

    private func allow(_ id: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = FocusWatcher.automationAllowed(id, prompt: true)
            DispatchQueue.main.async(execute: refresh)
        }
    }
}
