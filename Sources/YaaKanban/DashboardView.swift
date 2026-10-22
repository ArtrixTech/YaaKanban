import SwiftUI
import YaaCore

extension Period {
    var label: String { switch self { case .day: "日"; case .week: "周"; case .month: "月" } }
    /// "this" one, said of the current period.
    var current: String { switch self { case .day: "今天"; case .week: "本周"; case .month: "本月" } }
    /// The one before, so far (while the current one runs) or in full.
    func previous(soFar: Bool) -> String {
        switch self {
        case .day: soFar ? "昨天同期" : "前一天"
        case .week: soFar ? "上周同期" : "前一周"
        case .month: soFar ? "上月同期" : "前一月"
        }
    }

    func rangeLabel(_ p: Periods) -> String {
        let md = Date.FormatStyle().month().day()
        let d = switch self {
        case .day: p.range.start.formatted(md.weekday(.abbreviated))
        case .week: "\(p.range.start.formatted(md)) – \(p.range.end.addingTimeInterval(-1).formatted(md))"
        case .month: p.range.start.formatted(.dateTime.year().month())
        }
        return p.inProgress ? "\(current) · \(d)" : d
    }
}

/// Main-window home: how the user's parallel sessions went over a day, week or month, against
/// the one before. The headline figures and one chart first, the breakdowns under them.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    /// Periods back from the current one; the current one follows the clock.
    @State private var back = 0
    @State private var period: Period

    init(period: Period = .day) { _period = State(initialValue: period) }

    var body: some View {
        // Redraws every 30 s for the now line, and on each recorded row.
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let _ = model.activityVersion
            let p = Periods(period, back: back, now: ctx.date)
            let r = model.report(p.range, edges: p.edges)
            // The one before over the same stretch, for the figures; in full, for the chart.
            let prev = model.report(p.previousSoFar)
            let prevFull = model.report(p.previous, edges: p.previousEdges)
            let vs = period.previous(soFar: p.inProgress)
            // Nothing recorded then: no comparison, rather than "up by all of it".
            let base = prev.lanes.isEmpty && prev.turns == 0 ? nil : prev
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(p)
                    Text(summary(r, base, p, vs: vs)).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                    if let until = r.rebuiltUntil { rebuiltNote(r, until) }
                    Headline(r: r, prev: base, vs: vs)
                    Highlights(period: period, report: r)
                    ActivityChart(period: period, report: r, previous: prevFull, now: ctx.date)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 12) {
                            AgentMix(report: r)
                            ProjectBreakdown(report: r)
                        }
                        details(r, base, vs: vs, now: ctx.date)
                    }
                    SessionLanes(period: period, report: r, now: ctx.date)
                }
                .padding(20)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }
    private func header(_ p: Periods) -> some View {
        HStack(spacing: 8) {
            Text("概览").font(.system(size: 20, weight: .bold))
            Spacer()
            IconButton(symbol: "chevron.left", help: period.previous(soFar: false)) { back += 1 }
            Text(period.rangeLabel(p)).font(.system(size: 12.5, weight: .medium)).monospacedDigit().frame(minWidth: 130)
            IconButton(symbol: "chevron.right", help: "后一\(period == .day ? "天" : period == .week ? "周" : "月")") {
                back = max(0, back - 1)
            }
            .disabled(back == 0).opacity(back == 0 ? 0.3 : 1)
            if back > 0 { Button(period.current) { back = 0 }.controlSize(.small) }
            Picker("", selection: Binding(get: { period }, set: { period = $0; back = 0 })) {
                ForEach(Period.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    private func rebuiltNote(_ r: ActivityReport, _ until: Date) -> some View {
        Label(r.allRebuilt ? "这段时间在开始记录之前，只从会话历史还原了运行时段和轮数；等待、回复、离开和 token 没有数据。"
              : "\(until.formatted(.dateTime.month().day().hour().minute())) 之前从会话历史还原，只有运行时段和轮数。",
              systemImage: "clock.arrow.circlepath")
            .font(.system(size: 11.5)).foregroundStyle(.tertiary)
    }

    /// One plain sentence on how the period went, against the one before.
    private func summary(_ r: ActivityReport, _ prev: ActivityReport?, _ p: Periods, vs: String) -> String {
        let subject = p.inProgress ? period.current : period == .day ? "这一天" : period == .week ? "这一周" : "这个月"
        guard !r.lanes.isEmpty || r.turns > 0 else { return "\(subject)没有记录到 agent 活动。" }
        var s = "\(subject)你带着 \(r.lanes.count) 个会话忙了 \(duration(r.activeTime))，agent 一共干了 \(duration(r.agentTime))"
        if let x = r.leverage, x >= 0.05 { s += String(format: "，相当于 %.1f 个你", x) }
        if let prev, prev.agentTime >= 60 {
            let d = r.agentTime - prev.agentTime
            s += abs(d) < 60 ? "，和\(vs)差不多" : "，比\(vs)\(d > 0 ? "多" : "少") \(duration(abs(d)))"
        }
        if r.agentTimeAway >= 60 { s += "；你不在时它们又干了 \(duration(r.agentTimeAway))" }
        if !r.allRebuilt {
            if let m = r.replyMedian { s += "；agent 找你时，你一般 \(duration(m)) 内回复" }
            if r.bottleneck >= 60 { s += "，有 \(duration(r.bottleneck)) 所有 agent 都停着等你" }
        }
        return s + "；完成 \(r.turns) 轮。"
    }

    private func details(_ r: ActivityReport, _ prev: ActivityReport?, vs: String, now: Date) -> some View {
        let backlog = model.backlog
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            Tile(title: "平均同时在跑", symbol: "square.stack.3d.up", value: String(format: "%.1f 个", r.parallelAverage),
                 caption: "有 agent 在跑时 · 最多 \(r.parallelPeak) 个",
                 delta: Delta(r.parallelAverage, prev?.parallelAverage, better: .up, vs: vs) { String(format: "%.1f", $0) })
            Tile(title: "全部停工", symbol: "pause.circle", value: r.allRebuilt ? "–" : duration(r.bottleneck),
                 caption: "所有 agent 都在等你、没有一个在跑",
                 delta: comparesWaits(r, prev) ? Delta(r.bottleneck, prev?.bottleneck, better: .down, vs: vs, fmt: duration) : nil)
            Tile(title: "Agent 利用率", symbol: "gauge.with.dots.needle.67percent",
                 value: r.utilization.map(percent) ?? "–", caption: "在跑 ÷（在跑 + 等你）",
                 delta: comparesWaits(r, prev) ? Delta(r.utilization, prev?.utilization, better: .up, vs: vs, fmt: percent) : nil)
            Tile(title: "吞吐", symbol: "bolt", value: r.perActiveHour(r.turns).map { String(format: "%.1f 轮/时", $0) } ?? "–",
                 caption: "\(r.toolCalls) 次工具 · \(compactCount(r.tokens)) token（不含缓存读）")
            Tile(title: "当前积压", symbol: "tray.full", value: "\(backlog.count) 个",
                 caption: backlog.oldest.map { "最久已等 \(relative($0, now: now))" } ?? "没有在等你的会话")
            Tile(title: "切换", symbol: "arrow.left.arrow.right", value: "\(r.switches) 次",
                 caption: r.perActiveHour(r.switches).map { String(format: "每活跃小时 %.1f 次", $0) } ?? "点卡片或通知跳转")
            if let p = r.replyByProject.first, r.replyByProject.count > 1 {
                Tile(title: "回复最慢的项目", symbol: "tortoise", value: duration(p.median), caption: "\(p.project) · \(p.count) 次")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Waits, replies and absences exist only where recorded live: compare them only when neither
/// period was partly rebuilt, or the rebuilt side reads as "no waiting".
private func comparesWaits(_ a: ActivityReport, _ b: ActivityReport?) -> Bool {
    a.rebuiltUntil == nil && b?.rebuiltUntil == nil
}

func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

/// "1分12秒", "3分", "2.4时".
func duration(_ t: TimeInterval) -> String {
    let s = Int(t.rounded())
    if s < 60 { return "\(s)秒" }
    if s < 600 { return s % 60 == 0 ? "\(s / 60)分" : "\(s / 60)分\(s % 60)秒" }
    if s < 3600 { return "\(s / 60)分" }
    return String(format: "%.1f时", t / 3600)
}

extension Lane {
    var status: DisplayStatus {
        switch self {
        case .running: .running
        case .needsInput: .needsInput
        case .stuck: .stuck
        case .review: .review
        }
    }
}

/// Chart colors: running, and every way of waiting on the user, as one.
private enum Ink {
    static let running = DisplayStatus.running.tint
    static let waiting = DisplayStatus.needsInput.tint
    static let away = Color.primary.opacity(0.07)
}

/// A change against the period before: "↑ 1.2时 vs 昨天同期", green when it went the good way.
struct Delta {
    enum Better { case up, down }
    var text: String
    var color: Color

    init?(_ a: Double?, _ b: Double?, better: Better, vs: String, fmt: (Double) -> String) {
        guard let a, let b else { return nil }
        let d = a - b
        let shown = fmt(abs(d))
        if shown == fmt(0) {
            text = "与\(vs)持平"; color = .secondary
        } else {
            text = "\(d > 0 ? "↑" : "↓") \(shown) vs \(vs)"
            color = (d > 0) == (better == .up) ? .green : .red
        }
    }
}

/// The four figures at the top, each against the period before.
private struct Headline: View {
    let r: ActivityReport
    let prev: ActivityReport?
    let vs: String

    var body: some View {
        let waits = comparesWaits(r, prev)
        HStack(spacing: 12) {
            Figure(title: "Agent 总工时", value: duration(r.agentTime),
                   note: r.agentTimeAway >= 60 ? "其中你不在时 \(duration(r.agentTimeAway))" : "所有 agent 在跑的时间相加",
                   delta: Delta(r.agentTime, prev?.agentTime, better: .up, vs: vs, fmt: duration))
            Figure(title: "杠杆", value: r.leverage.map { String(format: "%.1f×", $0) } ?? "–",
                   note: "你在场的每小时，agent 干了几小时",
                   delta: waits ? Delta(r.leverage, prev?.leverage, better: .up, vs: vs) { String(format: "%.1f×", $0) } : nil)
            Figure(title: "回复速度", value: r.replyMedian.map(duration) ?? "–",
                   note: r.replyP90.map { "agent 等你回复的中位 · P90 \(duration($0))" } ?? "agent 等你回复要多久",
                   delta: waits ? Delta(r.replyMedian, prev?.replyMedian, better: .down, vs: vs, fmt: duration) : nil)
            Figure(title: "完成轮数", value: "\(r.turns)",
                   note: r.perActiveHour(r.turns).map { String(format: "每活跃小时 %.1f 轮", $0) } ?? "agent 回完一次算一轮",
                   delta: Delta(Double(r.turns), prev.map { Double($0.turns) }, better: .up, vs: vs) { "\(Int($0))" })
        }
    }
}

private struct Figure: View {
    let title: String
    let value: String
    let note: String
    let delta: Delta?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(delta?.text ?? " ").font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(delta?.color ?? .clear).lineLimit(1)
            Text(note).font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(.done, radius: 14)
    }
}

/// Four facts to read the period by: the hardest worker, the longest run, the busiest slice,
/// and what got done while the user was away.
private struct Highlights: View {
    @Environment(AppModel.self) private var model
    let period: Period
    let report: ActivityReport

    var body: some View {
        let r = report
        let mvp = r.sessionTotals.filter { $0.running > 0 }.max { $0.running < $1.running }
        let long = r.longestRun
        HStack(spacing: 12) {
            Fact(symbol: "trophy", title: "最卖力", agent: mvp.flatMap { agent($0.session) },
                 value: mvp.map { title($0.session) } ?? "–",
                 caption: mvp.map { "跑了 \(duration($0.running)) · \(r.turnsBySession[$0.session] ?? 0) 轮" } ?? "还没有 agent 跑过")
            Fact(symbol: "flame", title: "最长连跑", agent: long.flatMap { agent($0.session) },
                 value: long.map { duration($0.duration) } ?? "–",
                 caption: long.map { title($0.session) } ?? "一口气不停地跑")
            let peak = busiest
            Fact(symbol: "chart.bar.fill", title: "最忙的时候", value: peak?.value ?? "–", caption: peak?.when ?? "还没有 agent 跑过")
            Fact(symbol: "moon.zzz", title: "你不在时", value: duration(r.agentTimeAway),
                 caption: r.allRebuilt ? "这段没有离开的记录" : r.away.isEmpty ? "你一直都在"
                    : r.agentTimeAway >= 60 ? "agent 自己接着干的工时" : "你一走它们也停了")
        }
    }

    private func agent(_ id: String) -> AgentKind? {
        model.sessions[id]?.agent ?? id.split(separator: ":").first.flatMap { AgentKind(rawValue: String($0)) }
    }
    private func title(_ id: String) -> String { model.sessions[id]?.title ?? "已删除的会话" }

    /// The slice with the most running: sessions at once, or agent hours on a month's day.
    private var busiest: (value: String, when: String)? {
        let b = report.parallelBuckets, e = report.bucketEdges
        guard let i = b.indices.max(by: { b[$0] < b[$1] }), b[i] > 0, e.indices.contains(i + 1) else { return nil }
        let value = period == .month ? duration(b[i] * e[i + 1].timeIntervalSince(e[i])) + " 工时"
            : String(format: "%.1f 个同时在跑", b[i])
        return (value, slotLabel(period, e[i], e[i + 1]))
    }
}

private struct Fact: View {
    let symbol: String
    let title: String
    var agent: AgentKind?
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                if let agent { AgentLogo(agent: agent, size: 12) }
                Text(value).font(.system(size: 15, weight: .bold).monospacedDigit()).lineLimit(1).truncationMode(.tail)
            }
            Text(caption).font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(.done, radius: 12)
    }
}

/// Which agents did the work: running time per agent kind, as one bar and a row each.
private struct AgentMix: View {
    @Environment(AppModel.self) private var model
    let report: ActivityReport

    var body: some View {
        let rows = kinds
        let total = rows.reduce(0) { $0 + $1.time }
        VStack(alignment: .leading, spacing: 9) {
            Text("军团构成").font(.system(size: 12, weight: .semibold))
            if total < 1 {
                Text("没有 agent 在跑。").font(.system(size: 12)).foregroundStyle(.tertiary)
            } else {
                GeometryReader { g in
                    HStack(spacing: 1) {
                        ForEach(rows, id: \.kind) { k in
                            RoundedRectangle(cornerRadius: 2).fill(Self.tint(k.kind)).frame(width: max(0, g.size.width * k.time / total - 1))
                        }
                    }
                }
                .frame(height: 8)
                ForEach(rows, id: \.kind) { k in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Self.tint(k.kind)).frame(width: 4, height: 12)
                        AgentLogo(agent: k.kind, size: 11)
                        Text(k.kind.displayName).font(.system(size: 11.5, weight: .medium))
                        Spacer()
                        Text("\(duration(k.time)) · \(percent(k.time / total)) · \(k.sessions) 个会话")
                            .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(.done, radius: 14)
    }

    static func tint(_ k: AgentKind) -> Color {
        switch k {
        case .claudeCode: .orange
        case .codex: .teal
        case .cursor: .purple
        case .opencode: .green
        case .pi: .pink
        }
    }

    private var kinds: [(kind: AgentKind, time: TimeInterval, sessions: Int)] {
        var by: [AgentKind: (TimeInterval, Int)] = [:]
        for t in report.sessionTotals where t.running > 0 {
            guard let k = model.sessions[t.session]?.agent
                    ?? t.session.split(separator: ":").first.flatMap({ AgentKind(rawValue: String($0)) }) else { continue }
            by[k, default: (0, 0)].0 += t.running
            by[k, default: (0, 0)].1 += 1
        }
        return by.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
    }
}

/// Axis labels along a period: every 3 hours of a day (on the clock), under each day of a week,
/// under every few days of a month. Each label sits at the middle of its span.
func axisTicks(_ period: Period, _ range: DateInterval, calendar cal: Calendar = .current) -> [(span: DateInterval, label: String)] {
    func day(_ i: Int) -> DateInterval? {
        cal.date(byAdding: .day, value: i, to: range.start).flatMap { cal.dateInterval(of: .day, for: $0) }
    }
    switch period {
    case .day:
        return stride(from: 0, through: 24, by: 3).compactMap { h in
            let d = h == 24 ? range.end : cal.date(bySettingHour: h, minute: 0, second: 0, of: range.start)
            return d.map { (DateInterval(start: $0, duration: 0), "\(h)") }
        }
    case .week:
        return (0..<7).compactMap { i in day(i).map { ($0, $0.start.formatted(.dateTime.weekday(.abbreviated))) } }
    case .month:
        let days = cal.range(of: .day, in: .month, for: range.start)?.count ?? 30
        return [1, 5, 10, 15, 20, 25, days].compactMap { n in day(n - 1).map { ($0, "\(n)日") } }
    }
}

/// Where `d` falls along `edges`, as a fraction of the slots (each slot drawn equally wide).
func slotFraction(_ d: Date, _ edges: [Date]) -> Double {
    guard let first = edges.first, let last = edges.last, edges.count > 1 else { return 0 }
    if d <= first { return 0 }
    if d >= last { return 1 }
    let k = max(0, (edges.firstIndex { $0 > d } ?? edges.count) - 1)
    let w = edges[k + 1].timeIntervalSince(edges[k])
    return (Double(k) + (w > 0 ? d.timeIntervalSince(edges[k]) / w : 0)) / Double(edges.count - 1)
}

func midpoint(_ i: DateInterval) -> Date { i.start.addingTimeInterval(i.duration / 2) }

/// One chart slice in words: "14:00–14:30", "周二 15:00–18:00", "10月3日".
func slotLabel(_ period: Period, _ a: Date, _ b: Date) -> String {
    let hm = Date.FormatStyle.dateTime.hour().minute()
    return switch period {
    case .month: a.formatted(.dateTime.month().day())
    case .week: "\(a.formatted(hm.weekday(.abbreviated)))–\(b.formatted(hm))"
    case .day: "\(a.formatted(hm))–\(b.formatted(hm))"
    }
}

/// The main chart: per slice of the period, how many sessions ran and how many waited on you,
/// with the period before as a line.
private struct ActivityChart: View {
    let period: Period
    let report: ActivityReport
    let previous: ActivityReport
    let now: Date
    @State private var hover: Int?
    static let gutter: CGFloat = 26

    /// Per day in a month (hours of session time), otherwise sessions at once.
    private var scale: Double { period == .month ? 24 : 1 }
    private func fx(_ d: Date) -> Double { slotFraction(d, report.bucketEdges) }
    private var unit: String { period == .month ? "时" : "个" }
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v * scale) + unit }

    var body: some View {
        let run = report.parallelBuckets, wait = report.waitingBuckets, ghost = previous.parallelBuckets
        let peak = max((0..<run.count).map { run[$0] + (wait.indices.contains($0) ? wait[$0] : 0) }.max() ?? 0, ghost.max() ?? 0)
        // A whole number on the axis, in the shown unit, and an even one past 2 so its half is too.
        let whole = max(1, (peak * scale).rounded(.up))
        let top = (whole > 2 ? (whole / 2).rounded(.up) * 2 : whole) / scale
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(period == .month ? "每天的会话时长" : "同时在跑 / 在等你的会话数")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let i = hover, i < run.count { readout(i, run, wait, ghost) } else { legend }
            }
            .frame(height: 16)
            GeometryReader { g in
                let plot = CGRect(x: Self.gutter, y: 0, width: g.size.width - Self.gutter, height: g.size.height)
                canvas(run, wait, ghost, top: top, plot: plot)
                    .onContinuousHover { phase in
                        if case .active(let p) = phase, p.x >= plot.minX, !run.isEmpty {
                            hover = min(run.count - 1, Int((p.x - plot.minX) / plot.width * CGFloat(run.count)))
                        } else { hover = nil }
                    }
            }
            .frame(height: 170)
            GeometryReader { g in
                let w = g.size.width - Self.gutter
                ForEach(Array(axisTicks(period, report.range).enumerated()), id: \.offset) { _, t in
                    Text(t.label).font(.system(size: 10)).monospacedDigit().foregroundStyle(.tertiary).fixedSize()
                        .position(x: Self.gutter + w * fx(midpoint(t.span)), y: 6)
                }
            }
            .frame(height: 12)
        }
        .padding(14)
        .card(.done, radius: 14)
    }
    private func canvas(_ run: [Double], _ wait: [Double], _ ghost: [Double], top: Double, plot: CGRect) -> some View {
        let range = report.range, away = report.away, hover = hover, edges = report.bucketEdges
        let gridLabel = { (v: Double) in String(format: (v * scale).rounded() == v * scale ? "%.0f" : "%.1f", v * scale) }
        return Canvas { ctx, _ in
            func y(_ v: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(min(v, top) / top) }
            func x(_ d: Date) -> CGFloat { plot.minX + plot.width * CGFloat(slotFraction(d, edges)) }
            for a in away {
                ctx.fill(Path(CGRect(x: x(a.start), y: plot.minY, width: x(a.end) - x(a.start), height: plot.height)), with: .color(Ink.away))
            }
            for v in [0, top / 2, top] {
                ctx.fill(Path(CGRect(x: plot.minX, y: y(v) - 0.25, width: plot.width, height: 0.5)), with: .color(.primary.opacity(0.12)))
                ctx.draw(Text(gridLabel(v)).font(.system(size: 9.5)).foregroundStyle(.tertiary),
                         at: CGPoint(x: plot.minX - 4, y: min(max(y(v), 6), plot.maxY - 6)), anchor: .trailing)
            }
            let n = max(run.count, 1)
            let bw = plot.width / CGFloat(n)
            let gap = min(2, bw * 0.2)
            for i in 0..<run.count {
                let x0 = plot.minX + CGFloat(i) * bw + gap / 2
                let w = waitAt(wait, i)
                if hover == i {
                    ctx.fill(Path(CGRect(x: x0 - gap / 2, y: plot.minY, width: bw, height: plot.height)), with: .color(.primary.opacity(0.06)))
                }
                if run[i] > 0 {
                    ctx.fill(Path(roundedRect: CGRect(x: x0, y: y(run[i]), width: bw - gap, height: plot.maxY - y(run[i])), cornerRadius: 1.5),
                             with: .color(Ink.running.opacity(0.85)))
                }
                if w > 0 {
                    ctx.fill(Path(roundedRect: CGRect(x: x0, y: y(run[i] + w), width: bw - gap, height: y(run[i]) - y(run[i] + w)), cornerRadius: 1.5),
                             with: .color(Ink.waiting.opacity(0.85)))
                }
            }
            // The period before, running only, as a step line over the same slices.
            if ghost.contains(where: { $0 > 0 }) {
                var line = Path()
                for (i, v) in ghost.prefix(n).enumerated() {
                    let a = CGPoint(x: plot.minX + CGFloat(i) * bw, y: y(v)), b = CGPoint(x: a.x + bw, y: y(v))
                    i == 0 ? line.move(to: a) : line.addLine(to: a)
                    line.addLine(to: b)
                }
                ctx.stroke(line, with: .color(.primary.opacity(0.45)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round, dash: [3, 2]))
            }
            if range.contains(now) {
                ctx.fill(Path(CGRect(x: x(now) - 0.5, y: plot.minY, width: 1, height: plot.height)), with: .color(.primary.opacity(0.4)))
            }
        }
    }

    private func waitAt(_ wait: [Double], _ i: Int) -> Double { wait.indices.contains(i) ? wait[i] : 0 }

    private func readout(_ i: Int, _ run: [Double], _ wait: [Double], _ ghost: [Double]) -> some View {
        let e = report.bucketEdges
        let a = e.indices.contains(i) ? e[i] : report.range.start, b = e.indices.contains(i + 1) ? e[i + 1] : report.range.end
        var parts = [slotLabel(period, a, b), "在跑 \(fmt(run[i]))", "等你 \(fmt(waitAt(wait, i)))"]
        if ghost.indices.contains(i) { parts.append("上期在跑 \(fmt(ghost[i]))") }
        return Text(parts.joined(separator: "  ·  ")).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            swatch(Ink.running, "在跑")
            swatch(Ink.waiting, "等你处理")
            swatch(Ink.away, "你不在")
            HStack(spacing: 4) {
                Path { p in p.move(to: CGPoint(x: 0, y: 3)); p.addLine(to: CGPoint(x: 12, y: 3)) }
                    .stroke(Color.primary.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])).frame(width: 12, height: 6)
                Text("上期在跑")
            }
        }
        .font(.system(size: 10.5)).foregroundStyle(.secondary)
    }
}

private func swatch(_ c: Color, _ name: String) -> some View {
    HStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 6)
        Text(name)
    }
}
/// Where the time went: per project, running and waiting on the user, busiest first.
private struct ProjectBreakdown: View {
    @Environment(AppModel.self) private var model
    let report: ActivityReport
    static let shown = 7

    var body: some View {
        let rows = projects
        let top = rows.first.map { $0.running + $0.waiting } ?? 0
        VStack(alignment: .leading, spacing: 9) {
            Text("按项目").font(.system(size: 12, weight: .semibold))
            if rows.isEmpty {
                Text("没有会话在跑或等你。").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            ForEach(rows.prefix(Self.shown), id: \.name) { p in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(p.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                        Spacer()
                        Text("在跑 \(duration(p.running)) · 等你 \(duration(p.waiting))")
                            .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { g in
                        let unit = top > 0 ? g.size.width / top : 0
                        HStack(spacing: 1) {
                            RoundedRectangle(cornerRadius: 2).fill(Ink.running.opacity(0.85)).frame(width: max(0, p.running * unit))
                            RoundedRectangle(cornerRadius: 2).fill(Ink.waiting.opacity(0.85)).frame(width: max(0, p.waiting * unit))
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 6)
                }
            }
            if rows.count > Self.shown {
                Text("另有 \(rows.count - Self.shown) 个项目").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(.done, radius: 14)
    }

    private var projects: [(name: String, running: TimeInterval, waiting: TimeInterval)] {
        var by: [String: (TimeInterval, TimeInterval)] = [:]
        for t in report.sessionTotals {
            let s = model.sessions[t.session]
            let name = s == nil ? "已删除的会话" : s?.projectName ?? "其他"
            by[name, default: (0, 0)].0 += t.running
            by[name, default: (0, 0)].1 += t.waiting
        }
        return by.map { ($0.key, $0.value.0, $0.value.1) }.filter { $0.1 + $0.2 >= 1 }
            .sorted { $0.1 + $0.2 > $1.1 + $1.2 }
    }
}

private struct Tile: View {
    let title: String
    let symbol: String
    let value: String
    let caption: String
    var delta: Delta?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 18, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                if let delta { Text(delta.text).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(delta.color).lineLimit(1) }
            }
            Text(caption).font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .card(.done, radius: 12)
    }
}
/// Per-session swimlanes, folded by default; open, the busiest few, then all on request.
private struct SessionLanes: View {
    @Environment(AppModel.self) private var model
    let period: Period
    let report: ActivityReport
    let now: Date
    @State private var open = false
    @State private var all = false
    static let label: CGFloat = 170
    static let few = 10

    var body: some View {
        let totals = report.sessionTotals
        let segments = Dictionary(report.lanes.map { ($0.session, $0.segments) }, uniquingKeysWith: { a, _ in a })
        let rows = all ? totals : Array(totals.prefix(Self.few))
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text("会话明细").font(.system(size: 12, weight: .semibold))
                    Text("\(totals.count) 个会话").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if open { lanesLegend }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open, !rows.isEmpty {
                HStack(spacing: 8) {
                    Color.clear.frame(width: Self.label, height: 1)
                    GeometryReader { g in
                        ForEach(Array(axisTicks(period, report.range).enumerated()), id: \.offset) { _, t in
                            Text(t.label).font(.system(size: 9.5)).monospacedDigit().foregroundStyle(.tertiary).fixedSize()
                                .position(x: g.size.width * midpoint(t.span).timeIntervalSince(report.range.start) / report.range.duration, y: 6)
                        }
                    }
                    .frame(height: 12)
                }
                ForEach(rows, id: \.session) { t in
                    HStack(spacing: 8) {
                        rowLabel(t.session)
                        Track(range: report.range, now: now, segments: segments[t.session] ?? [], away: report.away)
                            .frame(height: 10)
                    }
                    .frame(height: 14)
                }
                if totals.count > Self.few {
                    Button(all ? "只看最忙的 \(Self.few) 个" : "显示全部 \(totals.count) 个") { all.toggle() }
                        .buttonStyle(.link).font(.system(size: 11))
                }
            }
        }
        .padding(14)
        .card(.done, radius: 14)
    }

    private func rowLabel(_ id: String) -> some View {
        let s = model.sessions[id]
        return Button {
            if s != nil { model.selection = id }
        } label: {
            HStack(spacing: 5) {
                if let s { AgentLogo(agent: s.agent, size: 10) }
                Text(s?.title ?? "已删除的会话").font(.system(size: 11)).lineLimit(1)
                    .foregroundStyle(s == nil ? .tertiary : .primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: Self.label)
        .help(s.map { "\($0.projectName ?? "") · \($0.title)" } ?? "")
    }

    private var lanesLegend: some View {
        HStack(spacing: 10) {
            ForEach(Lane.allCases, id: \.self) { swatch($0.status.tint, $0.status.label) }
            swatch(Color.primary.opacity(0.12), "离开")
        }
        .font(.system(size: 10.5)).foregroundStyle(.secondary)
    }
}

private struct Track: View {
    let range: DateInterval
    let now: Date
    let segments: [ActivityReport.Segment]
    let away: [DateInterval]

    var body: some View {
        Canvas { ctx, size in
            let span = range.duration
            func x(_ d: Date) -> CGFloat { size.width * min(1, max(0, d.timeIntervalSince(range.start) / span)) }
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3), with: .color(.primary.opacity(0.04)))
            for a in away {
                ctx.fill(Path(CGRect(x: x(a.start), y: 0, width: x(a.end) - x(a.start), height: size.height)),
                         with: .color(.primary.opacity(0.10)))
            }
            for s in segments {
                let w = max(1.5, x(s.end) - x(s.start))
                ctx.fill(Path(roundedRect: CGRect(x: x(s.start), y: 1, width: w, height: size.height - 2), cornerRadius: 2),
                         with: .color(s.lane.status.tint.opacity(0.85)))
            }
            if range.contains(now) {
                ctx.fill(Path(CGRect(x: x(now) - 0.5, y: 0, width: 1, height: size.height)), with: .color(.primary.opacity(0.5)))
            }
        }
    }
}
/// A compact row of figures for a range: agent hours, leverage, reply speed, turns. The menu
/// popover shows today; the floating panel, the last few minutes (`RecentFigures`).
struct QuickFigures: View {
    @Environment(AppModel.self) private var model
    let range: DateInterval
    /// Leading label naming the range, where the context does not.
    var title: String?
    var help: String

    var body: some View {
        let _ = model.activityVersion
        let r = model.report(range, buckets: 1)
        HStack(spacing: 0) {
            if let title {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .fixedSize().padding(.leading, 9)
            }
            figure(duration(r.agentTime), "agent 工时")
            figure(r.leverage.map { String(format: "%.1f×", $0) } ?? "–", "杠杆")
            figure(r.replyMedian.map(duration) ?? "–", "回复")
            figure("\(r.turns)", "轮")
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.05)))
        .help(help)
    }

    private func figure(_ value: String, _ name: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 13.5, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Today so far, for the menu popover.
struct TodayFigures: View {
    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        QuickFigures(range: DateInterval(start: today, end: Calendar.current.date(byAdding: .day, value: 1, to: today)!),
                     help: "今天，点击打开主界面「概览」")
    }
}

/// The last `recentMinutes`, for the floating panel. The window moves by whole minutes so the
/// report cache holds between redraws.
struct RecentFigures: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let minutes = model.settings.recentMinutes
            let end = Calendar.current.dateInterval(of: .minute, for: ctx.date)!.end
            QuickFigures(range: DateInterval(start: end.addingTimeInterval(-minutes * 60), end: end),
                         title: "近\(minutes < 60 ? "\(Int(minutes))分" : "\(Int(minutes / 60))时")", help: "最近 \(SettingsView.duration(minutes))，时长可在设置里调")
        }
    }
}
