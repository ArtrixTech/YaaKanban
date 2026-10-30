import SwiftUI
import YaaCore

// The Overview's cards. Each reads one `OverviewData`: one hue per card lights its label, units
// and chart, figures stay in the primary ink.
// Cards are as tall as their content; charts that can grow take the height a row gives them.

/// What every card reads: the period's report, the one before over the same stretch (for the
/// changes) and in full (for the dotted lines), and the clock.
struct OverviewData {
    let period: Period
    let report: ActivityReport
    /// The one before, as far in as this one is; nil when nothing was recorded then.
    let previous: ActivityReport?
    let previousFull: ActivityReport
    /// What the changes are against: "yesterday so far".
    let vs: String
    /// The period in a word or two: "Today", "That week".
    let scope: String
    let now: Date

    var inProgress: Bool { report.range.contains(now) }
    /// Waits, replies and absences exist only where recorded live: compare them only when neither
    /// period was partly rebuilt, or the rebuilt side reads as "no waiting".
    var comparesWaits: Bool { report.rebuiltUntil == nil && previous?.rebuiltUntil == nil }
    /// Where now falls along the chart slices, 0…1.
    var nowAt: Double { inProgress ? slotFraction(now, report.bucketEdges) : 1 }
}

/// A change against the period before: the arrow and amount in the primary ink, what it's against
/// dim. Nil without both values.
func change(_ a: Double?, _ b: Double?, vs: String, fmt: (Double) -> String) -> Text? {
    guard let a, let b else { return nil }
    let shown = fmt(abs(a - b))
    if shown == fmt(0) { return Text(String(localized: "Same as \(vs)")).foregroundStyle(Ink.tertiary) }
    return Text(verbatim: (a > b ? "↑ " : "↓ ") + shown).foregroundStyle(Ink.primary)
        + Text(verbatim: " " + String(localized: "vs \(vs)")).foregroundStyle(Ink.tertiary)
}

extension AppModel {
    /// The agent a session ran, also once it's deleted (its key starts with the agent).
    func agent(of id: String) -> AgentKind? {
        sessions[id]?.agent ?? id.split(separator: ":").first.flatMap { AgentKind(rawValue: String($0)) }
    }
}

// MARK: - Drawing

private func disc(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }

/// A line through points, smoothed (Catmull-Rom).
private func smooth(_ pts: [CGPoint]) -> Path {
    var p = Path()
    guard pts.count > 1 else { return p }
    p.move(to: pts[0])
    for i in 0..<(pts.count - 1) {
        let a = pts[max(i - 1, 0)], b = pts[i], c = pts[i + 1], d = pts[min(i + 2, pts.count - 1)]
        p.addCurve(to: c, control1: CGPoint(x: b.x + (c.x - a.x) / 6, y: b.y + (c.y - a.y) / 6),
                   control2: CGPoint(x: c.x - (d.x - b.x) / 6, y: c.y - (d.y - b.y) / 6))
    }
    return p
}

/// Angles clockwise from twelve o'clock.
private func at(_ c: CGPoint, _ r: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a))) }
private func arc(_ c: CGPoint, _ r: CGFloat, _ a: Double, _ b: Double) -> Path {
    var p = Path()
    p.addArc(center: c, radius: r, startAngle: .radians(a - .pi / 2), endAngle: .radians(b - .pi / 2), clockwise: false)
    return p
}

/// Axis text inside a chart.
private func tick(_ t: String, _ c: Color, _ size: CGFloat = 10.5) -> Text {
    Text(verbatim: t).font(.figure(size, .medium)).foregroundStyle(c)
}

/// How strong a glow is: soft on a white card, where a haze turns muddy; fuller on a dark one.
private func glowStrength(_ ctx: GraphicsContext) -> Double { ctx.environment.colorScheme == .dark ? 0.7 : 0.3 }

/// "Now": a disc of the card's hue with a white core, ringed in the card's colour so it sits clear
/// of the line under it.
private func knob(_ ctx: GraphicsContext, _ p: CGPoint, _ hue: Color, r: CGFloat = 5) {
    var halo = ctx
    halo.addFilter(.blur(radius: 5))
    halo.opacity = glowStrength(ctx)
    halo.fill(disc(p, r + 3), with: .color(hue))
    ctx.fill(disc(p, r + 2), with: .color(Fill.widget))
    ctx.fill(disc(p, r), with: .color(hue))
    ctx.fill(disc(p, r * 0.45), with: .color(.white))
}

/// A stroke with a glow of its own colour under it.
private func glow(_ ctx: GraphicsContext, _ path: Path, _ shading: GraphicsContext.Shading, width: CGFloat, blur: CGFloat = 7) {
    var g = ctx
    g.addFilter(.blur(radius: blur))
    g.opacity = glowStrength(ctx)
    g.stroke(path, with: shading, style: StrokeStyle(lineWidth: width + 2, lineCap: .round, lineJoin: .round))
    ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
}

/// A chart's line as (fraction along, value): each finished slice at its middle, held out to the
/// left edge and to `end` (now, or the right edge). A slice still running is left out: its average
/// counts the time not yet come as idle.
private func series(_ values: [Double], _ edges: [Date], end: Double, now: Date?) -> [(x: Double, v: Double)] {
    var out: [(x: Double, v: Double)] = []
    for i in values.indices where edges.indices.contains(i + 1) {
        if let now, edges[i + 1] > now { break }
        out.append(((Double(i) + 0.5) / Double(values.count), values[i]))
    }
    guard let first = out.first, let last = out.last else { return [] }
    return [(0, first.v)] + out + [(end, last.v)]
}

// MARK: - Accents

/// Leverage, the headline: hours of agent work per hour of yours. Its chart is each day's leverage
/// across the week (the month in the month view), the same days of the one before pale behind.
struct LeverageCard: View {
    @Environment(AppModel.self) private var model
    let data: OverviewData

    var body: some View {
        let r = data.report, ramp = Ramp.work, days = LeverageDays(data, model, calendar: model.settings.calendar)
        Widget {
            WidgetHead(title: String(localized: "Leverage"), ramp: ramp,
                       info: String(localized: "Hours of agent work per hour you were here. Agent time counts all running, away included; yours counts only while you were at the Mac and an agent was running or waiting on you. Each bar is one day's leverage, the pale one behind it the same day of the period before; above 1×, agents did more than you spent."), context: data.scope)
            FigureLine(figure: figure(r.leverage.map { String(format: "%.1f×", $0) } ?? "–", ramp, FigureSize.accent),
                       change: data.comparesWaits ? change(r.leverage, data.previous?.leverage, vs: data.vs) { String(format: "%.1f×", $0) } : nil,
                       note: String(localized: "Agents \(duration(r.agentTime)) ÷ you \(duration(r.activeTime))"))
            LeverageBars(days: days, now: data.now, ramp: ramp)
                .frame(minHeight: 84, maxHeight: .infinity)
                .padding(.top, Space.s)
            HStack(spacing: Space.l) {
                ChartKey(text: days.label) { Capsule().fill(ramp.hue).frame(width: 12, height: 6) }
                ChartKey(text: days.previousLabel) { Capsule().fill(ramp.dim).frame(width: 12, height: 6) }
                Spacer(minLength: 0)
            }
            .padding(.top, Space.m)
        }
    }
}

/// Each day's leverage over the week around the period (the month, in the month view), and the
/// same days of the one before; nil where too little was on to count, or the day is still to come.
private struct LeverageDays {
    var starts: [Date] = []
    var values: [Double?] = []
    var before: [Double?] = []
    /// The days the period covers: one in the day view, all of them otherwise.
    var shown: Range<Int> = 0..<0
    var monthly = false
    var label = "", previousLabel = ""

    @MainActor init(_ data: OverviewData, _ model: AppModel, calendar cal: Calendar = .current) {
        monthly = data.period == .month
        let unit: Calendar.Component = monthly ? .month : .weekOfYear
        let at = data.report.range.start
        guard let span = cal.dateInterval(of: unit, for: at),
              let prev = cal.date(byAdding: unit, value: -1, to: span.start).flatMap({ cal.dateInterval(of: unit, for: $0) }) else { return }
        let current = span.contains(data.now)
        label = monthly ? String(localized: current ? "This month" : "That month") : String(localized: current ? "This week" : "That week")
        previousLabel = monthly ? String(localized: "Previous month") : String(localized: "Previous week")
        func daily(_ range: DateInterval) -> (starts: [Date], values: [Double?]) {
            let edges = Periods.edges(.month, range, cal)
            let r = model.report(range, edges: edges)
            let values = r.activeBuckets.indices.map { i -> Double? in
                guard edges[i] < data.now, r.activeBuckets[i] >= 60 else { return nil }
                return r.agentBuckets[i] / r.activeBuckets[i]
            }
            return (Array(edges.dropLast()), values)
        }
        (starts, values) = daily(span)
        before = daily(prev).values
        if data.period == .day, let i = starts.firstIndex(where: { cal.isDate($0, inSameDayAs: at) }) {
            shown = i..<(i + 1)
        } else {
            shown = starts.indices
        }
    }
}

/// A bar a day, the period's days lit and the rest of the week mid; the same
/// day of the period before pale behind each; days still to come a hollow stub. Break-even 1× as
/// a hairline.
private struct LeverageBars: View {
    let days: LeverageDays
    let now: Date
    let ramp: Ramp

    var body: some View {
        let cal = Calendar.current
        let labels = days.starts.enumerated().map { i, d -> String? in
            if cal.isDateInToday(d) { return String(localized: "Today") }
            if days.monthly { return i % 7 == 0 ? d.formatted(.dateTime.day()) : nil }
            return d.formatted(.dateTime.weekday(.abbreviated))
        }
        Canvas { ctx, size in
            let n = days.starts.count
            guard n > 0 else { return }
            let axis: CGFloat = 16, right: CGFloat = 22, top: CGFloat = days.monthly ? 4 : 16
            let base = size.height - axis, pitch = (size.width - right) / CGFloat(n)
            let width = min(pitch * (days.monthly ? 0.62 : 0.5), 26)
            let ceiling = max(((days.values + days.before).compactMap { $0 }.max() ?? 0) * 1.1, 1.5)
            func y(_ v: Double) -> CGFloat { base - CGFloat(v / ceiling) * (base - top) }
            func bar(_ cx: CGFloat, _ w: CGFloat, _ v: Double) -> Path {
                let rect = CGRect(x: cx - w / 2, y: y(v), width: w, height: max(base - y(v), 2))
                return Path(roundedRect: rect, cornerRadius: min(w / 2, 4), style: .continuous)
            }
            let one = y(1)
            var even = Path(); even.move(to: CGPoint(x: 0, y: one)); even.addLine(to: CGPoint(x: size.width - right, y: one))
            ctx.stroke(even, with: .color(ramp.mid.opacity(0.6)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 4]))
            ctx.draw(tick("1×", Ink.tertiary), at: CGPoint(x: size.width, y: one), anchor: .trailing)
            for i in 0..<n {
                let cx = pitch * (CGFloat(i) + 0.5), lit = days.shown.contains(i)
                if days.before.indices.contains(i), let b = days.before[i] {
                    ctx.fill(bar(cx + width * 0.22, width, b), with: .color(ramp.dim))
                }
                if let v = days.values[i] {
                    ctx.fill(bar(cx - width * 0.22, width, v), with: .color(lit ? ramp.hue : ramp.mid))
                    if !days.monthly {
                        ctx.draw(tick(String(format: v < 10 ? "%.1f" : "%.0f", v), lit ? Ink.primary : Ink.tertiary),
                                 at: CGPoint(x: cx - width * 0.22, y: y(v) - 2), anchor: .bottom)
                    }
                } else if days.starts[i] >= now {
                    let stub = CGRect(x: cx - width * 0.72, y: base - 4, width: width, height: 4)
                    ctx.stroke(Path(roundedRect: stub.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2, style: .continuous), with: .color(ramp.faint), lineWidth: 1)
                }
                if let label = labels[i] {
                    ctx.draw(tick(label, lit || cal.isDateInToday(days.starts[i]) ? Ink.primary : Ink.tertiary),
                             at: CGPoint(x: cx, y: size.height), anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Running

/// How many agents ran across the period, the one before dotted behind, your time at the computer
/// as a strip under it.
struct RunningCard: View {
    @Environment(AppModel.self) private var model
    let data: OverviewData

    var body: some View {
        let r = data.report, ramp = Ramp.run
        Widget {
            WidgetHead(title: String(localized: "Running at once"), ramp: ramp,
                       info: String(localized: "How many agents ran at the same time, on average while any ran, and at the peak. The dotted line is the period before; the gray strip under it is when you were at the Mac. In a month, each point is that day's agent hours."),
                       context: data.inProgress && data.period == .day ? String(localized: "Now \(model.runningCount)") : nil)
            HStack(alignment: .lastTextBaseline) {
                FigureLine(figure: figure(one(r.parallelAverage), ramp),
                           change: change(r.parallelAverage, data.previous?.parallelAverage, vs: data.vs) { String(format: "%.1f", $0) },
                           note: String(localized: "While agents ran · peak \(r.parallelPeak)"))
                HStack(spacing: 14) {
                    ChartKey(text: data.scope) { Capsule().fill(ramp.hue).frame(width: 14, height: 3) }
                    ChartKey(text: String(localized: "Last period")) {
                        HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Circle().fill(ramp.mid).frame(width: 3, height: 3) } }
                    }
                    ChartKey(text: String(localized: "You here")) { Capsule().fill(Ink.secondary).frame(width: 14, height: 4) }
                }
                .fixedSize().padding(.bottom, Space.s)
            }
            RunCurve(data: data, ramp: ramp).frame(minHeight: 104, maxHeight: .infinity).padding(.top, Space.m)
        }
    }
}

private struct RunCurve: View {
    let data: OverviewData
    let ramp: Ramp

    var body: some View {
        let r = data.report, period = data.period, now = data.inProgress ? data.now : nil, nowAt = data.nowAt
        // Hours of session time per day in a month, otherwise sessions at once.
        let scale = period == .month ? 24.0 : 1
        let today = series(r.parallelBuckets.map { $0 * scale }, r.bucketEdges, end: nowAt, now: now)
        let before = series(data.previousFull.parallelBuckets.map { $0 * scale }, data.previousFull.bucketEdges, end: 1, now: nil)
        let peak = max((today + before).map(\.v).max() ?? 0, 1)
        let step: Double = peak > 24 ? 12 : peak > 12 ? 6 : peak > 6 ? 3 : peak > 3 ? 2 : 1
        let ceiling = (peak / step).rounded(.up) * step * 1.1
        let present = presence(r.activeBuckets, r.bucketEdges, end: nowAt)
        let ticks = axisTicks(period, r.range).enumerated().filter { period != .day || $0.offset % 2 == 0 }
            .map { (x: slotFraction(midpoint($0.element.span), r.bucketEdges), label: period == .day ? "\($0.element.label):00" : $0.element.label) }
        Canvas { ctx, size in
            let axis: CGFloat = 16, strip: CGFloat = 4, gap: CGFloat = 12
            let base = size.height - axis - strip - gap, top: CGFloat = 4
            func x(_ f: Double) -> CGFloat { size.width * CGFloat(f) }
            func y(_ v: Double) -> CGFloat { base - CGFloat(v / ceiling) * (base - top) }
            // Levels, as dotted hairlines in the hue.
            for l in stride(from: step, through: ceiling / 1.1, by: step) {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y(l))); p.addLine(to: CGPoint(x: size.width - 18, y: y(l)))
                ctx.stroke(p, with: .color(ramp.dim), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 4]))
                ctx.draw(tick(String(format: "%.0f", l), Ink.tertiary), at: CGPoint(x: size.width, y: y(l)), anchor: .trailing)
            }
            // The period before, dotted.
            ctx.stroke(smooth(before.map { CGPoint(x: x($0.x), y: y($0.v)) }), with: .color(ramp.mid),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [0.1, 5]))
            // This one: an area dimming to nothing, the line brightening towards now.
            let pts = today.map { CGPoint(x: x($0.x), y: y($0.v)) }
            if let last = pts.last {
                let line = smooth(pts)
                var area = line
                area.addLine(to: CGPoint(x: last.x, y: base)); area.addLine(to: CGPoint(x: 0, y: base)); area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [ramp.hue.opacity(0.32), ramp.hue.opacity(0)]),
                                                     startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: base)))
                glow(ctx, line, .linearGradient(Gradient(colors: [ramp.hue.opacity(0.55), ramp.hue]), startPoint: .zero, endPoint: CGPoint(x: max(last.x, 1), y: 0)), width: 2.4)
                if now != nil {
                    var drop = Path(); drop.move(to: last); drop.addLine(to: CGPoint(x: last.x, y: base + gap + strip))
                    ctx.stroke(drop, with: .color(Ink.tertiary), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    knob(ctx, last, ramp.hue)
                }
            }
            // Your time at the computer.
            let sy = base + gap + strip / 2
            var track = Path(); track.move(to: CGPoint(x: 0, y: sy)); track.addLine(to: CGPoint(x: x(nowAt), y: sy))
            ctx.stroke(track, with: .color(Color.primary.opacity(0.08)), style: StrokeStyle(lineWidth: strip, lineCap: .round))
            for s in present {
                var p = Path(); p.move(to: CGPoint(x: x(s.lowerBound), y: sy)); p.addLine(to: CGPoint(x: x(s.upperBound), y: sy))
                ctx.stroke(p, with: .color(Ink.secondary), style: StrokeStyle(lineWidth: strip, lineCap: .round))
            }
            for t in ticks where now == nil || abs(t.x - nowAt) * size.width > 44 {
                let anchor: UnitPoint = t.x < 0.02 ? .bottomLeading : t.x > 0.98 ? .bottomTrailing : .bottom
                ctx.draw(tick(t.label, Ink.tertiary), at: CGPoint(x: x(t.x), y: size.height), anchor: anchor)
            }
            if now != nil {
                ctx.draw(tick(String(localized: "Now"), Ink.primary), at: CGPoint(x: x(nowAt), y: size.height),
                         anchor: nowAt > 0.97 ? .bottomTrailing : .bottom)
            }
        }
    }

    /// Slices the user was at the computer with something on, merged into runs, as fractions.
    private func presence(_ active: [Double], _ edges: [Date], end: Double) -> [ClosedRange<Double>] {
        let n = Double(max(active.count, 1))
        var out: [ClosedRange<Double>] = []
        for (i, v) in active.enumerated() where v > 0 {
            let a = Double(i) / n, b = min(Double(i + 1) / n, end)
            guard b > a else { continue }
            if let last = out.last, last.upperBound >= a { out[out.count - 1] = last.lowerBound...b } else { out.append(a...b) }
        }
        return out
    }
}

// MARK: - Response

/// How fast you respond when an agent needs you: replying (to a question, or with the next prompt
/// after a turn), and getting to a finished turn. Each half has its median against the period before and the times on a log scale, the
/// middle half lit and beamed towards the centre, the median as the knob, each one a bead above.
struct ResponseCard: View {
    let data: OverviewData

    var body: some View {
        let r = data.report, ramp = Ramp.reply
        Widget {
            WidgetHead(title: String(localized: "Response time"), ramp: ramp,
                       info: String(localized: "How long agents waited for you, away time taken out. Replying: from an agent asking a question or permission, or finishing a turn, to your answer or next prompt. Reviewing: from a turn finishing to you opening it or following up. Each figure is the median; on the arcs the lit band holds the middle half and each dot is one."))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Space.xl) { replying(r, ramp); reviewing(r, ramp) }
                VStack(alignment: .leading, spacing: Space.l) { replying(r, ramp); reviewing(r, ramp) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func replying(_ r: ActivityReport, _ ramp: Ramp) -> some View {
        ResponseHalf(title: String(localized: "Replying"), times: r.replies, median: r.replyMedian, p90: r.replyP90,
                     previous: data.previous?.replyMedian, empty: String(localized: "No replies"),
                     scale: ResponseArc.replying, data: data, ramp: ramp)
    }

    private func reviewing(_ r: ActivityReport, _ ramp: Ramp) -> some View {
        ResponseHalf(title: String(localized: "Reviewing"), times: r.pickups, median: r.pickupMedian, p90: r.pickupP90,
                     previous: data.previous?.pickupMedian, empty: String(localized: "Nothing reviewed"),
                     scale: ResponseArc.reviewing, data: data, ramp: ramp)
    }
}

private struct ResponseHalf: View {
    let title: String
    let times: [TimeInterval]
    let median: TimeInterval?
    let p90: TimeInterval?
    let previous: TimeInterval?
    let empty: String
    let scale: ResponseArc.Scale
    let data: OverviewData
    let ramp: Ramp

    var body: some View {
        let live = !data.report.allRebuilt
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                Text(title).font(.ui(.callout, .semibold)).foregroundStyle(Ink.secondary)
                if !times.isEmpty {
                    Text(verbatim: "\(times.count)").font(.figure(TextSize.callout.rawValue, .medium)).foregroundStyle(Ink.tertiary)
                }
            }
            .padding(.top, Space.l)
            FigureLine(figure: figure(live ? median.map(duration) ?? "–" : "–", ramp),
                       change: data.comparesWaits ? change(median, previous, vs: data.vs, fmt: duration) : nil,
                       note: !live ? String(localized: "Not recorded live") : p90.map { String(localized: "90% within \(duration($0))") } ?? empty)
            ResponseArc(times: times, median: median, scale: scale, ramp: ramp)
                .frame(minHeight: 88, maxHeight: .infinity).padding(.top, Space.xs)
        }
        .frame(minWidth: 220, idealWidth: 220, maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResponseArc: View {
    /// A log scale from its first tick to its last; `mark` is the tick in the primary ink, `slow`
    /// where a bead turns bright.
    struct Scale { let ticks: [(TimeInterval, String)]; let mark: TimeInterval; let slow: TimeInterval }
    static let replying = Scale(ticks: [10, 30, 60, 120, 300].map { ($0, duration($0)) }, mark: 60, slow: 180)
    static let reviewing = Scale(ticks: [30, 120, 600, 1800].map { ($0, duration($0)) } + [(7200, String(localized: "\(String(2))h"))],
                                 mark: 600, slow: 3600)

    let times: [TimeInterval]
    let median: TimeInterval?
    let scale: Scale
    let ramp: Ramp

    var body: some View {
        let sorted = times.sorted()
        let q1 = sorted.isEmpty ? nil : sorted[sorted.count / 4], q3 = sorted.isEmpty ? nil : sorted[(sorted.count * 3) / 4]
        let lo = scale.ticks.first?.0 ?? 1, hi = scale.ticks.last?.0 ?? 2
        Canvas { ctx, size in
            let half = 1.08, w: CGFloat = 10
            let r = min((size.width / 2 - 8) / CGFloat(sin(half)), (size.height - 26) / CGFloat(1 - cos(half)))
            let c = CGPoint(x: size.width / 2, y: 22 + r)
            func ang(_ s: Double) -> Double { -half + 2 * half * log(min(max(s, lo), hi) / lo) / log(hi / lo) }
            ctx.stroke(arc(c, r, -half, half), with: .color(ramp.dim), style: StrokeStyle(lineWidth: w, lineCap: .round))
            if let q1, let q3 {
                // The beam from the lit band towards the centre.
                let a = ang(q1), b = max(ang(q3), ang(q1) + 0.04)
                var beam = Path(); beam.move(to: c)
                beam.addArc(center: c, radius: r, startAngle: .radians(a - .pi / 2), endAngle: .radians(b - .pi / 2), clockwise: false)
                beam.closeSubpath()
                ctx.fill(beam, with: .radialGradient(Gradient(colors: [ramp.hue.opacity(0), ramp.hue.opacity(0), ramp.hue.opacity(0.3)]),
                                                     center: c, startRadius: 0, endRadius: r))
                glow(ctx, arc(c, r, a, b), .color(ramp.hue), width: w, blur: 8)
            }
            // Each one; at most 200, spread over the whole range rather than the slowest.
            let step = max(1, (sorted.count + 199) / 200)
            for (i, s) in stride(from: 0, to: sorted.count, by: step).map({ sorted[$0] }).enumerated() {
                ctx.fill(disc(at(c, r + 11 + CGFloat(i % 2) * 4, ang(s)), 1.4), with: .color(s > scale.slow ? ramp.hue : ramp.mid))
            }
            // The scale, inside the arc.
            for (s, l) in scale.ticks {
                ctx.fill(disc(at(c, r, ang(s)), 1.2), with: .color(Fill.widget))
                ctx.draw(tick(l, s == scale.mark ? Ink.primary : Ink.tertiary), at: at(c, r - 19, ang(s)), anchor: .center)
            }
            if let median { knob(ctx, at(c, r, ang(median)), ramp.hue, r: 4.2) }
        }
    }
}

// MARK: - Agents

/// Who did the work: one lane per agent, its running across the period on a shared scale.
struct AgentsCard: View {
    @Environment(AppModel.self) private var model
    let data: OverviewData

    var body: some View {
        let r = data.report, ramp = Ramp.work, rows = agents
        let total = rows.reduce(0) { $0 + $1.time }
        let peak = rows.flatMap(\.slots).max() ?? 0
        Widget {
            WidgetHead(title: String(localized: "Who did the work"), ramp: ramp,
                       info: String(localized: "Each agent's share of the running time, with its turns. The line is when it ran across the period."),
                       context: rows.isEmpty ? nil : rows.count == 1 ? String(localized: "1 agent · \(duration(total))")
                           : String(localized: "\(rows.count) agents · \(duration(total))"))
            FigureLine(figure: figure(rows.first.map { percent($0.time / total) } ?? "–", ramp),
                       note: rows.first.map { String(localized: "By \($0.kind.displayName)") } ?? String(localized: "No agents ran."))
            VStack(spacing: Space.m) {
                ForEach(Array(rows.prefix(3).enumerated()), id: \.element.kind) { k, row in
                    HStack(spacing: Space.m) {
                        AgentLogo(agent: row.kind, size: 12, ink: ramp.hue).frame(width: 24, height: 24).background(Circle().fill(ramp.faint))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.kind.displayName).font(.ui(.body, .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
                            Text(verbatim: "\(percent(row.time / total)) · \(turns(row.turns))").font(.figure(TextSize.footnote.rawValue, .medium))
                                .foregroundStyle(Ink.tertiary).lineLimit(1)
                        }
                        .frame(width: 96, alignment: .leading)
                        AgentSpark(values: row.slots.map { peak > 0 ? $0 / peak : 0 }, edges: r.bucketEdges,
                                   now: data.inProgress ? data.now : nil, end: data.nowAt, ramp: ramp, lead: k == 0)
                            .frame(height: 22)
                        figure(duration(row.time), ramp, FigureSize.row).lineLimit(1).fixedSize().frame(minWidth: 48, alignment: .trailing)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.top, Space.l)
        }
    }

    /// Per agent kind, running time, turns and running per chart slice, the busiest first.
    private var agents: [(kind: AgentKind, time: TimeInterval, turns: Int, slots: [Double])] {
        let r = data.report, edges = r.bucketEdges, n = max(edges.count - 1, 0)
        var by: [AgentKind: (time: TimeInterval, turns: Int, slots: [Double])] = [:]
        for lane in r.lanes {
            guard let kind = model.agent(of: lane.session) else { continue }
            var entry = by[kind] ?? (0, 0, [Double](repeating: 0, count: n))
            entry.turns += r.turnsBySession[lane.session] ?? 0
            for s in lane.segments where s.lane == .running {
                entry.time += s.end.timeIntervalSince(s.start)
                for i in 0..<n where edges[i] < s.end && edges[i + 1] > s.start {
                    entry.slots[i] += min(edges[i + 1], s.end).timeIntervalSince(max(edges[i], s.start))
                }
            }
            by[kind] = entry
        }
        return by.filter { $0.value.time >= 1 }.map { ($0.key, $0.value.time, $0.value.turns, $0.value.slots) }.sorted { $0.time > $1.time }
    }
}

/// One agent's lane: a line with a fading area, the lead agent in full hue.
private struct AgentSpark: View {
    let values: [Double]
    let edges: [Date]
    let now: Date?
    let end: Double
    let ramp: Ramp
    let lead: Bool

    var body: some View {
        Canvas { ctx, size in
            let base = size.height - 1
            var rule = Path(); rule.move(to: CGPoint(x: 0, y: base)); rule.addLine(to: CGPoint(x: size.width, y: base))
            ctx.stroke(rule, with: .color(ramp.faint), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 4]))
            let pts = series(values, edges, end: end, now: now).map { CGPoint(x: size.width * $0.x, y: base - CGFloat($0.v) * (base - 2)) }
            guard let last = pts.last else { return }
            let line = smooth(pts)
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: base)); area.addLine(to: CGPoint(x: 0, y: base)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [ramp.hue.opacity(lead ? 0.3 : 0.18), ramp.hue.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: base)))
            ctx.stroke(line, with: .color(lead ? ramp.hue : ramp.mid), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            ctx.fill(disc(last, 2.6), with: .color(lead ? ramp.hue : ramp.mid))
        }
    }
}

// MARK: - Projects

/// Where the work went: a circle per project, area by agent hours, the largest lit.
struct ProjectsCard: View {
    @Environment(AppModel.self) private var model
    let data: OverviewData

    var body: some View {
        let ramp = Ramp.work, items = projects
        let total = items.reduce(0) { $0 + $1.running }
        let shown = Array(items.prefix(3))
        Widget {
            WidgetHead(title: String(localized: "Where the work went"), ramp: ramp,
                       info: String(localized: "Agent running time by project; a circle's area is its time. Under each name, how long its sessions waited on you."),
                       context: items.isEmpty ? nil : items.count == 1 ? String(localized: "1 project") : String(localized: "\(items.count) projects"))
            FigureLine(figure: figure(shown.first.map { percent($0.running / total) } ?? "–", ramp),
                       note: shown.first.map { String(localized: "In \($0.name)") } ?? String(localized: "No agents ran."))
            HStack(alignment: .center, spacing: Space.xl) {
                Bubbles(values: shown.map(\.running), ramp: ramp).frame(width: 128, height: 96)
                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .center, spacing: Space.m) {
                            Circle().fill(Bubbles.fill(i, ramp)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.ui(.body, .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
                                Text(String(localized: "Waiting \(duration(p.waiting))")).font(.figure(TextSize.footnote.rawValue, .medium))
                                    .foregroundStyle(p.waiting >= 60 ? Ramp.wait.mid : Ink.tertiary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            figure(duration(p.running), ramp, FigureSize.row).lineLimit(1).fixedSize()
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.top, Space.m)
        }
    }

    /// Per project, agent running time and time waiting on the user, the busiest first.
    private var projects: [(name: String, running: TimeInterval, waiting: TimeInterval)] {
        var by: [String: (TimeInterval, TimeInterval)] = [:]
        for t in data.report.sessionTotals {
            let s = model.sessions[t.session]
            let name = s == nil ? String(localized: "Deleted session") : s?.projectName ?? String(localized: "Other")
            by[name, default: (0, 0)].0 += t.running
            by[name, default: (0, 0)].1 += t.waiting
        }
        return by.map { ($0.key, $0.value.0, $0.value.1) }.filter { $0.1 >= 1 }.sorted { $0.1 > $1.1 }
    }
}

/// Up to three circles, area by value, packed touching and scaled to fit.
private struct Bubbles: View {
    let values: [Double]
    let ramp: Ramp

    static func fill(_ i: Int, _ ramp: Ramp) -> Color { i == 0 ? ramp.hue : ramp.hue.opacity(i == 1 ? 0.42 : 0.22) }

    var body: some View {
        GeometryReader { geo in
            let (centers, radii) = Self.layout(values.map { CGFloat(sqrt(max($0, 0))) })
            let box = zip(centers, radii).reduce(CGRect.null) { $0.union(CGRect(x: $1.0.x - $1.1, y: $1.0.y - $1.1, width: 2 * $1.1, height: 2 * $1.1)) }
            let k = box.isNull ? 0 : min(geo.size.width / box.width, geo.size.height / box.height) * 0.96
            ZStack {
                ForEach(radii.indices, id: \.self) { i in
                    let r = radii[i] * k
                    Circle().fill(Self.fill(i, ramp)).frame(width: 2 * r, height: 2 * r)
                        .overlay {
                            if r > 22 {
                                Text(verbatim: duration(values[i])).font(.figure(i == 0 ? 17 : 12)).lineLimit(1).minimumScaleFactor(0.6)
                                    .foregroundStyle(i == 0 ? Fill.widget : Ink.primary).padding(.horizontal, Space.xs)
                            }
                        }
                        .position(x: geo.size.width / 2 + (centers[i].x - box.midX) * k, y: geo.size.height / 2 + (centers[i].y - box.midY) * k)
                }
            }
        }
    }

    /// The first circle, the second up and right touching it, the third under both.
    static func layout(_ radii: [CGFloat]) -> ([CGPoint], [CGFloat]) {
        guard let r0 = radii.first, r0 > 0 else { return ([], []) }
        let g = r0 * 0.06
        var c = [CGPoint.zero]
        if radii.count > 1 { c.append(CGPoint(x: (r0 + radii[1] + g) * 0.954, y: -(r0 + radii[1] + g) * 0.3)) }
        if radii.count > 2 { c.append(touching(c[0], r0 + radii[2] + g, c[1], radii[1] + radii[2] + g)) }
        return (c, Array(radii.prefix(c.count)))
    }

    /// The lower point at distance `d0` from `a` and `d1` from `b`.
    private static func touching(_ a: CGPoint, _ d0: CGFloat, _ b: CGPoint, _ d1: CGFloat) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y, d = max(sqrt(dx * dx + dy * dy), 0.001)
        let l = (d0 * d0 - d1 * d1 + d * d) / (2 * d), h = sqrt(max(0, d0 * d0 - l * l))
        let m = CGPoint(x: a.x + dx * l / d, y: a.y + dy * l / d)
        let p1 = CGPoint(x: m.x - dy * h / d, y: m.y + dx * h / d), p2 = CGPoint(x: m.x + dy * h / d, y: m.y - dx * h / d)
        return p1.y > p2.y ? p1 : p2
    }
}

// MARK: - Rhythm

/// Seven days up to the period's last (or today): a row of half-hour cells per day, brighter where
/// more agents ran, the time still to come hollow, now as the knob, each day's agent hours at the
/// end of its row.
struct RhythmCard: View {
    @Environment(AppModel.self) private var model
    let data: OverviewData

    var body: some View {
        let ramp = Ramp.run, week = Week(data, model)
        Widget {
            WidgetHead(title: String(localized: "7-day rhythm"), ramp: ramp,
                       info: String(localized: "The last 7 days in half hours, brighter where more agents ran at once. Each row ends with that day's agent hours; Busiest marks the 3 hours with the most agent time."),
                       context: week.busiest.map { String(localized: "Busiest \($0)") })
            HStack(alignment: .lastTextBaseline) {
                FigureLine(figure: figure(duration(week.report.agentTime), ramp), note: String(localized: "Agent hours over 7 days"))
                HStack(spacing: Space.xs) {
                    Text("Less").foregroundStyle(Ink.tertiary)
                    ForEach(0..<5, id: \.self) { l in
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Week.cell(l, ramp)).frame(width: 10, height: 10)
                    }
                    Text("More").foregroundStyle(Ink.tertiary)
                }
                .font(.ui(.footnote, .medium)).fixedSize().padding(.bottom, Space.s)
            }
            WeekGrid(week: week, now: data.now, ramp: ramp).frame(height: 128).padding(.top, Space.m)
        }
    }
}

/// The seven days' report, in half hours, and where each day's slices sit in it.
private struct Week {
    let report: ActivityReport
    /// Per day, its start and the range of slices in it.
    let days: [(start: Date, slices: Range<Int>)]

    @MainActor init(_ data: OverviewData, _ model: AppModel, calendar cal: Calendar = .current) {
        let last = cal.startOfDay(for: data.inProgress ? data.now : data.report.range.end.addingTimeInterval(-1))
        var edges: [Date] = [], days: [(start: Date, slices: Range<Int>)] = []
        for i in -6...0 {
            guard let start = cal.date(byAdding: .day, value: i, to: last), let day = cal.dateInterval(of: .day, for: start) else { continue }
            let e = Periods.edges(.day, day, cal)
            let from = max(edges.count - 1, 0)
            edges += edges.last == e.first ? Array(e.dropFirst()) : e
            days.append((day.start, from..<(edges.count - 1)))
        }
        let range = DateInterval(start: edges.first ?? last, end: edges.last ?? last)
        report = model.report(range, edges: edges)
        self.days = days
    }

    /// 0 for none, then four steps up to the week's busiest slice.
    func level(_ i: Int) -> Int {
        let b = report.parallelBuckets, peak = b.max() ?? 0
        guard b.indices.contains(i), b[i] > 0, peak > 0 else { return 0 }
        return min(4, 1 + Int(b[i] / peak * 3.999))
    }

    static func cell(_ l: Int, _ ramp: Ramp) -> Color { l == 0 ? ramp.faint : ramp.hue.opacity([0, 0.3, 0.5, 0.75, 1][l]) }

    func hours(_ day: Int) -> TimeInterval {
        let b = report.agentBuckets
        return days[day].slices.reduce(0) { $0 + (b.indices.contains($1) ? b[$1] : 0) }
    }

    /// The 3 hours with the most agent time, as "Wed 14:00–17:00".
    var busiest: String? {
        let b = report.agentBuckets, e = report.bucketEdges
        guard b.count == e.count - 1, b.count >= 6 else { return nil }
        var best = (sum: 0.0, at: 0)
        for i in 0...(b.count - 6) {
            let s = b[i..<(i + 6)].reduce(0, +)
            if s > best.sum { best = (s, i) }
        }
        return best.sum > 0 ? slotLabel(.week, e[best.at], e[best.at + 6]) : nil
    }
}

private struct WeekGrid: View {
    let week: Week
    let now: Date
    let ramp: Ramp

    var body: some View {
        let labels = week.days.map { Calendar.current.isDateInToday($0.start) ? String(localized: "Today") : $0.start.formatted(.dateTime.weekday(.abbreviated)) }
        let totals = week.days.indices.map { duration(week.hours($0)) }
        let edges = week.report.bucketEdges
        Canvas { ctx, size in
            let left: CGFloat = 44, right: CGFloat = 44, axis: CGFloat = 16
            let width = size.width - left - right, pitchY = (size.height - axis) / CGFloat(max(week.days.count, 1))
            let ch = min(pitchY - 3, 12)
            for (d, day) in week.days.enumerated() {
                let cy = pitchY * (CGFloat(d) + 0.5)
                let today = Calendar.current.isDateInToday(day.start)
                let span = (edges.indices.contains(day.slices.upperBound) ? edges[day.slices.upperBound] : day.start).timeIntervalSince(day.start)
                ctx.draw(tick(labels[d], today ? Ink.primary : Ink.tertiary, 11), at: CGPoint(x: 0, y: cy), anchor: .leading)
                for i in day.slices where edges.indices.contains(i + 1) && span > 0 {
                    let x0 = left + width * CGFloat(edges[i].timeIntervalSince(day.start) / span)
                    let x1 = left + width * CGFloat(edges[i + 1].timeIntervalSince(day.start) / span)
                    let rect = CGRect(x: x0 + 1.5, y: cy - ch / 2, width: max(1, x1 - x0 - 3), height: ch)
                    if edges[i] >= now {
                        ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2.5, style: .continuous), with: .color(ramp.faint), lineWidth: 1)
                    } else {
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 2.5, style: .continuous), with: .color(Week.cell(week.level(i), ramp)))
                    }
                }
                ctx.draw(tick(totals[d], today ? ramp.hue : Ink.secondary, 11.5), at: CGPoint(x: size.width, y: cy), anchor: .trailing)
                if today, span > 0, now > day.start, now.timeIntervalSince(day.start) < span {
                    knob(ctx, CGPoint(x: left + width * CGFloat(now.timeIntervalSince(day.start) / span), y: cy), ramp.hue, r: 4)
                }
            }
            for h in stride(from: 0, through: 24, by: 6) {
                let anchor: UnitPoint = h == 0 ? .bottomLeading : h == 24 ? .bottomTrailing : .bottom
                ctx.draw(tick("\(h):00", Ink.tertiary), at: CGPoint(x: left + width * CGFloat(h) / 24, y: size.height), anchor: anchor)
            }
        }
    }
}
