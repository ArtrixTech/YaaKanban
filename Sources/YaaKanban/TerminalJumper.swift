import AppKit
import Foundation
import YaaCore

/// Brings the user back to where a session runs. One adapter per terminal; fallback copies context.
@MainActor
struct TerminalJumper {
    static let waveBundleId = "dev.commandline.waveterm"
    static let codexBundleId = "com.openai.codex"
    let settings: Preferences

    enum Outcome { case activated(String), copied }

    @discardableResult
    func jump(to s: SessionState) -> Outcome {
        if let t = s.terminal, t.isWave, let wave = NSRunningApplication.runningApplications(withBundleIdentifier: Self.waveBundleId).first {
            WaveAdapter(terminal: t, switchTabs: settings.waveTabSwitching).jump(app: wave)
            return .activated("Wave")
        }
        // The app the agent runs under: Cursor's own agent has no terminal at all, and an editor's
        // built-in terminal says TERM_PROGRAM=vscode whether it is VS Code or Cursor.
        if let app = s.agentPid.flatMap(Self.hostApp(of:)) ?? s.terminal?.termProgram.flatMap(Self.app(forTermProgram:)) {
            if app.bundleIdentifier == Self.codexBundleId, let url = Self.codexThreadURL(s.sessionId) {
                // The Codex app opens a thread from its own URL scheme (`codex://threads/<id>`).
                if let bundle = app.bundleURL {
                    NSWorkspace.shared.open([url], withApplicationAt: bundle, configuration: NSWorkspace.OpenConfiguration())
                } else {
                    NSWorkspace.shared.open(url)
                }
                return .activated(app.localizedName ?? "Codex")
            }
            if Self.isEditor(app) {
                // Raise the window that has the project (opening the folder would make a new editor
                // window when the session lives in Cursor's separate Agents window).
                app.activate()
                EditorWindows.raise(pid: app.processIdentifier, project: s.projectName, agentsFirst: s.agent == .cursor)
            } else {
                app.activate()
                copyContext(s)
            }
            return .activated(app.localizedName ?? "")
        }
        copyContext(s)
        return .copied
    }

    /// Codex thread ids are UUIDs; anything else is not put into a URL.
    static func codexThreadURL(_ id: String) -> URL? {
        guard !id.isEmpty, id.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
        return URL(string: "codex://threads/\(id)")
    }

    /// First ancestor of the agent that is a regular app (a terminal or an editor).
    static func hostApp(of pid: Int32) -> NSRunningApplication? {
        var cur = pid
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: cur), app.activationPolicy == .regular,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                return app
            }
            guard let up = ProcessUtil.parent(of: cur), up > 1 else { return nil }
            cur = up
        }
        return nil
    }

    static let editors: Set<String> = ["com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
                                       "com.exafunction.windsurf", "dev.zed.Zed"]
    static func isEditor(_ app: NSRunningApplication) -> Bool { app.bundleIdentifier.map(editors.contains) ?? false }

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
            "ghostty": "com.mitchellh.ghostty", "WezTerm": "com.github.wez.wezterm", "vscode": "com.microsoft.VSCode", "cursor": "com.todesktop.230313mzl4w4u92",
            "waveterm": waveBundleId,
        ]
        guard let id = ids[p] else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
    }
}

/// Editor windows through Accessibility: the one titled with the project, or Cursor's Agents window
/// (first for Cursor's own agent, which usually lives there). Without Accessibility the app is
/// only activated.
enum EditorWindows {
    static func raise(pid: pid_t, project: String?, agentsFirst: Bool) {
        guard AXIsProcessTrusted() else { return }
        let app = AXUIElementCreateApplication(pid)
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
              let windows = v as? [AXUIElement] else { return }
        func title(_ w: AXUIElement) -> String {
            var t: AnyObject?
            return AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success ? (t as? String ?? "") : ""
        }
        // Editor titles read "file — project — Cursor"; match the project as a whole segment.
        let byProject = project.flatMap { p in windows.first { title($0).components(separatedBy: " — ").contains(p) } }
        let agents = windows.first { title($0).hasSuffix("Agents") }
        guard let w = agentsFirst ? agents ?? byProject : byProject ?? agents else { return }
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}

/// Wave Terminal: `wsh` with the JWT captured by the hook for badges and block focus. Wave has no
/// external tab switching yet (wavetermdev/waveterm#3333), so the tab is pressed through the
/// Accessibility API: Wave's tab bar is a web view whose tabs answer AXPress.
struct WaveAdapter {
    let terminal: TerminalContext
    let switchTabs: Bool

    static var wsh: String {
        Paths.home().appendingPathComponent("Library/Application Support/waveterm/bin/wsh").path
    }

    func jump(app: NSRunningApplication) {
        app.activate()
        badge(on: true)
        guard switchTabs, let tab = terminal.waveTabId else { return }
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return }
        let pid = app.processIdentifier
        let block = terminal.waveBlockId
        DispatchQueue.global(qos: .userInitiated).async {
            // Re-read Wave's state on every attempt: a tab just created or renamed, or a block
            // moved to another tab, may reach the DB or the tab bar a moment later.
            let found = WaveTabBar(pid: pid).press { WaveDB.place(ofBlock: block, tab: tab) }
            if found {
                usleep(150_000)
                if let block { run(["focusblock", "-b", block]) }
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
}

/// Read-only view of Wave's object database.
enum WaveDB {
    static var path: String {
        Paths.home().appendingPathComponent("Library/Application Support/waveterm/db/waveterm.db").path
    }

    /// Where the block is now (the tab holding it; else the tab it started in): that tab's position
    /// in its workspace and the names of all tabs there, in order.
    static func place(ofBlock block: String?, tab: String) -> (index: Int, names: [String])? {
        var names: [String: String] = [:]
        var holder: String?
        for row in query("SELECT data FROM db_tab") {
            guard let id = row["oid"]?.string else { continue }
            names[id] = row["name"]?.string ?? ""
            if let block, row["blockids"]?.array?.contains(where: { $0.string == block }) == true { holder = id }
        }
        let target = holder ?? tab
        for ws in query("SELECT data FROM db_workspace") {
            guard let ids = ws["tabids"]?.array?.compactMap(\.string), let i = ids.firstIndex(of: target) else { continue }
            return (i, ids.map { names[$0] ?? "" })
        }
        return nil
    }

    private static func query(_ sql: String) -> [JSONValue] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = ["-readonly", "file:\(path)?mode=ro", sql]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { JSONValue.parse(Data($0.utf8)) }
    }
}

/// Wave's tab bar seen through Accessibility. Electron exposes its DOM only after
/// `AXManualAccessibility` is set, which takes a moment the first time.
struct WaveTabBar {
    let pid: pid_t

    /// Finds the window whose tab names match the workspace and presses the tab at the index.
    /// `place` is asked again on each attempt. A looser match (same count, same name at the index)
    /// is only used once exact matching has had all its tries.
    func press(_ place: () -> (index: Int, names: [String])?) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let attempts = 8
        for attempt in 0..<attempts {
            if attempt > 0 { usleep(250_000) }
            guard let (index, names) = place() else { continue }
            let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
            let bars = windows.compactMap { w in tabs(in: w).map { (w, $0) } }.filter { !$0.1.isEmpty }
            var match = bars.first { $0.1.map(label) == names }
            if match == nil, attempt == attempts - 1 {
                match = bars.first { $0.1.count == names.count && $0.1.indices.contains(index) && label($0.1[index]) == names[index] }
            }
            guard let (window, tabs) = match, tabs.indices.contains(index) else { continue }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return AXUIElementPerformAction(tabs[index], kAXPressAction as CFString) == .success
        }
        return false
    }

    private func tabs(in e: AXUIElement, depth: Int = 0) -> [AXUIElement]? {
        if depth > 16 { return nil }
        if classes(e).contains("tabs-wrapper") { return children(e) }
        for c in children(e) { if let t = tabs(in: c, depth: depth + 1) { return t } }
        return nil
    }

    /// Visible tab name, without the icon-font glyphs (private use area) Wave appends.
    private func label(_ e: AXUIElement) -> String {
        let scalars = text(e).unicodeScalars.filter { !(0xE000...0xF8FF).contains($0.value) }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func text(_ e: AXUIElement) -> String {
        ((attr(e, kAXValueAttribute) as? String) ?? "") + children(e).map(text).joined()
    }

    private func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
    private func classes(_ e: AXUIElement) -> [String] { (attr(e, "AXDOMClassList") as? [String]) ?? [] }

    private func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
}
