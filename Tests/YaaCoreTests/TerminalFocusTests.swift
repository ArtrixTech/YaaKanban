import Foundation
import Testing
@testable import YaaCore

@Suite struct TerminalFocusTests {
    @Test func readsPaneIdsFromTheHookEnvironment() {
        let t = TerminalContext(environment: [
            "TERM_PROGRAM": "tmux", "ITERM_SESSION_ID": "w0t1p0:ABC-123", "WEZTERM_PANE": "4",
            "TMUX": "/private/tmp/tmux-501/default,812,0", "TMUX_PANE": "%3",
        ], tty: "/dev/ttys004")
        #expect(t.tmuxSocket == "/private/tmp/tmux-501/default" && t.tmuxPane == "%3" && t.tty == "/dev/ttys004")
        // Ids of the terminal tmux was started from are not this pane's.
        #expect(t.itermSession == nil && t.weztermPane == nil)
        let iterm = TerminalContext(environment: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t1p0:ABC-123"])
        #expect(iterm.itermSession == "ABC-123")
        #expect(TerminalContext(environment: ["TERM_PROGRAM": "WezTerm", "WEZTERM_PANE": "4"]).weztermPane == "4")
        // Inherited by an app started from a shell there (`cursor .` from iTerm2, a GUI app from tmux).
        let inherited = TerminalContext(environment: ["TERM_PROGRAM": "vscode", "ITERM_SESSION_ID": "w0t1p0:ABC",
                                                      "WEZTERM_PANE": "4", "TMUX": "/tmp/s,1,0", "TMUX_PANE": "%3"])
        #expect(inherited.itermSession == nil && inherited.weztermPane == nil && inherited.tmuxPane == nil)
    }

    @Test func matchesThePaneOfEachTerminal() {
        let wave = TerminalContext(waveBlockId: "b1")
        #expect(TerminalFocus(waveBlocks: ["b1", "b9"]).shows(wave))
        #expect(!TerminalFocus(waveBlocks: ["b2"]).shows(wave))

        let iterm = TerminalContext(termProgram: "iTerm.app", itermSession: "S1", tty: "/dev/ttys001")
        #expect(TerminalFocus(itermSession: "S1", tty: "/dev/ttys001").shows(iterm))
        #expect(!TerminalFocus(itermSession: "S2", tty: "/dev/ttys002").shows(iterm))

        let terminal = TerminalContext(termProgram: "Apple_Terminal", tty: "/dev/ttys005")
        #expect(TerminalFocus(tty: "/dev/ttys005").shows(terminal))
        #expect(!TerminalFocus(tty: "/dev/ttys006").shows(terminal))
        #expect(!TerminalFocus().shows(terminal))

        let wez = TerminalContext(termProgram: "WezTerm", weztermPane: "7")
        #expect(TerminalFocus(weztermPane: "7").shows(wez))
        #expect(!TerminalFocus(weztermPane: "8").shows(wez))
    }

    @Test func tmuxCountsOnlyAClientShowingThePaneInFront() {
        // Inside tmux, the stale Wave block from the server's environment must not count.
        let t = TerminalContext(waveBlockId: "stale", tmuxPane: "%3", tmuxSocket: "/tmp/s")
        let inWave = TerminalContext(waveBlockId: "b1")
        func client(_ pane: String, focused: Bool = false, outer: TerminalContext? = inWave) -> TerminalFocus.TmuxClient {
            .init(socket: "/tmp/s", pane: pane, focused: focused, outer: outer)
        }
        #expect(TerminalFocus(waveBlocks: ["b1"], tmuxClients: [client("%3")]).shows(t))
        #expect(!TerminalFocus(waveBlocks: ["stale"], tmuxClients: [client("%3")]).shows(t))
        #expect(!TerminalFocus(waveBlocks: ["b1"], tmuxClients: [client("%4")]).shows(t))
        // Outer terminal unknown: tmux's focused flag decides.
        #expect(TerminalFocus(tmuxClients: [client("%3", focused: true, outer: nil)]).shows(t))
        #expect(!TerminalFocus(tmuxClients: [client("%3", focused: false, outer: nil)]).shows(t))
        // Another server's pane with the same id.
        let other = TerminalFocus.TmuxClient(socket: "/tmp/other", pane: "%3", focused: true)
        #expect(!TerminalFocus(tmuxClients: [other]).shows(t))
    }

    @Test func parsesWhatTheTerminalsAnswer() throws {
        let layout = try #require(JSONValue.parse(Data(#"""
            {"focusednodeid":"n2","leaforder":[{"nodeid":"n1","blockid":"b1"},{"nodeid":"n2","blockid":"b2"}]}
            """#.utf8)))
        #expect(TerminalFocus.waveFocusedBlock(layout: layout) == "b2")
        let single = try #require(JSONValue.parse(Data(#"{"leaforder":[{"nodeid":"n1","blockid":"b1"}]}"#.utf8)))
        #expect(TerminalFocus.waveFocusedBlock(layout: single) == "b1")

        let clients = try #require(JSONValue.parse(Data(#"""
            [{"focused_pane_id":1,"idle_time":{"secs":40,"nanos":0}},{"focused_pane_id":5,"idle_time":{"secs":2,"nanos":5}}]
            """#.utf8)))
        #expect(TerminalFocus.weztermFocusedPane(listClients: clients) == "5")
        let unfocused = try #require(JSONValue.parse(Data(#"""
            [{"focused_pane_id":null,"idle_time":{"secs":0,"nanos":0}},{"focused_pane_id":3,"idle_time":{"secs":9,"nanos":0}}]
            """#.utf8)))
        #expect(TerminalFocus.weztermFocusedPane(listClients: unfocused) == "3")

        let tmux = TerminalFocus.tmuxClients(listClients: "/dev/ttys001\t901\tattached,focused,UTF-8\t%3\n/dev/ttys002\t902\tattached,UTF-8\t%0\n")
        #expect(tmux.count == 2)
        #expect(tmux[0].tty == "/dev/ttys001" && tmux[0].pid == 901 && tmux[0].focused && tmux[0].pane == "%3")
        #expect(!tmux[1].focused && tmux[1].pane == "%0")
    }
}
