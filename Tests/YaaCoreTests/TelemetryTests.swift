import Foundation
import Testing
@testable import YaaCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private let env = TelemetryEnvironment(app: "0.1.0", build: "1", os: "15", arch: "arm64", lang: "zh")

@Suite struct TelemetryLedgerTests {
    @Test func countsNothingUntilTurnedOn() {
        var l = TelemetryLedger()
        l.note(.jumpWave, day: "2026-10-22")
        #expect(l.days.isEmpty && l.installId == nil && !l.asked)
        l.set(enabled: true)
        l.note(.jumpWave, day: "2026-10-22")
        l.note(.spoolReplay, by: 3, day: "2026-10-22")
        #expect(l.days["2026-10-22"] == ["jump_wave": 1, "spool_replay": 3])
        #expect(l.installId != nil && l.asked)
    }

    /// Off forgets the counts but keeps the id, so turning on again is the same install.
    @Test func turningOffClearsCountsKeepsId() {
        var l = TelemetryLedger()
        l.set(enabled: true)
        let id = l.installId
        l.note(.rename, day: "2026-10-22")
        l.set(enabled: false)
        #expect(l.days.isEmpty)
        l.set(enabled: true)
        #expect(l.installId == id)
        l.resetId()
        #expect(l.installId != id && l.installId != nil)
    }

    @Test func pendingIsFinishedUnsentDaysCapped() {
        var l = TelemetryLedger()
        l.set(enabled: true)
        for d in 1...10 { l.note(day: String(format: "2026-10-%02d", d)) }
        // Today is never due; only the last seven finished days are.
        #expect(l.pending(today: "2026-10-10") == (3...9).map { String(format: "2026-10-%02d", $0) })
        l.sent(through: "2026-10-09")
        #expect(Array(l.days.keys) == ["2026-10-10"])
        #expect(l.pending(today: "2026-10-10").isEmpty)
        #expect(l.pending(today: "2026-10-12") == ["2026-10-10"])
        // A day noted again after being reported is not sent twice.
        l.note(day: "2026-10-09")
        #expect(!l.pending(today: "2026-10-12").contains("2026-10-09"))
    }

    @Test func roundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-tel-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(TelemetryLedger.load(url) == TelemetryLedger())
        TelemetryLedger.update(url) { $0.set(enabled: true) }
        TelemetryLedger.update(url) { $0.note(.pin, day: "2026-10-22") }
        let l = TelemetryLedger.load(url)
        #expect(l.enabled && l.days["2026-10-22"] == ["pin": 1])
    }
}

@Suite struct TelemetryReportTests {
    /// Only listed fields and counters leave the machine, and figures are buckets, never values.
    @Test func reportCarriesOnlyListedFields() throws {
        var s = SessionState(agent: .claudeCode, sessionId: "secret-session", at: Date(timeIntervalSince1970: 0))
        s.cwd = "/Users/someone/secret-project"
        s.customName = "secret name"
        let day = utc.dateInterval(of: .day, for: Date(timeIntervalSince1970: 86_400 * 3))!
        s.turns = (0..<7).map { Turn(id: $0, prompt: "secret prompt", startedAt: day.start.addingTimeInterval(Double($0) * 60),
                                     endedAt: nil, toolCount: 1, lastMessage: "secret reply") }
        var f = TelemetryFigures(sessions: [s], day: day)
        #expect(f.sessions == [.claudeCode: 1] && f.turns == [.claudeCode: 7])
        f.agentHours = 2.5
        f.parallelPeak = 3
        f.leverage = 1.7
        let r = Telemetry.makeReport(installId: "id", day: "1970-01-04", env: env,
                                     integrations: [.claudeCode: "installed"], settings: [.slimRail: true],
                                     counts: ["jump_wave": 2, "made_up": 5, "rename": 0], figures: f)
        #expect(r.counts == ["jump_wave": 2])
        #expect(r.figures == ["sessions.claude-code": "1", "turns.claude-code": "6-20", "agent_hours": "1-3",
                              "parallel_peak": "2-5", "leverage": "1-2"])
        let json = String(decoding: Telemetry.encode(r), as: UTF8.self)
        #expect(!json.contains("secret"))
        let keys = try #require(JSONSerialization.jsonObject(with: Telemetry.encode(r)) as? [String: Any]).keys
        #expect(Set(keys) == ["schema", "install_id", "day", "app", "build", "os", "arch", "lang",
                              "integrations", "settings", "counts", "figures"])
    }

    @Test func turnsOutsideTheDayOrInSubagentsDoNotCount() {
        let day = utc.dateInterval(of: .day, for: Date(timeIntervalSince1970: 86_400 * 3))!
        var a = SessionState(agent: .pi, sessionId: "a", at: day.start)
        a.turns = [Turn(id: 0, prompt: "", startedAt: day.end, endedAt: nil, toolCount: 0, lastMessage: nil)]
        var b = SessionState(agent: .pi, sessionId: "b", at: day.start)
        b.parentId = "pi:a"
        b.turns = [Turn(id: 0, prompt: "", startedAt: day.start, endedAt: nil, toolCount: 0, lastMessage: nil)]
        #expect(TelemetryFigures(sessions: [a, b], day: day) == TelemetryFigures())
    }

    /// The server validates this same file (`server/telemetry/test`). After changing the report,
    /// regenerate it with `YAAK_UPDATE_FIXTURES=1 make test` and update the server to accept it.
    @Test func reportMatchesServerFixture() throws {
        var f = TelemetryFigures()
        f.sessions = [.claudeCode: 3, .pi: 1]
        f.turns = [.claudeCode: 12, .pi: 1]
        f.agentHours = 4.2
        f.parallelPeak = 2
        f.leverage = 0.8
        let r = Telemetry.makeReport(installId: "e617184b-ea01-4296-a57c-3a770a5f8ef8", day: "2026-10-22", env: env,
                                     integrations: [.claudeCode: "installed", .codex: "outdated", .cursor: "notDetected",
                                                    .opencode: "notInstalled", .pi: "installed"],
                                     settings: Dictionary(uniqueKeysWithValues: TelemetrySetting.allCases.map { ($0, true) }),
                                     counts: Dictionary(uniqueKeysWithValues: TelemetryEvent.allCases.map { ($0.rawValue, 1) }),
                                     figures: f)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../server/telemetry/test/fixture-report.json").standardizedFileURL
        let json = String(decoding: Telemetry.encode(r, pretty: true), as: UTF8.self) + "\n"
        if ProcessInfo.processInfo.environment["YAAK_UPDATE_FIXTURES"] != nil { try json.write(to: fixture, atomically: true, encoding: .utf8) }
        #expect(try String(contentsOf: fixture, encoding: .utf8) == json)
    }

    @Test func buckets() {
        #expect([0, 1, 2, 5, 6, 20, 21, 100, 101].map { Telemetry.bucket($0) }
                == ["0", "1", "2-5", "2-5", "6-20", "6-20", "21-100", "21-100", "100+"])
        #expect([0, 0.5, 1, 3, 8, 30].map { Telemetry.bucket(hours: $0) } == ["0", "<1", "1-3", "3-8", "8-24", "24+"])
        #expect([0.1, 0.5, 1, 2, 4].map { Telemetry.bucket(leverage: $0) } == ["<0.5", "0.5-1", "1-2", "2-4", "4+"])
    }

    @Test func dayKeys() {
        let d = Date(timeIntervalSince1970: 86_400 * 3 + 3600)
        #expect(Telemetry.dayKey(d, calendar: utc) == "1970-01-04")
        #expect(Telemetry.interval(ofDay: "1970-01-04", calendar: utc)?.contains(d) == true)
        #expect(Telemetry.interval(ofDay: "bad", calendar: utc) == nil)
    }

    @Test func doNotTrackAndJumpKinds() {
        #expect(Telemetry.doNotTrack(["DO_NOT_TRACK": "1"]))
        #expect(!Telemetry.doNotTrack(["DO_NOT_TRACK": "0"]) && !Telemetry.doNotTrack([:]))
        #expect(TelemetryEvent.jump(TerminalContext(termProgram: "iTerm.app")) == .jumpIterm)
        #expect(TelemetryEvent.jump(TerminalContext(termProgram: "WarpTerminal")) == .jumpOther)
        #expect(TelemetryEvent.jump(TerminalContext(waveBlockId: "b")) == .jumpWave)
        #expect(TelemetryEvent.jump(nil) == .jumpUnknown)
    }
}
