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
