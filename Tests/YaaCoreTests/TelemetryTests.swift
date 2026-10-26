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
        // A day more than seven calendar days back is never sent (the server would refuse it).
        l.note(day: "2026-10-11")
        #expect(l.pending(today: "2026-10-18") == ["2026-10-11"])
        #expect(l.pending(today: "2026-10-19").isEmpty)
    }

    @Test func roundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-tel-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(atPath: url.path + ".lock") }
        #expect(TelemetryLedger.load(url) == TelemetryLedger())
        TelemetryLedger.update(url) { $0.set(enabled: true) }
        TelemetryLedger.update(url) { $0.note(.pin, day: "2026-10-22") }
        let l = TelemetryLedger.load(url)
        #expect(l.enabled && l.days["2026-10-22"] == ["pin": 1])
    }

    /// The app and `yaak` both write the file; concurrent updates must not lose each other's edits.
    @Test func concurrentUpdatesAllLand() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-tel-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(atPath: url.path + ".lock") }
        TelemetryLedger.update(url) { $0.set(enabled: true) }
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            TelemetryLedger.update(url) { $0.note(.pin, day: "2026-10-22") }
        }
        #expect(TelemetryLedger.load(url).days["2026-10-22"]?["pin"] == 200)
    }

    /// Ledgers written before `lastResult` existed still load; a send's outcome is kept until off.
    @Test func sendResult() throws {
        let old = #"{"asked":true,"enabled":true,"installId":"x","days":{},"lastSent":"2026-10-24"}"#
        var l = try JSONDecoder().decode(TelemetryLedger.self, from: Data(old.utf8))
        #expect(l.lastSent == "2026-10-24" && l.lastResult == nil)
        let u = URL(string: "https://us.aptabase.com/api/v0/events")!
        let ok = HTTPURLResponse(url: u, statusCode: 200, httpVersion: nil, headerFields: nil)
        let bad = HTTPURLResponse(url: u, statusCode: 401, httpVersion: nil, headerFields: nil)
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(TelemetryLedger.SendResult(at: Date(), days: ["d"], response: ok, error: nil).ok)
        #expect(!TelemetryLedger.SendResult(at: Date(), days: ["d"], response: bad, error: nil).ok)
        let r = TelemetryLedger.SendResult(at: Date(), days: ["d"], response: nil, error: offline)
        #expect(!r.ok && r.error == "NSURLErrorDomain -1009" && r.status == nil)
        l.lastResult = r
        l.set(enabled: false)
        #expect(l.lastResult == nil)
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

    /// The Aptabase event carries the report flattened into string props and nothing else:
    /// the install id only hashed, counts bucketed, in a shape Aptabase's ingest accepts.
    @Test func aptabaseEvent() throws {
        var f = TelemetryFigures()
        f.sessions = [.claudeCode: 3]
        f.agentHours = 4.2
        let r = Telemetry.makeReport(installId: "e617184b-ea01-4296-a57c-3a770a5f8ef8", day: "2026-10-22", env: env,
                                     integrations: [.claudeCode: "installed"], settings: [.slimRail: true],
                                     counts: ["jump_wave": 7], figures: f)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let e = AptabaseEvent(report: r, at: at, debug: true)
        #expect(e.props["install"]?.count == 64 && e.props["install"] != r.installId)
        #expect(e.props["count.jump_wave"] == "6-20")
        #expect(e.props["figure.sessions.claude-code"] == "2-5")
        #expect(e.props["setting.slim_rail"] == "on")
        #expect(e.props["integration.claude-code"] == "installed")
        #expect(e.props["day"] == "2026-10-22")
        #expect(e.systemProps.appVersion == "0.1.0" && e.systemProps.osName == "macOS" && e.systemProps.isDebug)
        // Aptabase drops events whose session id does not start at the event's second, give or take.
        #expect(UInt64(e.sessionId).map { $0 / 100_000_000 } == 1_800_000_000)
        let body = AptabaseEvent.body([e])
        #expect(!String(decoding: body, as: UTF8.self).contains(r.installId))
        let arr = try #require(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(Set(arr[0].keys) == ["timestamp", "sessionId", "eventName", "systemProps", "props"])
        #expect(arr[0]["timestamp"] as? String == "2027-01-15T08:00:00Z")
        #expect(arr[0]["eventName"] as? String == "daily")
        let sys = try #require(arr[0]["systemProps"] as? [String: Any])
        #expect(sys["isDebug"] as? Bool == true && (sys["sdkVersion"] as? String)?.isEmpty == false)
    }

    /// Aptabase rejects prop keys over 40 characters; the longest come from every agent and event.
    @Test func aptabasePropKeysFit() {
        var f = TelemetryFigures()
        for a in AgentKind.allCases { f.sessions[a] = 1; f.turns[a] = 1 }
        let r = Telemetry.makeReport(installId: "x", day: "2026-10-22", env: env,
                                     integrations: Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, "installed") }),
                                     settings: Dictionary(uniqueKeysWithValues: TelemetrySetting.allCases.map { ($0, true) }),
                                     counts: Dictionary(uniqueKeysWithValues: TelemetryEvent.allCases.map { ($0.rawValue, 1) }),
                                     figures: f)
        let keys = AptabaseEvent(report: r).props.keys
        #expect(keys.allSatisfy { $0.count <= AptabaseEvent.maxKey }, "\(keys.filter { $0.count > AptabaseEvent.maxKey })")
    }

    @Test func aptabaseRegions() {
        #expect(AptabaseEvent.ingestURL(appKey: "A-EU-1234567890")?.host == "eu.aptabase.com")
        #expect(AptabaseEvent.ingestURL(appKey: "A-US-1234567890")?.absoluteString == "https://us.aptabase.com/api/v0/events")
        #expect(AptabaseEvent.ingestURL(appKey: "A-SH-1234567890") == nil)
        #expect(AptabaseEvent.ingestURL(appKey: "EF0ED3E0-A85B-4574-8D60-09E5DD6D9B2B") == nil)
        #expect(AptabaseEvent.ingestURL(appKey: "") == nil)
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
        #expect(Telemetry.day("2026-03-02", minus: 7) == "2026-02-23")
        // Keys stay Gregorian whatever calendar the user picked in System Settings.
        #expect(Telemetry.calendar.identifier == .gregorian)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC")!
        #expect(Telemetry.dayKey(d, calendar: buddhist) != "1970-01-04")
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

/// Release bundles copy `Resources/Info.plist`; its key must name a region the app can send to.
@Test func shippedInfoPlistAppKeyIsUsable() throws {
    let plist = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Info.plist")
    let info = try #require(NSDictionary(contentsOf: plist))
    let key = try #require(info[Telemetry.appKeyKey] as? String)
    #expect(AptabaseEvent.ingestURL(appKey: key)?.host == "us.aptabase.com")
}
