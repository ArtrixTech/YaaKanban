import AppKit
import SwiftUI

// The Overview page, seventh take, after Linear and Apple's Health and Fitness: flat white cards
// on gray, one type family, ink in grays. Two hues carry meaning and nothing else: green is agent
// work, red is time an agent waited on you. Each card is a title, one figure with its change, and a
// chart in hairlines and flat fills: a line, a dial, a curve, a waffle, a donut, packed circles, a
// dot calendar.

enum Ink {
    /// Agent work.
    static let work = Brand.green
    /// An agent waiting on you.
    static let wait = Color.red
    /// Tracks, grid lines, empty cells.
    static let line = Color.primary.opacity(0.07)
    static let faint = Color.primary.opacity(0.14)
}

private let card = RoundedRectangle(cornerRadius: 16, style: .continuous)

/// Quarter hours from 08:00; now is 18:00.
private enum Day {
    static let n = 48, now = 40
    static func wave(_ i: Int, _ base: Double, _ amp: Double, _ period: Double, _ phase: Double = 0) -> Double {
        i > now ? 0 : max(0, base + amp * sin(Double(i) / period + phase))
    }
    static let running: [Double] = (0..<n).map { (i: Int) -> Double in
        wave(i, 1.15, 0.8, 5) + (i < 4 ? 0 : wave(i, 0.75, 0.6, 3.6, 1)) + ((22...37).contains(i) ? wave(i, 0.85, 0.4, 2) : 0)
    }
    static let yesterday: [Double] = (0..<n).map { (i: Int) -> Double in
        max(0, 1.3 + 0.7 * sin(Double(i) / 4.4 + 2)) + max(0, 0.6 * sin(Double(i) / 2.7))
    }
    /// Quarter hours in which an agent waited on you.
    static let waits: [Range<Int>] = [9..<12, 13..<14, 22..<26, 33..<34]
    /// When you were at the computer.
    static let present: [Range<Int>] = [2..<8, 15..<20, 29..<31, 36..<41]
}

/// A card: white on the gray canvas, a hairline shadow, nothing else.
private struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                card.fill(scheme == .dark ? Color.white.opacity(0.05) : .white)
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 0.5, y: 0.5)
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 8, y: 2)
            }
    }
}

/// A card's title and what sits opposite it.
private struct Head<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.ui(.body, .medium)).foregroundStyle(.secondary)
            Spacer(minLength: Space.m)
            trailing.font(.ui(.footnote)).foregroundStyle(.tertiary)
        }
    }
}

extension Head where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// A figure, its units smaller and gray beside it: "3.0 倍", "34 分钟", "9.6 小时".
private struct Fig: View {
    let text: String
    var size: CGFloat
    var ink: Color = .primary
    var unit: Color = .secondary

    init(_ text: String, _ size: CGFloat, ink: Color = .primary, unit: Color = .secondary) {
        self.text = text; self.size = size; self.ink = ink; self.unit = unit
    }

    var body: some View { line.lineLimit(1).fixedSize() }

    var line: Text {
        runs.reduce(Text(verbatim: "")) { line, run in
            line + (run.figure
                ? Text(verbatim: run.text).font(.figure(size)).tracking(size >= 28 ? -size * 0.02 : 0).foregroundStyle(ink)
                : Text(verbatim: "\u{2009}" + run.text).font(.system(size: max(10, (size * 0.5).rounded()), weight: .medium)).foregroundStyle(unit))
        }
    }

    private var runs: [(text: String, figure: Bool)] {
        var out: [(text: String, figure: Bool)] = []
        for c in text {
            let figure = "0123456789.,:".contains(c)
            if out.last?.figure == figure { out[out.count - 1].text.append(c) } else { out.append((String(c), figure)) }
        }
        return out
    }
}

/// The change since the last period: an arrow and the amount in green when it got better, red
/// when worse, after a gray lead.
private struct Delta: View {
    let lead: String
    let amount: String
    let up: Bool
    let good: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(lead).foregroundStyle(Color.secondary).padding(.trailing, 1)
            Group {
                Image(systemName: up ? "arrow.up" : "arrow.down").font(.system(size: 9, weight: .bold))
                Text(amount).monospacedDigit()
            }
            .foregroundStyle(good ? Color.green : Ink.wait)
        }
        .font(.ui(.footnote, .medium))
        .lineLimit(1).fixedSize()
    }
}

/// A legend entry: a small swatch and its label.
private struct Key: View {
    let label: String
    let color: Color
    var dashed = false

    var body: some View {
        HStack(spacing: 5) {
            if dashed {
                HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(color).frame(width: 3, height: 1.5) } }
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 8, height: 8)
            }
            Text(label)
        }
        .font(.ui(.footnote)).foregroundStyle(.secondary)
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

private func label(_ t: String, _ size: CGFloat = 10) -> Text {
    Text(t).font(.system(size: size, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary)
}

// MARK: - Page

struct OverviewPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("概览").font(.system(size: 26, weight: .bold)).tracking(-0.3)
                    Text("10月27日 周一 · 6 个会话 · 41 轮").font(.ui(.body)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: Space.xs) {
                    IconButton(symbol: "chevron.left", help: "") {}
                    IconButton(symbol: "chevron.right", help: "") {}.opacity(0.3)
                    Segmented(items: [(0, "日"), (1, "周"), (2, "月")], selection: .constant(0)).padding(.leading, Space.m)
                }
            }
            .padding(.bottom, 10)
            Leverage().frame(height: 272)
            HStack(spacing: 14) { Waiting().frame(width: 318); Replies(); Away().frame(width: 236) }.frame(height: 248)
            HStack(spacing: 14) { Agents().frame(width: 430); Projects() }.frame(height: 214)
            Rhythm().frame(height: 222)
            Ledger()
            lanes
        }
        .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 32)
    }

    private var lanes: some View {
        Card(padding: 0) {
            HStack(spacing: Space.m) {
                Text("会话明细").font(.ui(.body, .medium))
                Text("6").font(.ui(.body)).foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20).frame(height: 48)
        }
        .frame(height: 48)
    }
}

// MARK: - Leverage

/// The output: leverage on the left; the day as a line on the right, yesterday dashed behind it,
/// your time at the computer as gray bands.
private struct Leverage: View {
    var body: some View {
        Card(padding: 24) {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 0) {
                    Head("杠杆")
                    Fig("3.0×", 64).padding(.top, 14)
                    Delta(lead: "比昨天", amount: "0.4×", up: true, good: true).padding(.top, 6)
                    Spacer(minLength: 0)
                    HStack(spacing: 28) {
                        pair("9.6h", "Agent 干活")
                        pair("3.2h", "你在电脑前")
                    }
                }
                .frame(width: 220, alignment: .leading)
                VStack(alignment: .leading, spacing: 14) {
                    Head(title: "同时在跑") {
                        HStack(spacing: 14) {
                            Key(label: "今天", color: Ink.work)
                            Key(label: "昨天", color: Ink.faint, dashed: true)
                            Key(label: "你在电脑前", color: Ink.line)
                        }
                    }
                    DayCurve()
                }
            }
        }
    }

    private func pair(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Fig(v, 22)
            Text(t).font(.ui(.footnote)).foregroundStyle(.secondary)
        }
    }
}

/// How many agents ran through the day: today's line in green over a light wash, yesterday dashed,
/// your time at the computer as bands, level lines at 1, 2 and 3, the hours under it.
private struct DayCurve: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let axis: CGFloat = 20, right: CGFloat = 18, top: CGFloat = 22
            let w = size.width - right, h = size.height - axis
            let x = { (i: Int) in w * CGFloat(i) / CGFloat(Day.n - 1) }
            let y = { (v: Double) in h - (h - top) * CGFloat(v) / 3.4 }
            for r in Day.present {
                ctx.fill(Path(CGRect(x: x(r.lowerBound), y: top - 8, width: x(r.upperBound) - x(r.lowerBound), height: h - top + 8)),
                         with: .color(Color.primary.opacity(scheme == .dark ? 0.04 : 0.03)))
            }
            for v in 1...3 {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y(Double(v)))); p.addLine(to: CGPoint(x: w, y: y(Double(v))))
                ctx.stroke(p, with: .color(Ink.line), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                ctx.draw(label("\(v)"), at: CGPoint(x: size.width, y: y(Double(v))), anchor: .trailing)
            }
            var floor = Path(); floor.move(to: CGPoint(x: 0, y: h)); floor.addLine(to: CGPoint(x: w, y: h))
            ctx.stroke(floor, with: .color(Ink.faint), lineWidth: 1)

            ctx.stroke(smooth((0..<Day.n).map { CGPoint(x: x($0), y: y(Day.yesterday[$0])) }), with: .color(Ink.faint),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))

            let pts = (0...Day.now).map { CGPoint(x: x($0), y: y(Day.running[$0])) }
            var area = smooth(pts)
            area.addLine(to: CGPoint(x: x(Day.now), y: h)); area.addLine(to: CGPoint(x: 0, y: h)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [Ink.work.opacity(0.16), Ink.work.opacity(0.01)]),
                                                 startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(smooth(pts), with: .color(Ink.work), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            let peak = (0...Day.now).max { Day.running[$0] < Day.running[$1] }!
            let pp = CGPoint(x: x(peak), y: y(Day.running[peak]))
            ctx.fill(disc(pp, 3), with: .color(Ink.work))
            ctx.draw(Text("峰值 3.0 · 15:00").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.secondary),
                     at: CGPoint(x: pp.x, y: pp.y - 8), anchor: .bottom)

            let np = CGPoint(x: x(Day.now), y: y(Day.running[Day.now]))
            var drop = Path(); drop.move(to: CGPoint(x: np.x, y: np.y)); drop.addLine(to: CGPoint(x: np.x, y: h))
            ctx.stroke(drop, with: .color(Ink.faint), lineWidth: 1)
            ctx.fill(disc(np, 5), with: .color(scheme == .dark ? Color(white: 0.16) : .white))
            ctx.stroke(disc(np, 4), with: .color(Ink.work), lineWidth: 2)

            for (i, t) in [(0, "8:00"), (12, "11:00"), (24, "14:00"), (36, "17:00"), (47, "20:00")] {
                ctx.draw(label(t), at: CGPoint(x: x(i), y: size.height), anchor: i == 0 ? .bottomLeading : i == 47 ? .bottomTrailing : .bottom)
            }
            ctx.draw(Text("现在").font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.work),
                     at: CGPoint(x: np.x, y: size.height), anchor: .bottom)
        }
    }
}

// MARK: - Waiting

/// Time agents waited on you, as a clock face from 8:00 at the top round to 20:00: a red arc for
/// each wait, the hours to come dotted, a tick at now.
private struct Waiting: View {
    var body: some View {
        Card {
            Head(title: "Agent 在等你") { Text("8:00–20:00") }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Fig("34m", 34).padding(.top, 10)
                    Delta(lead: "比昨天", amount: "9m", up: false, good: true).padding(.top, 4)
                    Spacer(minLength: 12)
                    VStack(alignment: .leading, spacing: 7) {
                        part("22m", "你离开时", Ink.wait)
                        part("12m", "你在电脑前", Ink.wait.opacity(0.4))
                        part("9m", "最长一次", nil)
                    }
                }
                WaitDial().frame(width: 140, height: 140).padding(.top, 18)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func part(_ v: String, _ t: String, _ c: Color?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c ?? .clear).frame(width: 7, height: 7)
                .overlay { if c == nil { Circle().strokeBorder(Ink.faint, lineWidth: 1.5) } }
            Text(t).font(.ui(.footnote)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(v).font(.figure(12)).foregroundStyle(.primary)
        }
    }
}

private struct WaitDial: View {
    /// Which waits came while you were away (deep red) or at the computer (light).
    let away = [true, false, true, false]

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), R = min(size.width, size.height) / 2 - 5
            let a = { (q: Int) in 2 * Double.pi * Double(q) / Double(Day.n) }
            ctx.stroke(arc(c, R, 0, a(Day.now)), with: .color(Ink.line), style: StrokeStyle(lineWidth: 8, lineCap: .butt))
            ctx.stroke(arc(c, R, a(Day.now), 2 * .pi), with: .color(Ink.line),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 4.5]))
            for (k, r) in Day.waits.enumerated() {
                ctx.stroke(arc(c, R, a(r.lowerBound), a(r.upperBound)), with: .color(away[k] ? Ink.wait : Ink.wait.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 8, lineCap: .butt))
            }
            var tick = Path(); tick.move(to: at(c, R - 7, a(Day.now))); tick.addLine(to: at(c, R + 7, a(Day.now)))
            ctx.stroke(tick, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for h in 0..<12 {
                let p = at(c, R - 15, a(h * 4))
                if h % 3 == 0 { ctx.draw(label("\(8 + h)", 9), at: p) } else { ctx.fill(disc(p, 0.9), with: .color(Ink.faint)) }
            }
            ctx.draw(Fig("5", 22).line, at: CGPoint(x: c.x, y: c.y + 2), anchor: .bottom)
            ctx.draw(Text("次").font(.ui(.caption)).foregroundStyle(.secondary), at: CGPoint(x: c.x, y: c.y + 3), anchor: .top)
        }
    }
}

// MARK: - Replies

/// How fast you answered: the spread of today's replies as a curve on a log scale from 10s to 5m,
/// a tick under it for each reply, the slow tail past 3m in red, the median marked.
private struct Replies: View {
    static let replies: [Double] = (0..<34).map { (k: Int) -> Double in
        let u = { (m: Double) in (Double(k + 1) * m).truncatingRemainder(dividingBy: 1) }
        let z = (u(0.618034) + u(0.414214) + u(0.732051) - 1.5) * 2
        return 48 * exp(0.6 * z)
    } + [205, 240, 270, 290]

    var body: some View {
        Card {
            Head(title: "回复速度") { Text("今天 38 次") }
            Fig("48s", 34).padding(.top, 10)
            Delta(lead: "比昨天", amount: "12s", up: false, good: true).padding(.top, 4)
            Spread().padding(.top, 16)
        }
    }
}

private struct Spread: View {
    var body: some View {
        Canvas { ctx, size in
            let axis: CGFloat = 16, rug: CGFloat = 12, top: CGFloat = 16
            let w = size.width, base = size.height - axis - rug - 4
            let lo = log(8.0), hi = log(340.0)
            let x = { (s: Double) in w * CGFloat((log(s) - lo) / (hi - lo)) }
            let xs = (0...80).map { lo + (hi - lo) * Double($0) / 80 }
            let dens = xs.map { u in Replies.replies.reduce(0.0) { $0 + exp(-pow((u - log($1)) / 0.24, 2) / 2) } }
            let peak = dens.max()!
            let pts = zip(xs, dens).map { CGPoint(x: w * CGFloat(($0 - lo) / (hi - lo)), y: base - (base - top) * CGFloat($1 / peak)) }
            var area = smooth(pts)
            area.addLine(to: CGPoint(x: w, y: base)); area.addLine(to: CGPoint(x: 0, y: base)); area.closeSubpath()
            ctx.fill(area, with: .color(Color.primary.opacity(0.06)))
            var tail = ctx
            tail.clip(to: Path(CGRect(x: x(180), y: 0, width: w, height: base)))
            tail.fill(area, with: .color(Ink.wait.opacity(0.18)))
            ctx.stroke(smooth(pts), with: .color(Color.primary.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            tail.stroke(smooth(pts), with: .color(Ink.wait), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

            var floor = Path(); floor.move(to: CGPoint(x: 0, y: base)); floor.addLine(to: CGPoint(x: w, y: base))
            ctx.stroke(floor, with: .color(Ink.faint), lineWidth: 1)

            let m = x(48)
            var med = Path(); med.move(to: CGPoint(x: m, y: top - 4)); med.addLine(to: CGPoint(x: m, y: base))
            ctx.stroke(med, with: .color(.primary), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            ctx.draw(Text("中位").font(.system(size: 10, weight: .semibold)).foregroundStyle(.primary),
                     at: CGPoint(x: m + 4, y: top - 4), anchor: .topLeading)

            for s in Replies.replies {
                var t = Path(); t.move(to: CGPoint(x: x(s), y: base + 4)); t.addLine(to: CGPoint(x: x(s), y: base + 4 + rug))
                ctx.stroke(t, with: .color(s > 180 ? Ink.wait : Color.primary.opacity(0.3)), lineWidth: 1)
            }
            for (s, t) in [(10.0, "10s"), (30.0, "30s"), (60.0, "1m"), (180.0, "3m"), (300.0, "5m")] {
                ctx.draw(label(t), at: CGPoint(x: min(x(s), w - 8), y: size.height), anchor: .bottom)
            }
        }
    }
}

// MARK: - Away

/// While you were away: a dot a minute, green while an agent still worked, red while one waited.
private struct Away: View {
    let work = 98, stuck = 22

    var body: some View {
        Card {
            Head(title: "你不在时") { Text("离开 2.0h") }
            Fig("81%", 34).padding(.top, 10)
            Text("时间里仍有 Agent 在干活").font(.ui(.footnote, .medium)).foregroundStyle(.secondary).padding(.top, 4)
            Canvas { ctx, size in
                let cols = 15, rows = 8, gap: CGFloat = 4
                let d = min((size.width - gap * CGFloat(cols - 1)) / CGFloat(cols), (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
                // Waits came in two spells: minutes 31–42 and 87–96.
                let red = Set(Array(31..<43) + Array(87..<97))
                for k in 0..<(cols * rows) {
                    let r = CGRect(x: CGFloat(k % cols) * (d + gap), y: CGFloat(k / cols) * (d + gap), width: d, height: d)
                    ctx.fill(Path(ellipseIn: r), with: .color(red.contains(k) ? Ink.wait.opacity(0.85) : Ink.work.opacity(0.8)))
                }
            }
            .padding(.top, 14).padding(.bottom, 12)
            HStack(spacing: 14) {
                Key(label: "干活 98m", color: Ink.work)
                Key(label: "卡住 22m", color: Ink.wait)
            }
        }
    }
}

// MARK: - Agents

/// Who did the work: a donut of each agent's hours in shades of green, the list beside it.
private struct Agents: View {
    let rows: [(logo: String, name: String, hours: String, share: Double, turns: Int)] = [
        ("claudecode", "Claude Code", "5.6h", 0.58, 24), ("codex", "Codex", "3.0h", 0.31, 13), ("cursor", "Cursor", "1.0h", 0.11, 4),
    ]
    static func tone(_ i: Int) -> Color { Ink.work.opacity([1, 0.6, 0.32][i]) }

    var body: some View {
        Card {
            Head(title: "谁在干") { Text("3 个 Agent · 41 轮") }
            HStack(spacing: 28) {
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2), R = min(size.width, size.height) / 2 - 8
                    var start = 0.0
                    for (i, r) in rows.enumerated() {
                        let end = start + 2 * .pi * r.share
                        ctx.stroke(arc(c, R, start + 0.03, end - 0.03), with: .color(Self.tone(i)), style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                        start = end
                    }
                    ctx.draw(Fig("9.6h", 24).line, at: CGPoint(x: c.x, y: c.y + 3), anchor: .bottom)
                    ctx.draw(Text("合计").font(.ui(.caption)).foregroundStyle(.secondary), at: CGPoint(x: c.x, y: c.y + 4), anchor: .top)
                }
                .frame(width: 136, height: 136)
                VStack(spacing: 14) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 1.5).fill(Self.tone(i)).frame(width: 3, height: 28)
                            Logo(name: r.logo, size: 16, ink: .primary.opacity(0.8)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.name).font(.ui(.body, .medium))
                                Text("\(Int(r.share * 100))% · \(r.turns) 轮").font(.ui(.footnote).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Space.m)
                            Fig(r.hours, 17).frame(width: 46, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Projects

/// Where the work went: a circle per project, its area the hours, packed side by side; the time it
/// waited on you under its name.
private struct Projects: View {
    let rows: [(name: String, hours: Double, waited: Int)] = [("YaaKanban", 5.6, 18), ("artrix-skills", 2.6, 4), ("wave-patch", 1.4, 12)]

    var body: some View {
        Card {
            Head(title: "在哪干") { Text("3 个项目") }
            Canvas { ctx, size in
                let k = (size.height / 2 - 2) / CGFloat(5.6).squareRoot()
                let r = rows.map { CGFloat($0.hours).squareRoot() * k }
                var c = [CGPoint(x: r[0], y: size.height / 2)]
                for (i, y) in [(1, r[1] + 2), (2, size.height - r[2] - 2)] {
                    let d = r[i - 1] + r[i] + 4, dy = y - c[i - 1].y
                    c.append(CGPoint(x: c[i - 1].x + (d * d - dy * dy).squareRoot(), y: y))
                }
                let shift = (size.width - (c[2].x + r[2])) / 2
                c = c.map { CGPoint(x: $0.x + shift, y: $0.y) }
                for (i, row) in rows.enumerated() {
                    ctx.fill(disc(c[i], r[i]), with: .color(Agents.tone(i).opacity(i == 0 ? 0.9 : 1)))
                    let ink: Color = i == 2 ? .primary : .white
                    ctx.draw(Fig(String(format: "%.1fh", row.hours), i == 0 ? 26 : 18, ink: ink, unit: ink.opacity(0.75)).line,
                             at: CGPoint(x: c[i].x, y: c[i].y - (i == 0 ? 6 : 4)), anchor: .bottom)
                    ctx.draw(Text(row.name).font(.ui(i == 0 ? .callout : .caption, .semibold)).foregroundStyle(ink.opacity(0.9)),
                             at: CGPoint(x: c[i].x, y: c[i].y - (i == 0 ? 3 : 2)), anchor: .top)
                    ctx.draw(Text("等你 \(row.waited)m").font(.system(size: i == 0 ? 11 : 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(i == 2 ? Ink.wait : .white.opacity(0.85)),
                             at: CGPoint(x: c[i].x, y: c[i].y + (i == 0 ? 16 : 12)), anchor: .top)
                }
            }
            .padding(.top, 12)
        }
    }
}

// MARK: - Rhythm

/// The week: a cell a half hour from 8:00, a row a day, green as deep as how many agents ran; today
/// last, its hours to come outlined; each day's hours at the end of its row.
private struct Rhythm: View {
    let days = ["周二", "周三", "周四", "周五", "周六", "周日", "今天"]
    let totals = ["8.4h", "11.2h", "9.1h", "7.8h", "2.6h", "1.9h", "9.6h"]

    var body: some View {
        Card {
            Head(title: "本周节奏") {
                HStack(spacing: 14) {
                    Text("最忙 周三下午")
                    HStack(spacing: 3) {
                        Text("少")
                        ForEach([0.12, 0.35, 0.6, 1.0], id: \.self) { RoundedRectangle(cornerRadius: 2).fill(Ink.work.opacity($0)).frame(width: 9, height: 9) }
                        Text("多")
                    }
                }
            }
            Canvas { ctx, size in
                let lead: CGFloat = 36, tail: CGFloat = 48, axis: CGFloat = 18, cols = 32, rows = 7, nowCol = 20
                let pitch = (size.width - lead - tail) / CGFloat(cols), row = (size.height - axis) / CGFloat(rows)
                let dw = pitch - 3, d = row - 3
                for r in 0..<rows {
                    let today = r == rows - 1, y = CGFloat(r) * row
                    ctx.draw(Text(days[r]).font(.ui(.caption, today ? .semibold : .regular)).foregroundStyle(today ? .primary : .secondary),
                             at: CGPoint(x: 0, y: y + d / 2), anchor: .leading)
                    for col in 0..<cols {
                        let cell = Path(roundedRect: CGRect(x: lead + CGFloat(col) * pitch, y: y, width: dw, height: d), cornerRadius: 3)
                        if today && col >= nowCol {
                            ctx.stroke(cell.strokedPath(StrokeStyle(lineWidth: 1, dash: [2, 2])), with: .color(Ink.faint))
                            continue
                        }
                        let v = level(r, col)
                        ctx.fill(cell, with: .color(v < 0.12 ? Ink.line : Ink.work.opacity(0.12 + 0.88 * v)))
                    }
                    ctx.draw(Fig(totals[r], 13, ink: today ? .primary : .secondary).line, at: CGPoint(x: size.width, y: y + d / 2), anchor: .trailing)
                }
                for (col, t) in [(0, "8:00"), (8, "12:00"), (16, "16:00"), (24, "20:00"), (32, "24:00")] {
                    ctx.draw(label(t), at: CGPoint(x: lead + CGFloat(col) * pitch - (col == 32 ? 3 : 0), y: size.height),
                             anchor: col == 0 ? .bottomLeading : col == 32 ? .bottomTrailing : .bottom)
                }
            }
            .padding(.top, 16)
        }
    }

    private func level(_ r: Int, _ col: Int) -> Double {
        let h = 8 + Double(col) / 2
        if h >= 22 { return r == 1 || r == 3 ? max(0, 0.55 - (h - 22) * 0.25) : 0 }
        guard h >= 9 else { return 0 }
        var v = 0.5 + 0.4 * sin((h - 9) / 2.2 + Double(r)) - (abs(h - 12.5) < 0.8 ? 0.45 : 0)
        if r == 4 || r == 5 { v -= 0.5 }
        if r == 1, h >= 14, h < 18 { v += 0.45 }
        return max(0, min(1, v))
    }
}

// MARK: - Ledger

/// The rest of the day's numbers on one card: a label, the figure, its change.
private struct Ledger: View {
    let cells: [(title: String, value: String, delta: String?, up: Bool, good: Bool)] = [
        ("平均同时在跑", "2.4", "0.3", true, true), ("利用率", "86%", "4%", true, true),
        ("接手速度", "3m40s", "50s", true, false), ("每次介入", "7m", "1m", true, true),
        ("吞吐", "12.8轮/h", "1.1", true, true), ("最长连跑", "47m", "6m", false, false),
        ("当前积压", "2", nil, true, true), ("切换", "23次", "4", false, true),
        ("工具调用", "1,284", "210", true, true), ("token", "3.1M", "0.4M", true, true),
    ]

    var body: some View {
        Card(padding: 0) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<2, id: \.self) { r in
                    GridRow {
                        ForEach(0..<5, id: \.self) { c in cell(cells[r * 5 + c]) }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cell(_ c: (title: String, value: String, delta: String?, up: Bool, good: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(c.title).font(.ui(.footnote)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Fig(c.value, 20)
                if let d = c.delta {
                    HStack(spacing: 1) {
                        Image(systemName: c.up ? "arrow.up" : "arrow.down").font(.system(size: 8, weight: .bold))
                        Text(d).font(.ui(.caption, .medium).monospacedDigit())
                    }
                    .foregroundStyle(c.good ? Color.green : Ink.wait)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}
