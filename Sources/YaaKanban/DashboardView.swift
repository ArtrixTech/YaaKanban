import SwiftUI
import YaaCore

extension Period {
    var label: String {
        switch self {
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        }
    }
    /// "this" one, said of the current period.
    var current: String {
        switch self {
        case .day: String(localized: "Today")
        case .week: String(localized: "This week")
        case .month: String(localized: "This month")
        }
    }
    /// The one before, so far (while the current one runs) or in full.
    func previous(soFar: Bool) -> String {
        switch self {
        case .day: soFar ? String(localized: "yesterday so far") : String(localized: "the day before")
        case .week: soFar ? String(localized: "last week so far") : String(localized: "the week before")
        case .month: soFar ? String(localized: "last month so far") : String(localized: "the month before")
        }
    }
    /// The step buttons' help.
    func step(forward: Bool) -> String {
        switch self {
        case .day: forward ? String(localized: "Next day") : String(localized: "Previous day")
        case .week: forward ? String(localized: "Next week") : String(localized: "Previous week")
        case .month: forward ? String(localized: "Next month") : String(localized: "Previous month")
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
/// the one before, as a wall of cards. The totals ride in the top bar, the counts in chips.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    /// Periods back from the current one; the current one follows the clock.
    @State private var back = 0
    @State private var period: Period
    @State private var lanes = false

    init(period: Period = .day) { _period = State(initialValue: period) }

    var body: some View {
        // Redraws every 30 s for the now line, and on each recorded row.
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let _ = model.activityVersion
            let p = Periods(period, back: back, now: ctx.date, calendar: model.settings.calendar)
            let r = model.report(p.range, edges: p.edges)
            // The one before over the same stretch, for the changes; in full, for the dotted lines.
            let prev = model.report(p.previousSoFar)
            // Nothing recorded then: no comparison, rather than "up by all of it".
            let base = prev.lanes.isEmpty && prev.turns == 0 ? nil : prev
            let data = OverviewData(period: period, report: r, previous: base,
                                    previousFull: model.report(p.previous, edges: p.previousEdges),
                                    vs: period.previous(soFar: p.inProgress), scope: scope(p), now: ctx.date)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    topBar(p, r)
                    if let until = r.rebuiltUntil { rebuiltNote(r, until) }
                    chips(counts(r))
                    cards(data)
                    chips(attention(r), more: lanesChip(r))
                    if lanes { SessionLanes(period: period, report: r, now: ctx.date) }
                }
                .padding(.horizontal, Space.page).padding(.top, 28).padding(.bottom, Space.page)
                .frame(maxWidth: 1240, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func scope(_ p: Periods) -> String {
        p.inProgress ? period.current
            : period == .day ? String(localized: "That day") : period == .week ? String(localized: "That week") : String(localized: "That month")
    }

    // MARK: Top bar

    /// The title and range, the period's four totals, then the range controls; stacked when narrow.
    private func topBar(_ p: Periods, _ r: ActivityReport) -> some View {
        let totals = [(String(localized: "Sessions"), "\(r.lanes.count)"), (String(localized: "Turns"), "\(r.turns)"),
                      (String(localized: "Agent hours"), duration(r.agentTime)), (String(localized: "You here"), duration(r.activeTime))]
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                title(p)
                Spacer(minLength: 24)
                totalsRow(totals)
                Spacer(minLength: 24)
                controls
            }
            .frame(height: 44)
            VStack(alignment: .leading, spacing: Space.l) {
                HStack { title(p); Spacer(minLength: Space.l); controls }
                totalsRow(totals)
            }
        }
    }

    private func title(_ p: Periods) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Overview").font(.ui(.display, .bold)).tracking(-0.3)
            Text(verbatim: period.rangeLabel(p)).font(.ui(.callout, .medium)).monospacedDigit().foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private func totalsRow(_ totals: [(String, String)]) -> some View {
        HStack(spacing: 28) {
            ForEach(totals, id: \.0) { t in
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(t.0).font(.ui(.footnote, .medium)).foregroundStyle(.secondary)
                    figure(t.1, Ramp.run, 19)
                }
                .fixedSize()
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Space.xs) {
            if back > 0 {
                Button(period.current) { back = 0 }.buttonStyle(.action(.ghost, size: .small)).padding(.trailing, Space.xs)
            }
            IconButton(symbol: "chevron.left", help: period.step(forward: false)) { back += 1 }
            IconButton(symbol: "chevron.right", help: period.step(forward: true)) { back = max(0, back - 1) }
                .disabled(back == 0).opacity(back == 0 ? 0.3 : 1)
            Segmented(items: Period.allCases.map { ($0, $0.label) },
                      selection: Binding(get: { period }, set: { period = $0; back = 0 }))
                .padding(.leading, Space.m)
        }
        .fixedSize()
    }

    private func rebuiltNote(_ r: ActivityReport, _ until: Date) -> some View {
        Label(r.allRebuilt ? "This stretch predates recording: only run times and turns were rebuilt from session history; waits, replies, time away and tokens have no data."
              : "Rebuilt from session history before \(until.formatted(.dateTime.month().day().hour().minute())): run times and turns only.",
              systemImage: "clock.arrow.circlepath")
            .font(.ui(.footnote)).foregroundStyle(.secondary)
    }

    // MARK: Chips

    private typealias Chip = (symbol: String, title: String, value: String, ramp: Ramp, info: String)

    /// How the agents ran and what they produced.
    private func counts(_ r: ActivityReport) -> [Chip] {
        [("gauge.with.needle", String(localized: "Agent utilization"), r.utilization.map(percent) ?? "–", .run,
         String(localized: "While you were here, the share of agent time spent running rather than blocked on you (asking or stuck). A finished turn waiting for review counts as neither.")),
         ("square.stack.3d.up.fill", String(localized: "Peak at once"), "\(r.parallelPeak)", .run,
         String(localized: "The most agents running at the same time.")),
         ("hammer.fill", String(localized: "Tool calls"), r.toolCalls.formatted(), .work,
         String(localized: "Tools the agents called in the turns that finished in the period.")),
         ("number", String(localized: "Tokens"), r.allRebuilt ? "–" : compactCount(r.tokens), .work,
         String(localized: "Tokens the agents reported using.")),
         ("checkmark.seal.fill", String(localized: "Reviewed"), "\(r.pickups.count)", .work,
         String(localized: "Finished turns you opened or followed up on."))]
    }

    /// What it took from the user.
    private func attention(_ r: ActivityReport) -> [Chip] {
        [("text.bubble.fill", String(localized: "Prompts and answers"), "\(r.interventions)", .reply,
         String(localized: "Times you stepped in: prompts you sent and questions you answered.")),
         ("arrow.left.arrow.right", String(localized: "Switches"), "\(r.switches)", .reply,
         String(localized: "Times you jumped to a session's terminal from the app."))]
    }

    /// One row of chips, wrapping onto two when it doesn't fit; `more` ends it.
    private func chips(_ items: [Chip], more: AnyView? = nil) -> some View {
        let row = ForEach(items, id: \.title) { c in StatChip(symbol: c.symbol, title: c.title, value: c.value, ramp: c.ramp, info: c.info).frame(minWidth: 116) }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.m) { row; more }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: Space.m)], spacing: Space.m) { row; more }
        }
    }

    /// Opens the per-session lanes under the cards.
    private func lanesChip(_ r: ActivityReport) -> AnyView {
        AnyView(Button {
            withAnimation(.easeOut(duration: 0.15)) { lanes.toggle() }
        } label: {
            HStack(spacing: Space.m) {
                Text("Session lanes").font(.ui(.callout, .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
                Text(verbatim: "\(r.lanes.count)").font(.figure(TextSize.body.rawValue, .medium)).foregroundStyle(Ink.tertiary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.ui(.footnote, .semibold)).foregroundStyle(Ink.tertiary)
                    .rotationEffect(.degrees(lanes ? 90 : 0))
            }
            .statChip().frame(minWidth: 116)
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressable()))
    }

    // MARK: Cards

    /// Two cards a row when wide (the wide ones alone); narrower, the agents and projects share
    /// the width evenly, then leverage and response stack too, one column on the narrowest. Leverage
    /// keeps one width while paired, as its week of bars looks sparse any wider. A row is as tall as its tallest card's content; the others stretch their
    /// charts to match. Each layout states its
    /// ideal width, so a long name truncates instead of pushing the layout to fewer columns.
    private func cards(_ d: OverviewData) -> some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: Space.l) {
                row { LeverageCard(data: d).frame(width: 330); ResponseCard(data: d) }
                RunningCard(data: d)
                row { AgentsCard(data: d).frame(width: 520); ProjectsCard(data: d) }
                RhythmCard(data: d)
            }
            .frame(minWidth: 980, idealWidth: 980)
            VStack(spacing: Space.l) {
                row { LeverageCard(data: d).frame(width: 330); ResponseCard(data: d) }
                RunningCard(data: d)
                row { AgentsCard(data: d); ProjectsCard(data: d) }
                RhythmCard(data: d)
            }
            .frame(minWidth: 830, idealWidth: 830)
            VStack(spacing: Space.l) {
                LeverageCard(data: d)
                ResponseCard(data: d)
                RunningCard(data: d)
                row { AgentsCard(data: d); ProjectsCard(data: d) }
                RhythmCard(data: d)
            }
            .frame(minWidth: 640, idealWidth: 640)
            VStack(spacing: Space.l) {
                LeverageCard(data: d); ResponseCard(data: d); RunningCard(data: d)
                AgentsCard(data: d); ProjectsCard(data: d); RhythmCard(data: d)
            }
        }
    }

    private func row(@ViewBuilder _ cards: () -> some View) -> some View {
        HStack(alignment: .top, spacing: Space.l) { cards() }.fixedSize(horizontal: false, vertical: true)
    }
}

func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

/// "1m 12s", "3m", "2.4h".
func duration(_ t: TimeInterval) -> String {
    let s = Int(t.rounded())
    if s < 60 { return String(localized: "\(s)s") }
    if s < 600 { return s % 60 == 0 ? String(localized: "\(s / 60)m") : String(localized: "\(s / 60)m \(s % 60)s") }
    if s < 3600 { return String(localized: "\(s / 60)m") }
    return String(localized: "\(one(t / 3600))h")
}

/// One decimal, for figures put into sentences.
func one(_ x: Double) -> String { String(format: "%.1f", x) }
func sessions(_ n: Int) -> String { n == 1 ? String(localized: "1 session") : String(localized: "\(n) sessions") }
func turns(_ n: Int) -> String { n == 1 ? String(localized: "1 turn") : String(localized: "\(n) turns") }

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
        return [1, 5, 10, 15, 20, 25, days].compactMap { n in day(n - 1).map { ($0, $0.start.formatted(.dateTime.day())) } }
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

/// One chart slice in words: "14:00–14:30", "Tue 15:00–18:00", "Oct 3".
func slotLabel(_ period: Period, _ a: Date, _ b: Date) -> String {
    let hm = Date.FormatStyle.dateTime.hour().minute()
    return switch period {
    case .month: a.formatted(.dateTime.month().day())
    case .week: "\(a.formatted(hm.weekday(.abbreviated)))–\(b.formatted(hm))"
    case .day: "\(a.formatted(hm))–\(b.formatted(hm))"
    }
}

private func swatch(_ c: Color, _ name: String) -> some View {
    HStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 6)
        Text(name)
    }
}
/// Per-session swimlanes, opened from the chip under the cards: the busiest few, then all on request.
private struct SessionLanes: View {
    @Environment(AppModel.self) private var model
    let period: Period
    let report: ActivityReport
    let now: Date
    @State private var all = false
    static let label: CGFloat = 170
    static let few = 10

    var body: some View {
        let totals = report.sessionTotals
        let segments = Dictionary(report.lanes.map { ($0.session, $0.segments) }, uniquingKeysWith: { a, _ in a })
        let rows = all ? totals : Array(totals.prefix(Self.few))
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Space.s) {
                Text("Session lanes").font(.ui(.body, .semibold))
                Text(verbatim: sessions(totals.count)).font(.ui(.footnote)).foregroundStyle(.secondary)
                Spacer()
                lanesLegend
            }
            .padding(.bottom, Space.xs)
            if !rows.isEmpty {
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
                    Button(all ? "Busiest \(Self.few) only" : "Show all \(totals.count)") { all.toggle() }
                        .buttonStyle(.link).font(.system(size: 11))
                }
            }
        }
        .padding(Space.xxl)
        .background(WidgetSurface())
    }

    private func rowLabel(_ id: String) -> some View {
        let s = model.sessions[id]
        return Button {
            if s != nil { model.selection = id }
        } label: {
            HStack(spacing: 5) {
                if let s { AgentLogo(agent: s.agent, size: 10) }
                Text(s?.title ?? String(localized: "Deleted session")).font(.system(size: 11)).lineLimit(1)
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
            swatch(Color.primary.opacity(0.12), String(localized: "Away"))
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
/// popover shows today.
struct QuickFigures: View {
    @Environment(AppModel.self) private var model
    let range: DateInterval
    var help: String

    /// Fixed, so the panel's cards sit at the same height folded or not.
    static let height: CGFloat = 40

    var body: some View {
        let _ = model.activityVersion
        let r = model.report(range, buckets: 1)
        HStack(spacing: 0) {
            figure(duration(r.agentTime), String(localized: "agent hours"))
            figure(r.leverage.map { String(format: "%.1f×", $0) } ?? "–", String(localized: "Leverage"))
            figure(r.replyMedian.map(duration) ?? "–", String(localized: "Reply"))
            figure("\(r.turns)", String(localized: "Turns"))
        }
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.05)))
        .help(help)
    }

    private func figure(_ value: String, _ name: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
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
                     help: String(localized: "Today. Click to open Overview in the main window."))
    }
}

/// The floating panel's figures: leverage over the last `window` as the hero with its trend
/// behind, and today's agent hours. The arrow and the dashed line read against today's usual
/// 4 hours (`typicalLeverage`), not the day so far, so like is compared with like.
/// The folded rail keeps only the leverage. Windows move by whole minutes so the report cache holds
/// between redraws.
struct RecentFigures: View {
    @Environment(AppModel.self) private var model
    var folded = false

    /// Fixed, so the panel's cards sit at the same height folded or not.
    static let height: CGFloat = 52
    /// Long enough that agents left running while the user is away still count against the time
    /// that set them going.
    static let window: TimeInterval = 4 * 3600
    /// Trend points, each the leverage of the `window` up to it, a `trendStep`th of that apart:
    /// together they span the last `window` too.
    static let trendStep = 24, trendPoints = trendStep + 1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let _ = model.activityVersion
            let end = Calendar.current.dateInterval(of: .minute, for: ctx.date)!.end
            let slices = Self.trendPoints + Self.trendStep - 1
            let span = Self.window / Double(Self.trendStep) * Double(slices)
            let trend = model.report(DateInterval(start: end.addingTimeInterval(-span), end: end), buckets: slices)
                .rollingLeverage(window: Self.trendStep)
            let leverage = trend.last ?? nil
            let today = model.report(DateInterval(start: Calendar.current.startOfDay(for: ctx.date), end: end), buckets: 1)
            let baseline = typicalLeverage(at: ctx.date)
            let arrow = Self.direction(leverage, against: baseline)
            let help = String(localized: "Over the last 4 hours, agent hours (away included) per hour you were here. The arrow compares it with today's average 4-hour leverage, taken at each whole hour.")
            Group {
                if folded {
                    // 20 pt wide: the number alone, and an arrow for its trend instead of the chart.
                    VStack(spacing: 2) {
                        Text("Leverage").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                        Text(leverage.map { String(format: $0 < 10 ? "%.1f" : "%.0f", $0) } ?? "–")
                            .font(.figure(12, .bold))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if let (symbol, tint) = arrow {
                            Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(tint)
                        }
                    }
                    .padding(.horizontal, 1)
                    .help(help)
                } else {
                    HStack(alignment: .center, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            // The same arrow as the folded rail's, beside the caption so the figure keeps its room.
                            HStack(spacing: 3) {
                                caption(String(localized: "Leverage"))
                                if let (symbol, tint) = arrow {
                                    Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                                }
                            }
                            value(leverage, size: 24)
                        }
                        .frame(width: 70, alignment: .leading)
                        .help(help)
                        let ticks = Self.ticks(end: end, span: span, slices: slices)
                        VStack(spacing: 1) {
                            Sparkline(values: trend, baseline: baseline, ticks: ticks.map(\.at))
                                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3)],
                                                     startPoint: .leading, endPoint: .trailing))
                            TimeAxis(ticks: ticks)
                        }
                        .padding(.top, 6).padding(.bottom, 3)
                        .help("Leverage trend: each point is the leverage over the 4 hours up to then, across the last \(SettingsView.duration(Self.window / 60)); the dashed line is today's average 4-hour leverage, taken at each whole hour.")
                        VStack(alignment: .trailing, spacing: 2) {
                            caption(String(localized: "Agent hours today"))
                            Text(duration(today.agentTime)).font(.figure(15))
                        }
                        .frame(width: 64, alignment: .trailing)
                        .help("All agents' running time today, added up")
                        .padding(.leading, 8)
                    }
                    .padding(.leading, 12).padding(.trailing, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: Self.height)
            .background(RecentFigures.plate(radius: folded ? 6 : 9))
        }
    }

    /// Round clock times under the trend, as fractions along it: the first point (a window after
    /// the report's start) is 0, now is 1. At most three, kept clear of the ends.
    static func ticks(end: Date, span: TimeInterval, slices: Int) -> [TimeAxis.Tick] {
        let slice = span / Double(slices)
        let first = end.addingTimeInterval(-span + slice * Double(trendStep))
        let length = end.timeIntervalSince(first)
        let step = [5.0, 10, 15, 30, 60, 120, 180, 240, 360].map { $0 * 60 }.first { length / $0 <= 3 } ?? 720 * 60
        // Steps divide a day, so multiples of them from local midnight land on round times.
        let midnight = Calendar.current.startOfDay(for: end)
        var t = midnight.addingTimeInterval((first.timeIntervalSince(midnight) / step).rounded(.up) * step)
        var out: [TimeAxis.Tick] = []
        while t < end {
            let at = t.timeIntervalSince(first) / length
            if at > 0.1 && at < 0.75 { out.append(.init(at: at, label: timeFormat.string(from: t))) }
            t.addTimeInterval(step)
        }
        return out
    }

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Today's usual leverage over a `window`: the mean of the leverage over the `window` up to each
    /// whole hour since midnight. Nil before the first hour, or with too little on to count.
    private func typicalLeverage(at date: Date) -> Double? {
        let hour = Calendar.current.dateInterval(of: .hour, for: date)!.start
        let hours = Int((hour.timeIntervalSince(Calendar.current.startOfDay(for: date)) / 3600).rounded())
        guard hours > 0 else { return nil }
        // Hourly slices from a `window` before the first hour, so each hour's run of them is whole.
        let w = Int(Self.window / 3600), slices = hours + w - 1
        let edges = (0...slices).map { hour.addingTimeInterval(Double($0 - slices) * 3600) }
        let each = model.report(DateInterval(start: edges[0], end: hour), edges: edges)
            .rollingLeverage(window: w).compactMap { $0 }
        return each.isEmpty ? nil : each.reduce(0, +) / Double(each.count)
    }

    /// Up or down when the leverage is a tenth or more above or below today's usual, else level.
    static func direction(_ now: Double?, against base: Double?) -> (String, Color)? {
        guard let now, let base else { return nil }
        if now > base * 1.1 { return ("arrow.up.right", Sparkline.lime) }
        if now < base * 0.9 { return ("arrow.down.right", .orange) }
        return ("arrow.right", .secondary)
    }

    private func value(_ v: Double?, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(v.map { String(format: "%.1f", $0) } ?? "–")
                .font(.figure(size, .bold))
            if v != nil {
                Text("×").font(.system(size: size * 0.6, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.6)
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
    }

    static func plate(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape.fill(Fill.control)
    }
}

/// The leverage trend: a smooth line from 0 up, filled down to the bottom edge, with a dashed line
/// at `baseline` (today's usual 4-hour leverage) and the latest point marked. Gaps (too little time on to count) are bridged; leading ones
/// are left empty.
struct Sparkline: View {
    let values: [Double?]
    var baseline: Double?
    /// Fractions along the line where `TimeAxis` labels a time: a faint guide each.
    var ticks: [Double] = []

    static let green = Color(red: 0.06, green: 0.73, blue: 0.51), lime = Color(red: 0.29, green: 0.87, blue: 0.5)
    /// Room right of the latest point for its dot; `TimeAxis` maps time the same way.
    static let endInset: CGFloat = 6

    var body: some View {
        Canvas { ctx, size in
            let known = values.enumerated().compactMap { i, v in v.map { (i, $0) } }
            let top = max(((known.map(\.1) + [baseline ?? 0]).max() ?? 0) * 1.2, 1.25)
            let n = max(values.count - 1, 1)
            func y(_ v: Double) -> CGFloat { 5 + (size.height - 5) * (1 - v / top) }
            let points = known.map { CGPoint(x: (size.width - Self.endInset) * Double($0.0) / Double(n), y: y($0.1)) }

            for at in ticks {
                let x = (size.width - Self.endInset) * at
                ctx.fill(Path(CGRect(x: x - 0.25, y: 3, width: 0.5, height: size.height - 3)), with: .color(.primary.opacity(0.08)))
            }

            // Today's usual level, which the arrow reads against.
            if let baseline {
                var base = Path()
                base.move(to: CGPoint(x: 0, y: y(baseline))); base.addLine(to: CGPoint(x: size.width, y: y(baseline)))
                ctx.stroke(base, with: .color(.primary.opacity(0.14)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }

            guard let first = points.first, let last = points.last else { return }
            // Each step eases out of one point and into the next, so it never overshoots.
            var line = Path()
            line.move(to: first)
            for (a, b) in zip(points, points.dropFirst()) {
                let mid = (a.x + b.x) / 2
                line.addCurve(to: b, control1: CGPoint(x: mid, y: a.y), control2: CGPoint(x: mid, y: b.y))
            }
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: size.height)); area.addLine(to: CGPoint(x: first.x, y: size.height))
            area.closeSubpath()

            ctx.fill(area, with: .linearGradient(Gradient(colors: [Self.green.opacity(0.32), Self.green.opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: points.map(\.y).min()!), endPoint: CGPoint(x: 0, y: size.height)))
            let stroke = GraphicsContext.Shading.linearGradient(Gradient(colors: [Self.green, Self.lime]),
                                                                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
            var glow = ctx
            glow.addFilter(.blur(radius: 3))
            glow.opacity = 0.55
            glow.stroke(line, with: stroke, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            ctx.stroke(line, with: stroke, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)), with: .color(Self.lime.opacity(0.22)))
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)), with: .color(Self.lime))
        }
        .accessibilityLabel("Leverage trend")
    }
}

/// Clock times under the `Sparkline`, at the same x as its points, with "Now" at its right end.
struct TimeAxis: View {
    struct Tick: Equatable { let at: Double; let label: String }
    let ticks: [Tick]

    var body: some View {
        GeometryReader { g in
            let width = g.size.width - Sparkline.endInset
            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.label) { t in
                    label(t.label).position(x: width * t.at, y: g.size.height / 2)
                }
                label(String(localized: "Now")).frame(width: g.size.width, alignment: .trailing)
                    .position(x: g.size.width / 2, y: g.size.height / 2)
            }
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 7.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.tertiary).fixedSize()
    }
}
