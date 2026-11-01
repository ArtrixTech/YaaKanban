import SwiftUI
import YaaCore

/// A session's detail: its figures (tokens, turns, time, your input), what needs the user, what the
/// latest turn came to, where the time went, every turn in brief, the files it touched and what it
/// cost; the raw tool log folded at the end.
struct SessionDetail: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    /// The session's recorded activity, read when it opens and when a turn or state changes.
    @State private var rows: [ActivityRow] = []
    @State private var openTurn: Int?
    /// The open tool row: "f<i>" in the failures, "l<i>" in the log (ids repeat for some agents).
    @State private var openTool: String?
    /// The insight of the session as last computed; the body runs on any session's change.
    @State private var memo = Memo()
    @State private var allTurns = false
    @State private var showLog = false
    @State private var showReads = false

    var body: some View {
        let st = model.display(session)
        let now = Date()
        let insight = memo.insight(session)
        let timeline = SessionTimeline(rows: rows.filter { $0.session == session.id }, session: session, now: now,
                                       inLane: session.parentId == nil && session.dismissedAt == nil && Lane(st) != nil)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header(st).padding(.bottom, Space.m)
                stats(insight, timeline, now: now)
                if st == .needsInput || st == .stuck { attention(st) }
                latest(st, insight, now: now)
                if let recap = session.peek?.recap {
                    DetailCard(title: String(localized: "Session summary"), symbol: "text.quote") {
                        Text(recap).textSelection(.enabled).font(.ui(.body)).foregroundStyle(.secondary)
                    }
                }
                if !timeline.spans.isEmpty { time(timeline) }
                if insight.turns.count > 1 { turnList(insight, now: now) }
                HStack(alignment: .top, spacing: Space.l) {
                    if !insight.files.isEmpty || !insight.failures.isEmpty { work(insight) }
                    resources(insight)
                }
                .fixedSize(horizontal: false, vertical: true)
                if !session.subagents.isEmpty { subagents }
                if !session.tools.isEmpty { toolLog }
            }
            .padding(.horizontal, Space.page + Space.m).padding(.top, 34).padding(.bottom, Space.page)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Fill.canvas)
        .animation(.snappy, value: st)
        .task(id: Refresh(id: session.id, turns: session.turns.count, status: st)) {
            rows = model.sessionActivity(session.id)
        }
        .onChange(of: session.id) { openTurn = nil; openTool = nil; allTurns = false; showLog = false; showReads = false }
    }

    /// The last insight and what it was computed from; a class so filling it doesn't redraw.
    private final class Memo {
        private var key: [AnyHashable] = []
        private var value: SessionInsight?

        func insight(_ s: SessionState) -> SessionInsight {
            let k: [AnyHashable] = [s.id, s.lastEventAt, s.tools.count, s.tools.last?.id, s.tools.last?.endedAt,
                                    s.turns.count, s.turns.last?.endedAt, s.status.rawValue]
            if let value, k == key { return value }
            let v = SessionInsight(s)
            key = k
            value = v
            return v
        }
    }

    /// What re-reads the activity: another session, a new turn, a state change.
    private struct Refresh: Equatable {
        let id: String
        let turns: Int
        let status: DisplayStatus
    }

    // MARK: Header

    private func header(_ st: DisplayStatus) -> some View {
        HStack(alignment: .top, spacing: 14) {
            StatusGlyph(status: st, size: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(session.title).font(.ui(.title, .bold)).tracking(-0.2).lineLimit(2)
                    StatusPill(status: st, compact: false)
                }
                if let p = session.turns.last(where: \.byUser)?.prompt ?? session.peek?.lastPrompt {
                    Text(Self.flat(p)).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                }
                HStack(spacing: 6) {
                    HStack(spacing: 4) { AgentLogo(agent: session.agent, size: 11); Text(session.agent.displayName) }
                        .font(.ui(.footnote)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Fill.control, in: Capsule()).foregroundStyle(.secondary)
                    if let p = session.projectName {
                        meta("folder.fill", p).help(where_)
                    }
                    if session.terminal?.isWave == true { meta("terminal", "Wave") }
                    if !session.hooked { meta("exclamationmark.circle", String(localized: "No hooks")).foregroundStyle(.orange) }
                }
                HStack(spacing: 6) {
                    Button { model.jump(session.id) } label: {
                        Label(AppModel.isGone(session) ? "Resume in original terminal" : "Jump to terminal", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.action(.primary))
                    Button { model.jumper.copyContext(session) } label: { Label("Copy cwd / session", systemImage: "doc.on.doc") }
                        .buttonStyle(.action())
                    Spacer()
                    Button(role: .destructive) { model.remove(session.id) } label: { Label("Delete", systemImage: "trash") }
                        .buttonStyle(.action(.ghost, tint: .red))
                }
                .padding(.top, 2)
            }
        }
    }

    /// A prompt on one line, for the places that clamp it (its blank lines would show as empty ones).
    static func flat(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The working directory and process, for the project chip's tooltip.
    private var where_: String {
        [session.cwd.map { ($0 as NSString).abbreviatingWithTildeInPath }, session.agentPid.map { "pid \($0)" }]
            .compactMap { $0 }.joined(separator: "\n")
    }

    private func meta(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.ui(.footnote)).lineLimit(1).truncationMode(.head)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Fill.control, in: Capsule())
            .foregroundStyle(.secondary)
    }

    // MARK: Figures

    private func stats(_ insight: SessionInsight, _ timeline: SessionTimeline, now: Date) -> some View {
        let u = session.usage
        let work = u.map { $0.input + $0.output + $0.cacheWrite }
        let prompts = session.turns.filter(\.byUser).count
        let agent = timeline.rebuilt ? insight.agentTime(now: now) : timeline.total(.running)
        let first = session.turns.first?.startedAt ?? session.startedAt
        let end = session.status == .running ? now : session.lastEventAt
        return HStack(spacing: Space.l) {
            StatTile(title: String(localized: "Tokens used"), symbol: "circle.hexagongrid.fill", tint: Ramp.work.hue,
                     value: work.map(compactCount) ?? "–",
                     note: u.map { String(localized: "+\(compactCount($0.cacheRead)) cache reads") } ?? String(localized: "Not in the transcript"))
            StatTile(title: String(localized: "Turns"), symbol: "arrow.triangle.2.circlepath", tint: .secondary,
                     value: "\(session.turns.count)",
                     note: String(localized: "\(session.toolCallCount) tool calls"))
            StatTile(title: String(localized: "Agent time"), symbol: "clock.fill", tint: Ramp.run.hue,
                     value: duration(agent),
                     note: String(localized: "over \(duration(max(0, end.timeIntervalSince(first))))"))
            StatTile(title: String(localized: "Your input"), symbol: "person.fill", tint: Ramp.reply.hue,
                     value: "\(prompts + timeline.answered)",
                     note: inputNote(prompts: prompts, answered: timeline.answered, mean: timeline.meanReply))
        }
    }

    private func inputNote(prompts: Int, answered: Int, mean: TimeInterval?) -> String {
        let parts = String(localized: "\(prompts) prompts · \(answered) answers")
        guard let mean else { return parts }
        return String(localized: "\(parts) · replied in \(duration(mean)) on average")
    }

    // MARK: Needs you

    private func attention(_ st: DisplayStatus) -> some View {
        DetailCard(title: st.label, symbol: st.symbol, tint: st.tint, surface: st) {
            Text(session.needsInputMessage ?? session.stuckReason ?? "").textSelection(.enabled).font(.ui(.body))
            PermissionButtons(session: session)
        }
    }

    /// What the latest turn came to: its reply, drawn, with its facts; a turn to review says so.
    private func latest(_ st: DisplayStatus, _ insight: SessionInsight, now: Date) -> some View {
        let turn = insight.turns.last
        let review = st == .review
        let title = review ? String(localized: "Done, waiting for your review")
            : turn?.turn.endedAt == nil && st == .running ? String(localized: "In progress") : String(localized: "Latest turn")
        return DetailCard(title: title, symbol: review ? "checkmark.seal.fill" : "text.bubble",
                          tint: review ? .green : .secondary, trailing: turn.map { "#\($0.id)" },
                          surface: review ? .review : .done) {
            if let reply = session.lastReply {
                ReplyText(text: reply).id(reply)
            } else {
                Text(st == .running ? String(localized: "No reply yet") : String(localized: "No reply recorded"))
                    .font(.ui(.body)).foregroundStyle(.secondary)
            }
            if let turn {
                VStack(alignment: .leading, spacing: Space.s) {
                    if !turn.phases.isEmpty { PhaseStrip(phases: turn.phases) }
                    HStack {
                        TurnFacts(turn: turn, now: now)
                        Spacer()
                        if review {
                            Button { model.jump(session.id) } label: { Label("Go to it", systemImage: "arrow.up.forward.app") }
                                .buttonStyle(.action(.primary, tint: .green, size: .small))
                        }
                    }
                }
                .padding(.top, Space.xs)
            }
        }
    }

    // MARK: Time

    private func time(_ t: SessionTimeline) -> some View {
        let pieces = t.pieces()
        let starts = session.turns.map(\.startedAt)
        let lanes: [Lane] = [.running, .needsInput, .review, .stuck]
        let fmt = Date.FormatStyle(date: .omitted, time: .shortened)
        let range = t.spans.first.map { a in "\(a.start.formatted(fmt)) – \(t.spans.last!.end.formatted(fmt))" }
        return DetailCard(title: String(localized: "Where the time went"), symbol: "chart.bar.xaxis", trailing: range) {
            TimeBar(pieces: pieces, ticks: starts.count <= 24 ? starts : [])
            HStack(spacing: Space.xl) {
                ForEach(lanes, id: \.self) { lane in
                    let total = t.total(lane)
                    if total > 0 || lane == .running {
                        HStack(spacing: Space.s) {
                            Circle().fill(lane.status.tint).frame(width: 7, height: 7)
                            Text(lane.status.label).foregroundStyle(.secondary)
                            Text(duration(total)).font(.figure(TextSize.callout.rawValue, .medium))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.ui(.callout)).lineLimit(1)
            if t.rebuilt {
                Text("Recorded before state tracking began: only running time is known.")
                    .font(.ui(.footnote)).foregroundStyle(.tertiary)
            } else if pieces.contains(where: \.folded) {
                Text("Hatched stretches are long waits drawn shorter.").font(.ui(.footnote)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Turns

    private func turnList(_ insight: SessionInsight, now: Date) -> some View {
        let all = Array(insight.turns.reversed())
        let shown = allTurns ? all : Array(all.prefix(6))
        return DetailCard(title: String(localized: "Turns"), symbol: "arrow.triangle.2.circlepath",
                          trailing: turns(insight.turns.count)) {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(shown) { t in turnRow(t, now: now) }
            }
            if all.count > shown.count {
                Button { withAnimation(.snappy) { allTurns = true } } label: { Text("Show all \(all.count)") }
                    .buttonStyle(.action(.ghost, size: .small))
            }
        }
    }

    private func turnRow(_ t: TurnInsight, now: Date) -> some View {
        let open = openTurn == t.id
        return VStack(alignment: .leading, spacing: Space.s) {
            Button { withAnimation(.snappy) { openTurn = open ? nil : t.id } } label: {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                        Text("#\(t.id)").font(.figure(11)).foregroundStyle(.tertiary).frame(width: 26, alignment: .trailing)
                        if t.turn.byUser {
                            Text(open ? t.turn.prompt : Self.flat(t.turn.prompt)).font(.ui(.body)).lineLimit(open ? nil : 2)
                                .multilineTextAlignment(.leading)
                        } else {
                            Text(t.turn.reportsTask ? String(localized: "A background task reported back")
                                 : t.turn.prompt.isEmpty ? String(localized: "(no prompt)") : String(localized: "Sent by the agent's tools"))
                                .font(.ui(.body)).italic().foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: Space.m)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        if !t.phases.isEmpty { PhaseStrip(phases: t.phases, height: 4) }
                        HStack(spacing: Space.l) {
                            TurnFacts(turn: t, now: now)
                            if let back = t.followedAt, let end = t.turn.endedAt, back > end {
                                Fact(symbol: "arrow.uturn.left", text: String(localized: "you came back after \(duration(back.timeIntervalSince(end)))"),
                                     tint: Ramp.reply.hue)
                            }
                        }
                    }
                    .padding(.leading, 26 + Space.m)
                }
                .padding(.vertical, Space.s).padding(.horizontal, Space.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: Space.m) {
                    if let reply = t.turn.lastMessage { ReplyText(text: reply, limit: 1200).id(reply) }
                    if !t.editedFiles.isEmpty {
                        Text(t.editedFiles.joined(separator: "\n")).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if !t.complete {
                        Text("Older tool calls of this turn are no longer kept.").font(.ui(.footnote)).foregroundStyle(.tertiary)
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Fill.control.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .padding(.leading, 26 + Space.m + Space.s)
            }
        }
        .background { if open { RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Fill.control.opacity(0.4)) } }
    }

    // MARK: Files and failures

    private func work(_ insight: SessionInsight) -> some View {
        let edited = insight.files.filter { $0.edits > 0 }
        let read = insight.files.filter { $0.edits == 0 }
        return DetailCard(title: String(localized: "Files and failures"), symbol: "doc.text",
                          trailing: insight.truncated ? String(localized: "Last \(session.tools.count) calls") : nil) {
            VStack(alignment: .leading, spacing: Space.xs) {
                if edited.isEmpty && read.isEmpty { Text("No files touched").font(.ui(.callout)).foregroundStyle(.secondary) }
                ForEach(edited.prefix(8), id: \.path) { fileRow($0) }
                if edited.count > 8 { Text("\(edited.count - 8) more edited").font(.ui(.footnote)).foregroundStyle(.tertiary) }
                if !read.isEmpty {
                    Button { withAnimation(.snappy) { showReads.toggle() } } label: {
                        Label(read.count == 1 ? String(localized: "1 file only read") : String(localized: "\(read.count) files only read"),
                              systemImage: showReads ? "chevron.down" : "chevron.right")
                            .font(.ui(.footnote, .medium)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).padding(.top, Space.xs)
                    if showReads { ForEach(read.prefix(20), id: \.path) { fileRow($0) } }
                }
            }
            if !insight.failures.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Label(String(localized: "\(insight.failures.count) failed calls"), systemImage: "xmark.circle.fill")
                        .font(.ui(.footnote, .semibold)).foregroundStyle(.red)
                    ForEach(Array(insight.failures.prefix(5).enumerated()), id: \.offset) { toolRow($1, key: "f\($0)") }
                }
                .padding(.top, Space.s)
            }
        }
    }

    private func fileRow(_ f: FileTouch) -> some View {
        let name = (f.path as NSString).lastPathComponent
        let dir = (f.path as NSString).deletingLastPathComponent
        return HStack(spacing: Space.s) {
            Image(systemName: f.edits > 0 ? "pencil.circle.fill" : "eye.circle")
                .foregroundStyle(f.edits > 0 ? ToolKind.edit.tint : .secondary).font(.system(size: 12))
            Text(name).font(.ui(.callout, .medium)).lineLimit(1).layoutPriority(1)
            Text(dir).font(.ui(.footnote)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
            Spacer(minLength: Space.s)
            if f.failed > 0 { Image(systemName: "exclamationmark.circle").foregroundStyle(.red).font(.system(size: 10)) }
            Text(f.edits > 0 ? "×\(f.edits)" : "").font(.figure(11, .medium)).foregroundStyle(.secondary)
        }
        .help(f.path)
    }

    // MARK: Resources

    private func resources(_ insight: SessionInsight) -> some View {
        DetailCard(title: String(localized: "Resources"), symbol: "gauge.with.dots.needle.33percent") {
            if let u = session.usage {
                if u.context > 0 {
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Context").font(.ui(.footnote, .medium)).foregroundStyle(.secondary)
                            Spacer()
                            if let w = u.contextWindow, w > 0 {
                                Text("\(compactCount(u.context)) / \(compactCount(w)) · \(percent(Double(u.context) / Double(w)))")
                                    .font(.figure(TextSize.footnote.rawValue, .medium))
                            } else {
                                Text(compactCount(u.context)).font(.figure(TextSize.footnote.rawValue, .medium))
                            }
                        }
                        if let w = u.contextWindow, w > 0 {
                            GeometryReader { g in
                                Capsule().fill(Fill.control).overlay(alignment: .leading) {
                                    Capsule().fill(Ramp.run.hue).frame(width: g.size.width * min(1, Double(u.context) / Double(w)))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    let into = u.input + u.cacheRead + u.cacheWrite
                    HStack {
                        Text("Tokens").font(.ui(.footnote, .medium)).foregroundStyle(.secondary)
                        Spacer()
                        if into > 0 {
                            Text("Cache hit \(percent(Double(u.cacheRead) / Double(into)))").font(.figure(TextSize.footnote.rawValue, .medium))
                        }
                    }
                    ShareBar(parts: [
                        .init(id: "out", label: String(localized: "Output"), value: Double(u.output), tint: Ramp.work.hue, note: compactCount(u.output)),
                        .init(id: "in", label: String(localized: "Input"), value: Double(u.input), tint: .primary.opacity(0.55), note: compactCount(u.input)),
                        .init(id: "cw", label: String(localized: "Cache write"), value: Double(u.cacheWrite), tint: .primary.opacity(0.32), note: compactCount(u.cacheWrite)),
                        .init(id: "cr", label: String(localized: "Cache read"), value: Double(u.cacheRead), tint: .primary.opacity(0.14), note: compactCount(u.cacheRead)),
                    ])
                }
            }
            if !insight.kinds.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Tool mix").font(.ui(.footnote, .medium)).foregroundStyle(.secondary)
                    ShareBar(parts: insight.kinds.map { .init(id: $0.kind.rawValue, label: $0.kind.label, value: Double($0.count), tint: $0.kind.tint, note: "\($0.count)") })
                }
            }
            if session.usage == nil && insight.kinds.isEmpty {
                Text("None yet").font(.ui(.callout)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Subagents and the raw log

    private var subagents: some View {
        DetailCard(title: String(localized: "Subagents"), symbol: "person.2") {
            ForEach(session.subagents, id: \.id) { a in
                HStack { Text(a.type ?? "agent"); Spacer(); Text(relative(a.startedAt)).foregroundStyle(.secondary) }
                    .font(.ui(.callout))
            }
        }
    }

    private var toolLog: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Button { withAnimation(.snappy) { showLog.toggle() } } label: {
                HStack {
                    Label("Tool calls", systemImage: "wrench.and.screwdriver").font(.ui(.callout, .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Last \(session.tools.count)").font(.ui(.footnote)).foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showLog ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showLog {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    ForEach(Array(session.tools.reversed().enumerated()), id: \.offset) { toolRow($1, key: "l\($0)") }
                }
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(.done, radius: Radius.group)
    }

    private func toolRow(_ t: ToolCall, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { openTool = openTool == key ? nil : key } } label: {
                HStack {
                    ToolLine(tool: t)
                    Spacer()
                    if t.subagentId != nil { Text("subagent").font(.system(size: 10)).foregroundStyle(.purple) }
                    Text(t.startedAt, style: .time).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(openTool == key ? 90 : 0))
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if openTool == key {
                CodeBlock(title: String(localized: "Input"), text: t.input)
                if let o = t.output { CodeBlock(title: String(localized: "Output"), text: o) }
            }
        }
    }
}
