import Foundation
import Testing
@testable import YaaCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

private func session(_ status: SessionStatus, _ id: String = "s1", at s: TimeInterval = 0) -> SessionState {
    var st = SessionState(agent: .claudeCode, sessionId: id, at: at(0))
    st.status = status
    st.lastEventAt = at(s)
    st.projectDir = "/tmp/proj"
    return st
}

private func lane(_ id: String, _ s: TimeInterval, _ l: Lane?) -> ActivityRow {
    ActivityRow(at: at(s), session: "claude-code:\(id)", kind: .lane, text: l?.rawValue ?? "")
}

@Suite struct ActivityRows {
    @Test func laneChangesOnly() {
        let run = session(.running)
        #expect(Activity.rows(old: nil, new: run, now: at(0)).map(\.text) == ["running"])
        #expect(Activity.rows(old: run, new: run, now: at(1)).isEmpty)
        var done = session(.idle, at: 5)
        done.unreadSince = at(5)
        #expect(Activity.rows(old: run, new: done, now: at(5)).map(\.text) == ["review"])
        var read = done
        read.unreadSince = nil
        #expect(Activity.rows(old: done, new: read, now: at(9)).map(\.text) == [""])
        // An agent exit after review changes nothing for the lanes.
        var gone = read
        gone.status = .ended
        #expect(Activity.rows(old: read, new: gone, now: at(10)).isEmpty)
    }

    @Test func subagentsHaveNoLaneButCountTokens() {
        var a = session(.running, "sub")
        a.parentId = "claude-code:s1"
        a.usage = Usage()
        var b = a
        b.usage?.output = 500
        let rows = Activity.rows(old: a, new: b, now: at(1))
        #expect(rows.map(\.kind) == [.tokens])
        #expect(rows.first?.value == 500)
    }

    @Test func linkedAsSubagentLeavesTheLanes() {
        let top = session(.running, "sub")
        var linked = top
        linked.parentId = "claude-code:s1"
        #expect(Activity.rows(old: top, new: linked, now: at(1)).map(\.text) == [""])
    }

    @Test func replyAfterFinishedTurn() {
        var idle = session(.idle, at: 10)
        idle.turns = [Turn(id: 1, prompt: "a", startedAt: at(0), endedAt: at(10), toolCount: 3)]
        idle.unreadSince = at(10)
        var next = idle
        next.status = .running
        next.unreadSince = nil
        next.turns.append(Turn(id: 2, prompt: "b", startedAt: at(70), toolCount: 0))
        let reply = Activity.rows(old: idle, new: next, now: at(70)).first { $0.kind == .reply }
        #expect(reply?.value == 60)
        #expect(reply?.at == at(70))
        #expect(reply?.text == "proj")
        // Already reviewed (or resumed days later): nobody was waiting on the user.
        var read = idle
        read.unreadSince = nil
        #expect(Activity.rows(old: read, new: next, now: at(70)).allSatisfy { $0.kind != .reply })
    }

    @Test func replyToBlockedPrompt() {
        var wait = session(.needsInput, at: 20)
        wait.needsInputSince = at(20)
        var go = wait
        go.status = .running
        go.lastEventAt = at(45)
        #expect(Activity.rows(old: wait, new: go, now: at(45)).first { $0.kind == .reply }?.value == 25)
        // Stuck going on by itself is not a reply.
        let stuck = session(.stuck, at: 20)
        #expect(Activity.rows(old: stuck, new: go, now: at(45)).allSatisfy { $0.kind != .reply })
    }

    @Test func turnRowOnceWhenItEnds() {
        var run = session(.running)
        run.turns = [Turn(id: 1, prompt: "a", startedAt: at(0), toolCount: 4)]
        var done = run
        done.status = .idle
        done.turns[0].endedAt = at(30)
        let rows = Activity.rows(old: run, new: done, now: at(30)).filter { $0.kind == .turn }
        #expect(rows.count == 1 && rows[0].value == 4)
        var again = done
        again.turns[0].endedAt = at(31)
        #expect(Activity.rows(old: done, new: again, now: at(31)).allSatisfy { $0.kind != .turn })
    }

    @Test func tokensBaselineForOldSessions() {
        var s = session(.running)
        s.usage = Usage()
        s.usage?.input = 1000
        s.usage?.cacheRead = 9000
        // Seen from its start: counted in full.
        #expect(Activity.rows(old: nil, new: s, now: at(30)).first { $0.kind == .tokens }?.value == 1000)
        // First seen an hour in: only the baseline.
        #expect(Activity.rows(old: nil, new: s, now: at(3600)).allSatisfy { $0.kind != .tokens })
    }
}

@Suite struct InterruptRows {
    private func turn(_ id: Int, end: TimeInterval?, cut: Bool? = nil) -> Turn {
        var t = Turn(id: id, prompt: "p", startedAt: at(Double(id)), endedAt: end.map(at), toolCount: 2)
        t.interrupted = cut
        return t
    }

    @Test func countedOnceWhenEndedAndMarked() {
        var a = session(.running)
        a.turns = [turn(1, end: nil, cut: true)]
        var b = a
        b.turns = [turn(1, end: 5, cut: true), turn(2, end: nil)]
        #expect(Activity.rows(old: a, new: b, now: at(5)).filter { $0.kind == .interrupt }.map(\.at) == [at(5)])
        // Marked later by the transcript: one row, at the turn's end.
        var c = session(.idle)
        c.turns = [turn(1, end: 5)]
        var d = c
        d.turns[0].interrupted = true
        #expect(Activity.rows(old: c, new: d, now: at(30)).filter { $0.kind == .interrupt }.map(\.at) == [at(5)])
        #expect(Activity.rows(old: d, new: d, now: at(31)).isEmpty)
    }

    @Test func rateOverFinishedTurns() {
        let rows = [ActivityRow(at: at(10), session: "s", kind: .turn, value: 1),
                    ActivityRow(at: at(20), session: "s", kind: .turn, value: 1),
                    ActivityRow(at: at(20), session: "s", kind: .interrupt),
                    ActivityRow(at: at(30), session: "s", kind: .turn, value: 1),
                    ActivityRow(at: at(40), session: "s", kind: .turn, value: 1)]
        let r = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 100), now: at(100))
        #expect(r.interrupts == 1 && r.interruptRate == 0.25)
        // Turns before interrupts were recorded are left out of the rate.
        let later = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 100),
                                           now: at(100), interruptsSince: at(15))
        #expect(later.turns == 4 && later.interruptTurns == 3 && later.interruptRate == 1.0 / 3)
        #expect(ActivityReport.compute(rows: [], lanesBefore: [:], range: DateInterval(start: t0, duration: 100), now: at(100)).interruptRate == nil)
    }
}

@Suite struct Report {
    @Test func parallelismBottleneckUtilization() {
        // a runs 0–100; b runs 50–150 then waits 150–250; nothing after.
        let rows = [lane("a", 0, .running), lane("b", 50, .running), lane("a", 100, nil),
                    lane("b", 150, .needsInput), lane("b", 250, nil)]
        let r = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 400),
                                       now: at(1000), buckets: 4)
        #expect(r.lanes.map(\.session) == ["claude-code:a", "claude-code:b"])
        #expect(r.parallelPeak == 2)
        // Running time 200 over 150 s with something running.
        #expect(abs(r.parallelAverage - 200.0 / 150) < 1e-9)
        #expect(r.bottleneck == 100)
        #expect(r.activeTime == 250)
        #expect(abs(r.utilization! - 200.0 / 300) < 1e-9)
        #expect(r.parallelBuckets.map { ($0 * 100).rounded() / 100 } == [1.5, 0.5, 0, 0])
        #expect(r.waitingBuckets.map { ($0 * 100).rounded() / 100 } == [0, 0.5, 0.5, 0])
        #expect(r.sessionTotals.map(\.session) == ["claude-code:b", "claude-code:a"])
        #expect(r.sessionTotals.first.map { [$0.running, $0.waiting] } == [100, 100])
        #expect(r.agentTime == 200)
        #expect(r.agentTimeAway == 0)
        #expect(abs(r.leverage! - 200.0 / 250) < 1e-9)
        #expect(r.longestRun?.duration == 100)
    }

    @Test func agentHoursWhileAway() {
        // a runs 0–300 with the user away 100–250; b runs 0–60 and finishes a turn.
        let rows = [lane("a", 0, .running), lane("a", 300, nil), lane("b", 0, .running), lane("b", 60, nil),
                    ActivityRow(at: at(60), session: "claude-code:b", kind: .turn, value: 3),
                    ActivityRow(at: at(100), session: "", kind: .away, value: 150)]
        let r = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 400), now: at(500))
        #expect(r.agentTime == 360)
        #expect(r.agentTimeAway == 150)
        // Present 150 s with 210 s of work; the 150 s away is set against present time and 30 min.
        #expect(r.presentWork == 210 && r.awayWork == 150)
        #expect(abs(r.leverage! - (210.0 / 150 + 150.0 / (150 + 1800))) < 1e-9)
        #expect(r.utilizationAway == 1 && r.blockedAway == 0)
        #expect(r.longestRun?.session == "claude-code:a")
        #expect(r.longestRun?.duration == 300)
        #expect(r.turnsBySession == ["claude-code:b": 1])
    }

    @Test func rollingLeverageEndsAtTheWindowsLeverage() {
        // Same rows, 100 s slices: present 0–100 (a, b), 250–300 (a), away 100–250.
        let rows = [lane("a", 0, .running), lane("a", 300, nil), lane("b", 0, .running), lane("b", 60, nil),
                    ActivityRow(at: at(100), session: "", kind: .away, value: 150)]
        let r = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 400),
                                       now: at(500), buckets: 4)
        #expect(r.activeBuckets == [100, 0, 50, 0])
        #expect(r.agentBuckets == [160, 100, 100, 0])
        let trend = r.rollingLeverage(window: 2)
        #expect(trend.count == 3)
        // Only the work while present counts on the panel.
        #expect(abs(trend[0]! - 1.6) < 1e-9)
        // 50 s present is under a minute: no figure.
        #expect(trend[1] == nil && trend[2] == nil)
        // The whole range as one window is the report's leverage while present.
        #expect(abs(r.rollingLeverage(window: 4)[0]! - r.presentWork / r.activeTime) < 1e-9)
    }

    @Test func rollingLeverageOverHourEdgesMatchesEachWindowsReport() {
        // Hourly slices, read 4 at a time, give each 4-hour window's leverage while present.
        let rows = [lane("a", 0, .running), lane("a", 9000, nil), lane("b", 3600, .running), lane("b", 20000, .needsInput),
                    lane("b", 22000, nil), ActivityRow(at: at(5000), session: "", kind: .away, value: 4000)]
        let edges = (0...6).map { at(Double($0) * 3600) }
        let r = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: edges[0], end: edges[6]),
                                       now: at(30000), edges: edges)
        let rolled = r.rollingLeverage(window: 4)
        #expect(rolled.count == 3)
        for (k, v) in rolled.enumerated() {
            // What the store hands a report starting there: each session's lane before it.
            var before: [String: Lane] = [:]
            for row in rows where row.kind == .lane && row.at < edges[k] { before[row.session] = Lane(rawValue: row.text) }
            let w = ActivityReport.compute(rows: rows, lanesBefore: before.compactMapValues { $0 }, range: DateInterval(start: edges[k], end: edges[k + 4]),
                                           now: at(30000), buckets: 1)
            #expect(abs(v! - w.presentWork / w.activeTime) < 1e-9)
        }
    }

    @Test func blockedReviewAndInterventions() {
        // a runs 0–100, waits for review 100–160 (away 120–140 inside), then is looked at.
        // b asks 0–50, is answered and runs to 80; one turn. c asks 200–400, user away 250–500.
        let rows = [lane("a", 0, .running), lane("a", 100, .review), lane("a", 160, nil),
                    lane("b", 0, .needsInput), lane("b", 50, .running), lane("b", 80, nil),
                    ActivityRow(at: at(80), session: "claude-code:b", kind: .turn, value: 1),
                    lane("c", 200, .needsInput), lane("c", 400, nil),
                    ActivityRow(at: at(120), session: "", kind: .away, value: 20),
                    ActivityRow(at: at(250), session: "", kind: .away, value: 250)]
        let r = ActivityReport.compute(rows: rows, lanesBefore: ["d": .review], range: DateInterval(start: t0, duration: 600),
                                       now: at(1000))
        // Review is idle, not blocked: only c's present wait 200–250 stalls everything.
        #expect(r.bottleneck == 50)
        #expect(abs(r.utilization! - 130.0 / 230) < 1e-9)
        #expect(r.blockedAway == 150)
        #expect(r.utilizationAway == 0)
        // a's review less the 20 s away; d's review was carried in, so its start is unknown.
        #expect(r.pickups == [40])
        #expect(r.pickupMean == 40)
        #expect(r.interventions == 2)
        #expect(r.agentTimePerIntervention == 65)
    }

    @Test func bucketsSpanTheWholeRange() {
        // Now halfway in: the buckets still split the full range, the later ones empty.
        let r = ActivityReport.compute(rows: [], lanesBefore: ["x": .running], range: DateInterval(start: t0, duration: 1000),
                                       now: at(500), buckets: 4)
        #expect(r.parallelBuckets.map { ($0 * 100).rounded() / 100 } == [1, 1, 0, 0])
    }

    @Test func bucketsOnUnevenSpans() {
        // Spans whose bucket edges do not divide evenly once looped forever.
        for span in stride(from: 3600.37, to: 3700, by: 0.37) {
            let r = ActivityReport.compute(rows: [lane("a", 0, .running)], lanesBefore: [:],
                                           range: DateInterval(start: t0, duration: span), now: at(span))
            #expect(r.parallelBuckets.count == 48)
            #expect(r.parallelBuckets.allSatisfy { abs($0 - 1) < 1e-6 })
        }
    }

    @Test func awayTimeIsLeftOut() {
        let rows = [lane("a", 0, .needsInput), lane("a", 100, nil),
                    ActivityRow(at: at(20), session: "", kind: .away, value: 50),
                    ActivityRow(at: at(100), session: "claude-code:a", kind: .reply, value: 100)]
        let r = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 200), now: at(500))
        #expect(r.bottleneck == 50)
        #expect(r.activeTime == 50)
        #expect(r.replies == [50])
        #expect(r.away == [DateInterval(start: at(20), duration: 50)])
        #expect(r.sessionTotals.first?.waiting == 50)
        #expect(r.waitingBuckets.reduce(0, +) > 0)
    }

    @Test func replyMeanCountsEveryReply() {
        // One wait spent wholly away still counts, as 0 s: the mean stays off 0 where a median would not.
        let rows = [ActivityRow(at: at(100), session: "claude-code:a", kind: .reply, value: 10),
                    ActivityRow(at: at(200), session: "claude-code:a", kind: .reply, value: 20),
                    ActivityRow(at: at(300), session: "claude-code:a", kind: .reply, value: 60),
                    ActivityRow(at: at(240), session: "", kind: .away, value: 60)]
        let r = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 400), now: at(500))
        #expect(r.replies == [10, 20, 0])
        #expect(r.replyMean == 10)
        #expect(ActivityReport.compute(rows: [], lanesBefore: [:], range: DateInterval(start: t0, duration: 400), now: at(500)).replyMean == nil)
    }

    @Test func lanesCarriedIntoRangeAndClippedAtNow() {
        let r = ActivityReport.compute(rows: [], lanesBefore: ["x": .running], range: DateInterval(start: t0, duration: 1000),
                                       now: at(300), awaySince: at(200))
        #expect(r.lanes.first?.segments == [ActivityReport.Segment(lane: .running, start: t0, end: at(300))])
        #expect(r.away == [DateInterval(start: at(200), end: at(300))])
        #expect(r.activeTime == 200)
    }

    @Test func percentiles() {
        let xs: [TimeInterval] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        #expect(ActivityReport.percentile(xs, 0.5) == 5)
        #expect(ActivityReport.percentile(xs, 0.9) == 9)
        #expect(ActivityReport.percentile([], 0.5) == nil)
    }

    @Test func backlogOldestWait() {
        var a = session(.needsInput, "a", at: 50)
        a.needsInputSince = at(40)
        var b = session(.idle, "b", at: 10)
        b.unreadSince = at(10)
        var c = session(.idle, "c")
        c.unreadSince = at(1)
        c.dismissedAt = at(2)
        let bl = Backlog([a, b, c, session(.running, "d")])
        #expect(bl.count == 2)
        #expect(bl.oldest == at(10))
    }
}

@Suite struct ActivityStore {
    @Test func roundTripAndLanesBefore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(path: url)
        store.record([lane("a", 0, .running), lane("a", 100, .review), lane("b", 50, .running), lane("b", 60, nil),
                      ActivityRow(at: at(-500), session: "", kind: .away, value: 600),
                      ActivityRow(at: at(-500), session: "", kind: .away, value: 100)])
        #expect(store.lanes(before: at(80)) == ["claude-code:a": .running])
        #expect(store.lanes() == ["claude-code:a": .review])
        let rows = store.activity(from: at(0), to: at(200))
        // The long away reaches into the range; the short one does not.
        #expect(rows.filter { $0.kind == .away }.map(\.value) == [600])
        #expect(rows.filter { $0.kind == .lane }.count == 4)
        // Deleting a session keeps past days' numbers.
        store.delete(id: "claude-code:a")
        #expect(store.lanes() == ["claude-code:a": .review])
        store.record([], meta: ["heartbeat": 42])
        #expect(store.meta("heartbeat") == 42)
        #expect(store.meta("nope") == nil)
        // Two rows at the same time: the later insert counts.
        store.record([lane("c", 10, .running), lane("c", 10, .review)])
        #expect(store.lanes(before: at(80))["claude-code:c"] == .review)
    }

    @Test func replyWaitStartingBeforeTheRangeTakesItsAwayOut() throws {
        // Waiting since 0, away 10–90, replied at 110: the day starting at 100 sees a 30 s reply.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(path: url)
        store.record([ActivityRow(at: at(10), session: "", kind: .away, value: 80),
                      ActivityRow(at: at(110), session: "claude-code:a", kind: .reply, value: 110)])
        let range = DateInterval(start: at(100), end: at(200))
        let r = ActivityReport.compute(rows: store.activity(from: range.start, to: range.end), lanesBefore: [:],
                                       range: range, now: at(200))
        #expect(r.replies == [30])
        // The earlier away row only serves the reply; the range's own away is unchanged.
        #expect(r.away.isEmpty)
    }
}

@Suite struct Backfill {
    @Test func turnsBecomeRunningLanes() {
        var s = session(.idle)
        s.turns = [Turn(id: 1, prompt: "a", startedAt: at(0), endedAt: at(100), toolCount: 2),
                   Turn(id: 2, prompt: "b", startedAt: at(200), endedAt: at(400), toolCount: 5)]
        var sub = session(.idle, "sub")
        sub.parentId = s.id
        sub.turns = s.turns
        let rows = ActivityBackfill.rows([s, sub], before: at(300))
        #expect(rows.allSatisfy { $0.session == s.id })
        let r = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 1000), now: at(1000))
        // The second turn is cut just before the cutoff; only the first finished before it.
        #expect(abs(r.activeTime - 200) < 0.01)
        #expect(r.turns == 1 && r.toolCalls == 2)
        #expect(r.bottleneck == 0)
    }
}

@Suite struct Periods_ {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 1
        return c
    }()
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func dayEdgesFollowTheClockAcrossDaylightSaving() {
        let p = Periods(.day, back: 0, now: date(2025, 3, 9, 12), calendar: cal)
        #expect(p.edges.count == 47)  // 23 hours
        #expect(p.edges.contains(date(2025, 3, 9, 3)))
        #expect(p.previousEdges.count == 49)
        #expect(Periods(.day, back: 0, now: date(2025, 11, 2, 12), calendar: cal).edges.count == 49)  // 1:00 once
    }

    @Test func weekEdgesStayOnThreeHourMarks() {
        let p = Periods(.week, back: 0, now: date(2025, 3, 12, 12), calendar: cal)
        #expect(p.range.start == date(2025, 3, 9))
        #expect(p.edges.count == 57)
        #expect(p.edges.contains(date(2025, 3, 15, 21)))
    }

    @Test func monthEdgesAreDays() {
        let p = Periods(.month, back: 0, now: date(2025, 3, 20), calendar: cal)
        #expect(p.edges.count == 32)
        #expect(p.edges[10] == date(2025, 3, 11))
        #expect(p.previousEdges.count == 29)
    }

    @Test func previousSoFarIsTheSameClockTime() {
        // Day after the clocks went forward: yesterday up to the same 12:00, not 13:00.
        let p = Periods(.day, back: 0, now: date(2025, 3, 10, 11, 55), calendar: cal)
        #expect(p.previousSoFar == DateInterval(start: date(2025, 3, 9), end: date(2025, 3, 9, 12)))
        // A past day: the whole day before.
        let q = Periods(.day, back: 1, now: date(2025, 3, 10, 11, 55), calendar: cal)
        #expect(q.previousSoFar == q.previous && q.previous.start == date(2025, 3, 8))
        // Late in a long month: capped at the shorter month's end.
        let m = Periods(.month, back: 0, now: date(2025, 3, 30, 12), calendar: cal)
        #expect(m.previousSoFar.end == date(2025, 3, 1))
    }

    @Test func explicitEdgesSliceTheReport() {
        let t = date(2025, 3, 1)
        let edges = [t, t.addingTimeInterval(100), t.addingTimeInterval(400)]
        let r = ActivityReport.compute(rows: [], lanesBefore: ["x": .running], range: DateInterval(start: t, duration: 400),
                                       now: t.addingTimeInterval(200), edges: edges)
        #expect(r.parallelBuckets.count == 2)
        #expect(r.parallelBuckets[0] == 1)
        #expect(abs(r.parallelBuckets[1] - 1.0 / 3) < 1e-9)
    }
}

private func held(_ id: String, _ s: TimeInterval, since: TimeInterval? = nil) -> ActivityRow {
    .held("claude-code:\(id)", at: at(s), since: at(since ?? s))
}

@Suite struct HeldWork {
    private let tau = ActivityReport.heldHalfLife

    @Test func heldWorkCountsForLessTheLongerItWaits() {
        // a works 0–100, then waits on a background job until 100 + τ.
        let rows = [lane("a", 0, .running), held("a", 100), lane("a", 100 + tau, nil)]
        let r = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 2 * tau),
                                       now: at(4 * tau))
        #expect(abs(r.presentWork - (100 + tau * log(2))) < 1e-6)
        // Raw agent time, the lane and the longest run are unchanged by the hold.
        #expect(r.agentTime == 100 + tau)
        #expect(r.lanes.first?.segments.count == 1)
        #expect(r.longestRun?.duration == 100 + tau)
        #expect(r.activeTime == 100 + tau)
    }

    @Test func aHoldCarriedInOrMarkedAgainKeepsItsStart() {
        // Held since τ before the range: the range's τ counts from weight 1/2 down.
        let carried = ActivityReport.compute(rows: [], lanesBefore: ["claude-code:a": .running], heldBefore: ["claude-code:a": at(-tau)],
                                             range: DateInterval(start: t0, duration: tau), now: at(tau))
        #expect(abs(carried.presentWork - tau * log(1.5)) < 1e-6)
        // Marked held again while held: the wait still runs from its first mark.
        let rows = [held("a", 0), held("a", tau), lane("a", 2 * tau, nil)]
        let again = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 3 * tau),
                                           now: at(3 * tau))
        #expect(abs(again.presentWork - tau * log(3)) < 1e-6)
        // Reopened after a relaunch, held since before the app stopped: it counts down from then.
        let reopened = ActivityReport.compute(rows: [held("a", tau, since: 0), lane("a", 2 * tau, nil)], lanesBefore: [:],
                                              range: DateInterval(start: t0, duration: 3 * tau), now: at(3 * tau))
        #expect(abs(reopened.presentWork - tau * log(1.5)) < 1e-6)
        // Legacy marks (`value` 1) start at the row.
        #expect(ActivityRow(at: at(5), session: "x", kind: .lane, value: 1, text: "running").heldSince == at(5))
    }

    @Test func workWhileAwayGoesToTheSliceTheUserLeftIn() {
        // a runs 0–3000; the user is away 500–2500, leaving in the first of two 1000 s slices.
        let rows = [lane("a", 0, .running), lane("a", 3000, nil), ActivityRow(at: at(500), session: "", kind: .away, value: 2000)]
        let first = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 1000), now: at(3000))
        #expect(first.presentWork == 500)
        // The whole absence, past the range's end.
        #expect(first.awayWork == 2000)
        #expect(abs(first.leverage! - (1 + 2000.0 / (500 + 1800))) < 1e-9)
        // The range after it: the absence began before, so only its own present time counts.
        let later = ActivityReport.compute(rows: rows, lanesBefore: ["claude-code:a": .running],
                                           range: DateInterval(start: at(1000), duration: 2000), now: at(3000))
        #expect(later.presentWork == 500 && later.awayWork == 0)
        #expect(later.leverage == 1)
        // Days: the absence counts in the slice it began in.
        let days = ActivityReport.compute(rows: rows, lanesBefore: [:], range: DateInterval(start: t0, duration: 3000),
                                          now: at(3000), edges: [t0, at(1000), at(2000), at(3000)])
        #expect(days.awayWorkBuckets == [2000, 0, 0])
        #expect(days.presentWorkBuckets == [500, 0, 500])
        #expect(days.leverage(at: 1) == nil)
    }

    @Test func rowsMarkHoldsAsTheyStartAndEnd() {
        var working = session(.running)
        working.turns = [Turn(id: 1, prompt: "p", startedAt: at(0), endedAt: nil, toolCount: 1)]
        var waiting = working
        waiting.turns[0].endedAt = at(50)
        waiting.backgroundTasks = ["train"]
        let start = Activity.rows(old: working, new: waiting, now: at(50)).filter { $0.kind == .lane }
        #expect(start.map(\.text) == ["running"] && start.map(\.heldSince) == [at(50)])
        // Seen held only now (a relaunch): the wait began where the turn ended.
        let seen = Activity.laneRow(waiting, .running, now: at(500), working: false)
        #expect(seen.at == at(500) && seen.heldSince == at(50))
        #expect(Activity.rows(old: waiting, new: waiting, now: at(60)).filter { $0.kind == .lane }.isEmpty)
        var back = waiting
        back.turns.append(Turn(id: 2, prompt: "q", startedAt: at(70), endedAt: nil, toolCount: 0))
        let end = Activity.rows(old: waiting, new: back, now: at(70)).filter { $0.kind == .lane }
        #expect(end.map(\.text) == ["running"] && end.map(\.value) == [0])
        // A background agent still at work is not a hold.
        var delegating = waiting
        delegating.subagents = [Subagent(id: "x", type: "general", startedAt: at(40))]
        #expect(!Activity.held(delegating))
    }

    @Test func timelineKeepsOneSpanAcrossAHold() {
        let s = session(.idle, at: 200)
        let rows = [lane("s1", 0, .running), held("s1", 100), lane("s1", 200, nil)]
        let t = SessionTimeline(rows: rows, session: s, now: at(300), inLane: false)
        #expect(t.spans == [SessionTimeline.Span(lane: .running, start: at(0), end: at(200))])
    }

    @Test func backfillMarksRunningOutsideTurns() {
        func turn(_ a: TimeInterval, _ b: TimeInterval?) -> Turn {
            Turn(id: Int(a), prompt: "p", startedAt: at(a), endedAt: b.map(at), toolCount: 1)
        }
        // a: turns 0–100 and 400–500, running 0–900. A 30 s gap is left.
        var a = session(.idle, "a", at: 900)
        a.turns = [turn(0, 100), turn(130, 160), turn(400, 500)]
        // b: running since 0 and held now; c: running since 0 and back in a turn the record hasn't seen.
        var b = session(.running, "b", at: 100)
        b.turns = [turn(0, 100)]
        b.backgroundTasks = ["train"]
        var c = session(.running, "c", at: 100)
        c.turns = [turn(0, 100)]
        // d: a background agent's calls run on after its turn's Stop at 100, until 400.
        var d = session(.idle, "d", at: 400)
        d.turns = [turn(0, 100)]
        var call = ToolCall(id: "1", name: "Bash", summary: "", input: "{}", output: nil, isError: false, startedAt: at(90))
        call.endedAt = at(400)
        call.subagentId = "x"
        d.tools = [call]
        // e: reopened at 1000 after a relaunch, held since its turn ended at 100. Removed sessions keep their lanes.
        var e = session(.running, "e", at: 100)
        e.turns = [turn(0, 100)]
        e.backgroundTasks = ["train"]
        let lanes = [lane("a", 0, .running), lane("a", 900, nil), lane("b", 0, .running), lane("c", 0, .running),
                     lane("d", 0, .running), lane("d", 900, nil), lane("e", 0, .running), lane("e", 200, nil),
                     lane("e", 1000, .running), lane("gone", 0, .running), lane("gone", 900, nil)]
        let rows = HeldBackfill.rows([a, b, c, d, e], lanes: lanes, until: at(2000))
        func of(_ id: String) -> [[Double]] {
            rows.filter { $0.session == "claude-code:\(id)" }.map { r in
                [r.at.timeIntervalSince(t0), r.heldSince.map { $0.timeIntervalSince(t0) } ?? -1]
            }
        }
        #expect(of("a") == [[160, 160], [400, -1], [500, 500]])
        #expect(of("b") == [[100, 100]])
        #expect(of("c").map { $0.map { ($0 * 1000).rounded() / 1000 } } == [[100, 100], [1999.999, -1]])
        #expect(of("d") == [[400, 400]])
        #expect(of("e").map { $0.map { ($0 * 1000).rounded() / 1000 } } == [[100, 100], [1000.001, 100]])
        #expect(of("gone").isEmpty)
        #expect(rows.allSatisfy { $0.text == Lane.running.rawValue })
    }
}
