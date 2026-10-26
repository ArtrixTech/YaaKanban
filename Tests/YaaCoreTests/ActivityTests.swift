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
        // Present 150 s; all 360 s of agent time count, the away part costing the user nothing.
        #expect(abs(r.leverage! - 360.0 / 150) < 1e-9)
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
        #expect(abs(trend[0]! - 2.6) < 1e-9)
        // 50 s present is under a minute: no figure.
        #expect(trend[1] == nil && trend[2] == nil)
        // The whole range as one window is the report's own leverage.
        #expect(abs(r.rollingLeverage(window: 4)[0]! - r.leverage!) < 1e-9)
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
