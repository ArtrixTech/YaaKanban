import Foundation

/// The panes the user has in front in the frontmost terminal, read from the terminal itself
/// (`FocusWatcher` in the app). A session whose pane is among them counts as looked at.
public struct TerminalFocus: Equatable, Sendable {
    /// Wave: the focused block of each window's active tab.
    public var waveBlocks: Set<String> = []
    /// iTerm2: the current session's UUID.
    public var itermSession: String?
    /// Terminal.app (and iTerm2): the tty of the selected tab.
    public var tty: String?
    /// WezTerm: the focused pane of the most recently active client.
    public var weztermPane: String?
    /// tmux clients attached to the servers asked about.
    public var tmuxClients: [TmuxClient] = []

    public init(waveBlocks: Set<String> = [], itermSession: String? = nil, tty: String? = nil,
                weztermPane: String? = nil, tmuxClients: [TmuxClient] = []) {
        self.waveBlocks = waveBlocks
        self.itermSession = itermSession
        self.tty = tty
        self.weztermPane = weztermPane
        self.tmuxClients = tmuxClients
    }

    public struct TmuxClient: Equatable, Sendable {
        public var socket: String
        /// The client's current pane (`%3`).
        public var pane: String
        /// tmux's own `focused` flag; only meaningful with `focus-events on`.
        public var focused: Bool
        /// Where the client itself runs (its tty and environment), when it could be read.
        public var outer: TerminalContext?

        public init(socket: String, pane: String, focused: Bool, outer: TerminalContext? = nil) {
            self.socket = socket
            self.pane = pane
            self.focused = focused
            self.outer = outer
        }
    }

    /// Whether the pane `t` describes is in front. Inside tmux, the outer terminal's ids in the
    /// environment may be stale (tmux keeps its server's), so only tmux's own state counts: a
    /// client showing the pane whose outer terminal is in front, or, when that is unknown, one
    /// tmux says is focused.
    public func shows(_ t: TerminalContext) -> Bool {
        if let pane = t.tmuxPane, let socket = t.tmuxSocket {
            return tmuxClients.contains { c in
                c.socket == socket && c.pane == pane && (c.outer.map { outerShows($0) } ?? c.focused)
            }
        }
        return outerShows(t)
    }

    private func outerShows(_ t: TerminalContext) -> Bool {
        if let b = t.waveBlockId { return waveBlocks.contains(b) }
        if let id = t.itermSession, let cur = itermSession { return id == cur }
        if let p = t.weztermPane, let cur = weztermPane { return p == cur }
        if let tty = t.tty, let cur = self.tty { return tty == cur }
        return false
    }
}

// MARK: Parsing what the terminals answer

extension TerminalFocus {
    /// Wave's layout state of a tab (`db_layout.data`): the focused node's block, or the only block.
    public static func waveFocusedBlock(layout: JSONValue) -> String? {
        let leaves = layout["leaforder"]?.array ?? []
        if let node = layout["focusednodeid"]?.string,
           let leaf = leaves.first(where: { $0["nodeid"]?.string == node }) {
            return leaf["blockid"]?.string
        }
        return leaves.count == 1 ? leaves[0]["blockid"]?.string : nil
    }

    /// `wezterm cli list-clients --format json`: the focused pane of the client used last.
    public static func weztermFocusedPane(listClients: JSONValue) -> String? {
        let clients = (listClients.array ?? []).filter { $0["focused_pane_id"]?.string != nil }
        func idle(_ c: JSONValue) -> Double {
            let d = c["idle_time"]
            return (d?["secs"]?.number ?? .infinity) + (d?["nanos"]?.number ?? 0) / 1e9
        }
        return clients.min { idle($0) < idle($1) }?["focused_pane_id"]?.string
    }

    /// Lines of `tmux list-clients -F '#{client_tty}\t#{client_pid}\t#{client_flags}\t#{pane_id}'`.
    public static func tmuxClients(listClients out: String) -> [(tty: String, pid: Int32, focused: Bool, pane: String)] {
        out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4, let pid = Int32(f[1]), !f[3].isEmpty else { return nil }
            return (f[0], pid, f[2].split(separator: ",").contains("focused"), f[3])
        }
    }
}
