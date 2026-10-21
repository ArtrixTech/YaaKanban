import SwiftUI
import YaaCore

/// Main-window home: how the user's parallel sessions went over a day (or seven) — swimlanes,
/// then the figures under them, then this week against the last.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    /// Days back from today; today follows the clock past midnight.
    @State private var back = 0
    @State private var week = false

    var body: some View {
        // Redraws every 30 s for the now line, and on each recorded row.
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let _ = model.activityVersion
            let now = ctx.date
            let day = Calendar.current.date(byAdding: .day, value: -back, to: Calendar.current.startOfDay(for: now))!
            let r = model.report(range(day))
            // Whole minutes, so the cached reports serve redraws within one.
            let minute = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.up) * 60)
            let thisWeek = model.report(Self.days(7, endingAt: minute))
            let lastWeek = model.report(Self.days(7, endingAt: minute.addingTimeInterval(-7 * 86400)))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(day)
                    Text(summary(r)).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                    if let until = r.rebuiltUntil {
                        Label(r.allRebuilt ? "这段时间在开始记录之前，只从会话历史还原了运行时段和轮数；等待、回复、离开和 token 没有数据。"
                              : "\(until.formatted(.dateTime.month().day().hour().minute())) 之前从会话历史还原，只有运行时段和轮数。",
                              systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 11.5)).foregroundStyle(.tertiary)
                    }
                    Swimlanes(report: r, now: now)
                    tiles(r, now: now)
                    WeekComparison(this: thisWeek, last: lastWeek)
                }
                .padding(20)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func range(_ day: Date) -> DateInterval {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: day)!
        return DateInterval(start: week ? cal.date(byAdding: .day, value: -6, to: day)! : day, end: end)
    }

    static func days(_ n: Int, endingAt end: Date) -> DateInterval {
        DateInterval(start: end.addingTimeInterval(-Double(n) * 86400), end: end)
    }

    private var isToday: Bool { back == 0 }

    private func header(_ day: Date) -> some View {
        HStack(spacing: 8) {
            Text("概览").font(.system(size: 20, weight: .bold))
            Spacer()
            IconButton(symbol: "chevron.left", help: "前一天") { shift(-1) }
            Text(dayLabel(day)).font(.system(size: 12.5, weight: .medium)).monospacedDigit().frame(minWidth: 110)
            IconButton(symbol: "chevron.right", help: "后一天") { shift(1) }.disabled(isToday).opacity(isToday ? 0.3 : 1)
            if !isToday { Button("今天") { back = 0 }.controlSize(.small) }
            Picker("", selection: $week) {
                Text("日").tag(false)
                Text("7 天").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    private func shift(_ n: Int) { back = max(0, back - n) }

    private func dayLabel(_ day: Date) -> String {
        let f = Date.FormatStyle().month().day().weekday(.abbreviated)
        guard week else { return isToday ? "今天 · \(day.formatted(f))" : day.formatted(f) }
        return "\(range(day).start.formatted(.dateTime.month().day())) – \(day.formatted(.dateTime.month().day()))"
    }

    /// One line on how the range went.
    private func summary(_ r: ActivityReport) -> String {
        guard !r.lanes.isEmpty || r.turns > 0 else { return week ? "这 7 天没有记录到 agent 活动。" : "这一天没有记录到 agent 活动。" }
        var parts = ["\(isToday && !week ? "今天" : "这段时间")活跃 \(duration(r.activeTime))",
                     "平均同时跑 \(String(format: "%.1f", r.parallelAverage)) 个（峰值 \(r.parallelPeak)）"]
        if let m = r.replyMedian { parts.append("回复中位 \(duration(m))") }
        if !r.allRebuilt, r.bottleneck >= 60 { parts.append("全员等你 \(duration(r.bottleneck))") }
        parts.append("完成 \(r.turns) 轮")
        return parts.joined(separator: "，") + "。"
    }

    private func tiles(_ r: ActivityReport, now: Date) -> some View {
        let backlog = model.backlog
        let running = model.sessions.values.filter { Activity.lane($0) == .running }.count
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
            Tile(title: "并行度", symbol: "square.stack.3d.up", value: String(format: "%.1f", r.parallelAverage),
                 caption: "当前 \(running) · 峰值 \(r.parallelPeak)") {
                Sparkline(values: r.parallelBuckets)
            }
            Tile(title: "回复延迟", symbol: "timer", value: r.replyMedian.map(duration) ?? "–",
                 caption: r.replyP90.map { "P90 \(duration($0)) · \(r.replies.count) 次" } ?? "还没有回复") {
                if let p = r.replyByProject.first, r.replyByProject.count > 1 {
                    Text("最慢：\(p.project) \(duration(p.median))").font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Tile(title: "Agent 利用率", symbol: "gauge.with.dots.needle.67percent",
                 value: r.utilization.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", caption: "运行 ÷（运行 + 等你）")
            Tile(title: "瓶颈时间", symbol: "hourglass.bottomhalf.filled", value: r.allRebuilt ? "–" : duration(r.bottleneck),
                 caption: "有会话在等你、没有在跑的")
            Tile(title: "吞吐", symbol: "bolt", value: r.perActiveHour(r.turns).map { String(format: "%.1f 轮/时", $0) } ?? "–",
                 caption: "\(r.turns) 轮 · \(r.toolCalls) 次工具 · \(compactCount(r.tokens)) token（不含缓存读）")
            Tile(title: "当前积压", symbol: "tray.full", value: "\(backlog.count)",
                 caption: backlog.oldest.map { "最久已等 \(relative($0, now: now))" } ?? "没有在等你的会话")
            Tile(title: "切换", symbol: "arrow.left.arrow.right", value: "\(r.switches) 次",
                 caption: r.perActiveHour(r.switches).map { String(format: "每活跃小时 %.1f 次", $0) } ?? "点卡片或通知跳转")
        }
    }
}

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

/// One row per session that ran or waited in the range, colored by lane, with away time shaded
/// across all of them.
private struct Swimlanes: View {
    @Environment(AppModel.self) private var model
    let report: ActivityReport
    let now: Date
    static let label: CGFloat = 170
    static let maxRows = 40

    var body: some View {
        let rows = Array(report.lanes.prefix(Self.maxRows))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("泳道", systemImage: "chart.bar.xaxis").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                legend
            }
            if rows.isEmpty {
                Text("这段时间没有会话在跑或等你。").font(.system(size: 12)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                axis
                ForEach(rows, id: \.session) { row in
                    HStack(spacing: 8) {
                        rowLabel(row.session)
                        Track(range: report.range, now: now, segments: row.segments, away: report.away)
                            .frame(height: 14)
                    }
                    .frame(height: 18)
                }
                if report.lanes.count > rows.count {
                    Text("另有 \(report.lanes.count - rows.count) 个会话未显示").font(.system(size: 10.5)).foregroundStyle(.tertiary)
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

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(Lane.allCases, id: \.self) { l in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(l.status.tint).frame(width: 10, height: 6)
                    Text(l.status.label)
                }
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.12)).frame(width: 10, height: 6)
                Text("离开")
            }
        }
        .font(.system(size: 10.5)).foregroundStyle(.secondary)
    }

    /// Hours along a day, days along a week.
    private var axis: some View {
        let span = report.range.duration
        let step: TimeInterval = span > 86400 * 1.5 ? 86400 : 3 * 3600
        let ticks = stride(from: 0, through: span, by: step).map { report.range.start.addingTimeInterval($0) }
        return HStack(spacing: 8) {
            Color.clear.frame(width: Self.label, height: 1)
            GeometryReader { g in
                ForEach(ticks, id: \.self) { t in
                    Text(step >= 86400 ? t.formatted(.dateTime.month(.defaultDigits).day()) : t.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted))))
                        .font(.system(size: 9.5)).monospacedDigit().foregroundStyle(.tertiary)
                        .fixedSize()
                        .position(x: g.size.width * t.timeIntervalSince(report.range.start) / span, y: 6)
                }
            }
            .frame(height: 12)
        }
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
                ctx.fill(Path(roundedRect: CGRect(x: x(s.start), y: 2, width: w, height: size.height - 4), cornerRadius: 2),
                         with: .color(s.lane.status.tint.opacity(0.85)))
            }
            if range.contains(now) {
                ctx.fill(Path(CGRect(x: x(now) - 0.5, y: 0, width: 1, height: size.height)), with: .color(.primary.opacity(0.5)))
            }
        }
    }
}

private struct Tile<Extra: View>: View {
    let title: String
    let symbol: String
    let value: String
    let caption: String
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            extra
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .card(.done, radius: 12)
    }
}

extension Tile where Extra == EmptyView {
    init(title: String, symbol: String, value: String, caption: String) {
        self.init(title: title, symbol: symbol, value: value, caption: caption) { EmptyView() }
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let top = values.max(), top > 0 else { return }
            let dx = size.width / CGFloat(values.count - 1)
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * dx, y: size.height * (1 - v / top))
                i == 0 ? line.move(to: p) : line.addLine(to: p)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(.blue.opacity(0.15)))
            ctx.stroke(line, with: .color(.blue.opacity(0.8)), lineWidth: 1.2)
        }
        .frame(height: 22)
    }
}

/// The last 7 days against the 7 before.
private struct WeekComparison: View {
    let this: ActivityReport
    let last: ActivityReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("周环比（近 7 天 vs 前 7 天）", systemImage: "calendar").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("近 7 天")
                    Text("前 7 天")
                    Text("变化")
                }
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.tertiary)
                row("活跃时间", this.activeTime, last.activeTime, duration, better: .up)
                row("平均并行", this.parallelAverage, last.parallelAverage, { String(format: "%.1f", $0) }, better: .up)
                row("利用率", this.utilization, last.utilization, { "\(Int(($0 * 100).rounded()))%" }, better: .up)
                row("回复中位", this.replyMedian, last.replyMedian, duration, better: .down)
                row("瓶颈时间", this.allRebuilt ? nil : this.bottleneck, last.allRebuilt ? nil : last.bottleneck, duration, better: .down)
                row("完成轮数", Double(this.turns), Double(last.turns), { "\(Int($0))" }, better: .up)
                row("切换", Double(this.switches), Double(last.switches), { "\(Int($0))" }, better: nil)
            }
            .font(.system(size: 12)).monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(.done, radius: 14)
    }

    enum Better { case up, down }

    private func row(_ name: String, _ a: Double?, _ b: Double?, _ fmt: (Double) -> String, better: Better?) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(a.map(fmt) ?? "–")
            Text(b.map(fmt) ?? "–").foregroundStyle(.secondary)
            change(a, b, better: better)
        }
    }

    @ViewBuilder
    private func change(_ a: Double?, _ b: Double?, better: Better?) -> some View {
        if let a, let b, b > 0 {
            let pct = (a - b) / b * 100
            let up = pct >= 0
            let good = better.map { ($0 == .up) == up }
            Text("\(up ? "↑" : "↓") \(Int(abs(pct).rounded()))%")
                .foregroundStyle(abs(pct) < 1 || good == nil ? Color.secondary : good! ? .green : .red)
        } else {
            Text("–").foregroundStyle(.tertiary)
        }
    }
}

/// The menu popover's three numbers for today: average parallel, median reply, bottleneck.
struct TodayFigures: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.activityVersion
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let r = model.report(DateInterval(start: today, end: Calendar.current.date(byAdding: .day, value: 1, to: today)!))
        HStack(spacing: 0) {
            figure(String(format: "%.1f", r.parallelAverage), "平均并行")
            figure(r.replyMedian.map(duration) ?? "–", "回复中位")
            figure(r.allRebuilt ? "–" : duration(r.bottleneck), "瓶颈")
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.05)))
        .help("今天，详见主界面「概览」")
    }

    private func figure(_ value: String, _ name: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
