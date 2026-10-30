import AppKit
import SwiftUI

// The Overview page, sixth take. Each tile holds one object with some body to it: a glowing curve,
// a clock face, a gauge strewn with replies, a glass of water, activity rings, a cluster of
// spheres, a dot calendar. Light comes from the top left, so spheres, glass and knobs shade alike.
// Hues are the sidebar's; figures sit in the corners with small tinted units; now is a glass knob.

enum Palette {
    static let good = Color.green, bad = Color.red
    static let you = Color.primary.opacity(0.75)
}

private let tile = RoundedRectangle(cornerRadius: 22, style: .continuous)

/// Quarter hours from 08:00; now is 18:00.
private enum Day {
    static let n = 48, now = 40
    static func wave(_ i: Int, _ base: Double, _ amp: Double, _ period: Double, _ phase: Double = 0) -> Double {
        i > now ? 0 : max(0, base + amp * sin(Double(i) / period + phase))
    }
    static let running: [Double] = (0..<n).map { (i: Int) -> Double in
        wave(i, 1.15, 0.8, 5) + (i < 4 ? 0 : wave(i, 0.75, 0.6, 3.6, 1)) + ((22...37).contains(i) ? wave(i, 0.85, 0.4, 2) : 0)
    }
    /// Yesterday up to the same hour, the faint line behind today's.
    static let yesterday: [Double] = (0...now).map { (i: Int) -> Double in
        max(0, 1.3 + 0.7 * sin(Double(i) / 4.4 + 2)) + max(0, 0.6 * sin(Double(i) / 2.7))
    }
    static let wait: [Double] = (0..<n).map { (i: Int) -> Double in
        i > now ? 0 : [10, 13, 23, 25, 33].reduce(0.0) { $0 + max(0, 0.75 - 0.32 * abs(Double(i - $1))) }
    }
    /// When you were at the computer.
    static let present: [Range<Int>] = [2..<8, 15..<20, 29..<31, 36..<41]
    static func clock(_ i: Int) -> String { String(format: "%d:%02d", 8 + i / 4, (i % 4) * 15) }
    /// Centre of column i, so every time strip on the page shares one grid.
    static func x(_ i: Int, _ w: CGFloat) -> CGFloat { w * (CGFloat(i) + 0.5) / CGFloat(n) }
}

/// A widget: the card, its hue as a soft glow from one corner, a sheen along the top.
private struct Tile<Content: View>: View {
    let hue: Color
    var glow: UnitPoint = .topLeading
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) { content }
            .padding(Space.xl + 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    tile.fill(Fill.card)
                    tile.fill(RadialGradient(colors: [hue.opacity(scheme == .dark ? 0.26 : 0.15), hue.opacity(0)],
                                             center: glow, startRadius: 0, endRadius: 360))
                    tile.fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.05 : 0.5), .white.opacity(0)],
                                             startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22)))
                }
                .compositingGroup().shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            }
    }
}
/// A tile's corner label: small, bold, in the tile's hue.
private func corner(_ t: String, _ hue: Color, symbol: String? = nil) -> some View {
    HStack(spacing: Space.xs) {
        if let symbol { Image(systemName: symbol).imageScale(.small) }
        Text(t)
    }
    .font(.ui(.footnote, .bold)).foregroundStyle(hue).lineLimit(1)
}
/// The other corner: a gray lead-in and its value in the hue.
private func note(_ lead: String, _ value: String, _ hue: Color) -> some View {
    (Text(lead).foregroundStyle(.secondary) + Text(value).foregroundStyle(hue))
        .font(.ui(.footnote, .bold).monospacedDigit()).lineLimit(1)
}

/// A figure with its units small and tinted, as on the widgets: "34m", "3.0×", "5.6h".
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
            line + Text(verbatim: run.text)
                .font(run.figure ? .figure(size) : .system(size: (size * 0.46).rounded(), weight: .bold))
                .foregroundStyle(run.figure ? ink : unit)
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
// MARK: - Drawing

private func disc(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }

/// Now: a glass knob lit from the top left, a ring in the hue and two ripples around it.
private func knob(_ ctx: GraphicsContext, _ p: CGPoint, _ hue: Color, _ r: CGFloat = 6) {
    for (k, o) in [(2.6, 0.08), (1.8, 0.16)] { ctx.fill(disc(p, r * k), with: .color(hue.opacity(o))) }
    var lifted = ctx
    lifted.addFilter(.shadow(color: .black.opacity(0.25), radius: 2, y: 1))
    lifted.fill(disc(p, r + 1.5), with: .color(hue))
    ctx.fill(disc(p, r - 0.5), with: .radialGradient(Gradient(colors: [.white, Color(white: 0.86)]),
                                                     center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.3))
}

/// A sphere in the hue, lit from the top left, with a soft shadow under it.
private func sphere(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ hue: Color, dark: Bool) {
    var under = ctx
    under.addFilter(.blur(radius: r * 0.18))
    under.fill(disc(CGPoint(x: c.x, y: c.y + r * 0.12), r * 0.96), with: .color(hue.opacity(0.35)))
    ctx.fill(disc(c, r), with: .color(hue))
    let light = CGPoint(x: c.x - r * 0.38, y: c.y - r * 0.45)
    ctx.fill(disc(c, r), with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0.12), .white.opacity(0)]),
                                               center: light, startRadius: 0, endRadius: r * 1.1))
    ctx.fill(disc(c, r), with: .radialGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0), .black.opacity(dark ? 0.32 : 0.18)]),
                                               center: light, startRadius: 0, endRadius: r * 1.75))
}

/// A line through points, smoothed (Catmull-Rom) so the day reads as a flow, not as steps.
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

/// An arc by sampled points, angles in radians clockwise from twelve o'clock.
private func arc(_ c: CGPoint, _ r: CGFloat, _ a: Double, _ b: Double) -> Path {
    var p = Path()
    let steps = max(2, Int(abs(b - a) * 40))
    for k in 0...steps {
        let t = a + (b - a) * Double(k) / Double(steps)
        let q = CGPoint(x: c.x + r * CGFloat(sin(t)), y: c.y - r * CGFloat(cos(t)))
        if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
    }
    return p
}
private func at(_ c: CGPoint, _ r: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a))) }

/// A small glass pill pinned above a point: the callout for the one value a chart is about.
private func pill(_ ctx: GraphicsContext, _ text: Text, above p: CGPoint, within w: CGFloat, dark: Bool) {
    let label = ctx.resolve(text), s = label.measure(in: CGSize(width: 300, height: 40))
    let box = CGRect(x: min(max(p.x - s.width / 2 - 8, 0), w - s.width - 16), y: p.y - s.height - 20, width: s.width + 16, height: s.height + 8)
    var lifted = ctx
    lifted.addFilter(.shadow(color: .black.opacity(0.12), radius: 4, y: 1))
    lifted.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(dark ? Color(white: 0.24) : .white))
    ctx.draw(label, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
}
// MARK: - Page

struct OverviewPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top) {
                PageHeader(title: "概览", symbol: "chart.xyaxis.line", tint: .accentColor, lead: "10月27日 周一 · 6 个会话 · 41 轮")
                Spacer()
                HStack(spacing: Space.xs) {
                    IconButton(symbol: "chevron.left", help: "") {}
                    IconButton(symbol: "chevron.right", help: "") {}.opacity(0.3)
                    Segmented(items: [(0, "日"), (1, "周"), (2, "月")], selection: .constant(0)).padding(.leading, Space.m)
                }
                .padding(.top, Space.xs)
            }
            .padding(.bottom, Space.m)
            Leverage().frame(height: 276)
            HStack(spacing: Space.l) { Waiting().frame(width: 318); Replies(); Away().frame(width: 216) }.frame(height: 236)
            HStack(spacing: Space.l) { Agents().frame(width: 404); Projects() }.frame(height: 216)
            Rhythm().frame(height: 206)
            Ledger()
            lanes
        }
        .padding(.horizontal, 40).padding(.top, 36).padding(.bottom, 32)
    }

    private var lanes: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "chevron.right").font(.ui(.caption, .bold)).foregroundStyle(.tertiary)
            Text("会话明细").font(.ui(.body, .semibold))
            Text("6 个会话").font(.ui(.footnote)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Space.xl).frame(height: 46).surface(tile)
    }
}

// MARK: - Leverage

/// The output: leverage large on the left; on the right the day as a glowing curve of how many
/// agents ran, yesterday's faint behind it, your time at the computer as soft bands, now a knob.
private struct Leverage: View {
    var body: some View {
        Tile(hue: Brand.green) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 0) {
                    corner("杠杆", Brand.green, symbol: "bolt.fill")
                    Fig("3.0×", 96, unit: Brand.green).padding(.top, Space.s)
                    Badge(text: "↑ 0.4× 比昨天同期", tint: Palette.good, compact: true)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: Space.xxl + Space.xs) {
                        pair("9.6h", "agent 在干")
                        pair("3.2h", "你在电脑前")
                    }
                }
                .frame(width: 214, alignment: .leading)
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.l) {
                        corner("同时在跑", .secondary)
                        Spacer()
                        key("今天") { Capsule().fill(LinearGradient(colors: [Brand.lime, Brand.green], startPoint: .leading, endPoint: .trailing)).frame(width: 14, height: 3) }
                        key("昨天") { Capsule().fill(Color.primary.opacity(0.25)).frame(width: 14, height: 2) }
                        key("你在电脑前") { RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.1)).frame(width: 10, height: 10) }
                    }
                    DayCurve().frame(maxHeight: .infinity)
                    Axis().frame(height: 12)
                }
            }
        }
    }

    private func pair(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Fig(v, 26)
            Text(t).font(.ui(.caption, .medium)).foregroundStyle(.secondary)
        }
    }
    private func key(_ label: String, @ViewBuilder _ swatch: () -> some View) -> some View {
        HStack(spacing: Space.xs) { swatch(); Text(label).font(.ui(.caption, .medium)).foregroundStyle(.secondary) }
    }
}
private struct DayCurve: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { ctx, size in
            let dark = scheme == .dark, top = 4.4, base = size.height - 2
            func y(_ v: Double) -> CGFloat { base - (base - 26) * CGFloat(v / top) }
            func pt(_ i: Int, _ v: Double) -> CGPoint { CGPoint(x: Day.x(i, size.width), y: y(v)) }
            let half = size.width / CGFloat(Day.n) / 2
            // Your time at the computer: soft bands rising from the floor.
            for r in Day.present {
                let a = Day.x(r.lowerBound, size.width) - half, b = Day.x(r.upperBound - 1, size.width) + half
                let band = Path(roundedRect: CGRect(x: a, y: 18, width: b - a, height: base - 18), cornerRadius: 6)
                ctx.fill(band, with: .linearGradient(Gradient(colors: [.primary.opacity(0), .primary.opacity(dark ? 0.08 : 0.055)]),
                                                     startPoint: CGPoint(x: 0, y: 18), endPoint: CGPoint(x: 0, y: base)))
            }
            // Levels, as dotted rows labelled at the right where the day has not happened yet.
            for v in [1, 2, 3] {
                var row = Path(); row.move(to: CGPoint(x: 0, y: y(Double(v)))); row.addLine(to: CGPoint(x: size.width - 14, y: y(Double(v))))
                ctx.stroke(row, with: .color(.primary.opacity(0.1)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 5]))
                ctx.draw(Text("\(v)").font(.figure(9, .semibold)).foregroundStyle(.tertiary), at: CGPoint(x: size.width, y: y(Double(v))), anchor: .trailing)
            }
            var floor = Path(); floor.move(to: CGPoint(x: Day.x(Day.now, size.width), y: base)); floor.addLine(to: CGPoint(x: size.width, y: base))
            ctx.stroke(floor, with: .color(.primary.opacity(0.18)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 5]))

            let yday = smooth(Day.yesterday.enumerated().map { pt($0.offset, $0.element) })
            ctx.stroke(yday, with: .color(.primary.opacity(dark ? 0.22 : 0.18)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            let pts = (0...Day.now).map { pt($0, Day.running[$0]) }, line = smooth(pts)
            var area = line
            area.addLine(to: CGPoint(x: pts.last!.x, y: base)); area.addLine(to: CGPoint(x: pts[0].x, y: base)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [Brand.green.opacity(dark ? 0.4 : 0.3), Brand.lime.opacity(0.02)]),
                                                 startPoint: CGPoint(x: 0, y: y(top * 0.85)), endPoint: CGPoint(x: 0, y: base)))
            let ink = GraphicsContext.Shading.linearGradient(Gradient(colors: [Brand.lime, Brand.green]),
                                                              startPoint: .zero, endPoint: CGPoint(x: pts.last!.x, y: 0))
            var glow = ctx
            glow.addFilter(.blur(radius: 5))
            glow.stroke(line, with: .color(Brand.green.opacity(0.55)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            ctx.stroke(line, with: ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            // The busiest moment, called out; now, dropped to the floor.
            let peak = (0...Day.now).max { Day.running[$0] < Day.running[$1] }!
            let pp = pt(peak, Day.running[peak])
            ctx.fill(disc(pp, 3.5), with: .color(dark ? Color(white: 0.2) : .white))
            ctx.fill(disc(pp, 2), with: .color(Brand.green))
            pill(ctx, Text("最忙 ").font(.ui(.caption, .bold)).foregroundStyle(.secondary)
                    + Text("\(Day.clock(peak)) · \(String(format: "%.1f", Day.running[peak])) 个").font(.ui(.caption, .bold).monospacedDigit()).foregroundStyle(Brand.green),
                 above: pp, within: size.width, dark: dark)
            let np = pts.last!
            var drop = Path(); drop.move(to: CGPoint(x: np.x, y: np.y + 8)); drop.addLine(to: CGPoint(x: np.x, y: base))
            ctx.stroke(drop, with: .color(Brand.green.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))
            knob(ctx, np, Brand.green, 6)
        }
    }
}

private struct Axis: View {
    var body: some View {
        GeometryReader { g in
            ForEach([(0, "8:00"), (12, "11:00"), (24, "14:00"), (Day.now, "现在"), (Day.n - 1, "20:00")], id: \.0) { i, t in
                Text(t).font(i == Day.now ? .ui(.caption, .bold) : .figure(10, .semibold))
                    .foregroundStyle(i == Day.now ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)).fixedSize()
                    .position(x: min(max(Day.x(i, g.size.width), 12), g.size.width - 14), y: 6)
            }
        }
    }
}
// MARK: - Waiting

/// Where you held the agents up: the working day as a clock face, 8:00 at the top round to 20:00,
/// red where they waited (deeper the longer), a thin ring for your time at the computer, the hours
/// still to come dotted, now a knob, the total in the middle.
private struct Waiting: View {
    var body: some View {
        Tile(hue: .red) {
            HStack {
                corner("agent 在等你", .red, symbol: "hand.raised.fill")
                Spacer()
                Badge(text: "↓ 9m", tint: Palette.good, compact: true)
            }
            HStack(alignment: .center, spacing: Space.l) {
                ZStack {
                    WaitDial()
                    VStack(spacing: 0) {
                        Fig("34m", 34, ink: .red, unit: .red.opacity(0.7))
                        Text("今天共等").font(.ui(.micro, .semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 164, height: 164)
                VStack(alignment: .leading, spacing: Space.l) {
                    part("22m", "你离开时", Color.red)
                    part("6m", "全部停工", Color.red.opacity(0.45))
                    part("5次", "最长 9m", Color.primary.opacity(0.2))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func part(_ v: String, _ t: String, _ dot: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Circle().fill(dot).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            VStack(alignment: .leading, spacing: 0) {
                Fig(v, 20)
                Text(t).font(.ui(.caption, .medium)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WaitDial: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), R = min(size.width, size.height) / 2 - 8
            func ang(_ i: Double) -> Double { 2 * .pi * i / Double(Day.n) }
            let nowA = ang(Double(Day.now) + 0.5)
            // The face: past as a quiet track, the hours to come as dots.
            ctx.stroke(arc(c, R, 0, nowA), with: .color(.primary.opacity(0.07)), style: StrokeStyle(lineWidth: 11, lineCap: .round))
            ctx.stroke(arc(c, R, nowA + 0.18, 2 * .pi - 0.05), with: .color(.primary.opacity(0.2)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.1, 6]))
            // Your time at the computer, a thin ring inside.
            for r in Day.present {
                ctx.stroke(arc(c, R - 12, ang(Double(r.lowerBound)), ang(Double(r.upperBound))), with: .color(Palette.you.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            // Hour marks, every hour a dot and every three a figure.
            for h in 0...12 where h < 12 {
                let a = ang(Double(h * 4)), q = at(c, R - 21, a)
                if h % 3 == 0 {
                    ctx.draw(Text("\(8 + h)").font(.figure(9, .bold)).foregroundStyle(.tertiary), at: q, anchor: .center)
                } else {
                    ctx.fill(disc(q, 1), with: .color(.primary.opacity(0.22)))
                }
            }
            // The waits: one arc each, glowing, its red as deep as the wait was long.
            var spans: [ClosedRange<Int>] = [], open: Int?
            for i in 0...Day.now {
                if Day.wait[i] > 0.05 { if open == nil { open = i } } else if let o = open { spans.append(o...(i - 1)); open = nil }
            }
            if let o = open { spans.append(o...Day.now) }
            for s in spans {
                let a = ang(Double(s.lowerBound)), b = ang(Double(s.upperBound + 1)), path = arc(c, R, a, b)
                let peak = s.map { Day.wait[$0] }.max() ?? 0
                var glow = ctx
                glow.addFilter(.blur(radius: 4))
                glow.stroke(path, with: .color(.red.opacity(0.5 * min(1, peak / 0.75))), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                ctx.stroke(path, with: .color(.red.opacity(0.4 + 0.6 * min(1, peak / 0.75))), style: StrokeStyle(lineWidth: 11, lineCap: .round))
            }
            knob(ctx, at(c, R, nowA), .red, 5.5)
        }
    }
}
// MARK: - Replies

/// How fast you answer: a gauge from 10s to 5m on a log scale, a bead for every reply today, the
/// middle half lit as a beam from the centre, the slow tail red, the median the knob.
private struct Replies: View {
    /// Today's replies in seconds, spread like real ones: most under a minute and a half, a long tail.
    static let replies: [Double] = (0..<38).map { (k: Int) -> Double in
        let u = (Double(k) * 0.618034).truncatingRemainder(dividingBy: 1)
        return 10 * pow(30, min(0.98, 0.02 + pow(u, 1.25) * 0.98))
    }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Tile(hue: .orange, glow: .bottom) {
            HStack {
                corner("回复速度", .orange, symbol: "arrowshape.turn.up.left.fill")
                Spacer()
                Badge(text: "↓ 12s", tint: Palette.good, compact: true)
            }
            Canvas { ctx, size in
                let R = min(size.width / 2 - 14, size.height - 34), c = CGPoint(x: size.width / 2, y: size.height - 20)
                func t(_ s: Double) -> Double { max(0, min(1, log(s / 10) / log(30.0))) }
                func a(_ s: Double) -> Double { -.pi / 2 + .pi * t(s) }
                // The beam: the middle half of your replies, lit from the centre.
                var beam = arc(c, R - 6, a(25), a(90)); beam.addLine(to: c); beam.closeSubpath()
                ctx.fill(beam, with: .radialGradient(Gradient(colors: [.orange.opacity(0), .orange.opacity(scheme == .dark ? 0.32 : 0.22)]),
                                                     center: c, startRadius: R * 0.25, endRadius: R))
                let thick = StrokeStyle(lineWidth: 13, lineCap: .round)
                ctx.stroke(arc(c, R, -.pi / 2, .pi / 2), with: .color(.primary.opacity(0.07)), style: thick)
                ctx.stroke(arc(c, R, a(180), .pi / 2), with: .color(.red.opacity(0.3)), style: thick)
                var glow = ctx
                glow.addFilter(.blur(radius: 5))
                glow.stroke(arc(c, R, a(25), a(90)), with: .color(.orange.opacity(0.6)), style: thick)
                ctx.stroke(arc(c, R, a(25), a(90)), with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.72, blue: 0.3), .orange]),
                                                                       startPoint: at(c, R, a(25)), endPoint: at(c, R, a(90))), style: thick)
                // A bead for every reply, scattered across the band.
                for (k, s) in Self.replies.enumerated() {
                    let jitter = CGFloat((Double(k) * 0.754877).truncatingRemainder(dividingBy: 1) - 0.5) * 7
                    let q = at(c, R + jitter, a(s))
                    let lit = s >= 25 && s <= 90
                    ctx.fill(disc(q, 1.6), with: .color(lit ? .white.opacity(0.9) : s > 180 ? .red : .orange.opacity(0.75)))
                }
                for (s, label) in [(10.0, "10s"), (300.0, "5m")] {
                    ctx.draw(Text(label).font(.figure(9, .semibold)).foregroundStyle(.tertiary), at: CGPoint(x: at(c, R, a(s)).x, y: c.y + 9), anchor: .top)
                }
                knob(ctx, at(c, R, a(48)), .orange, 6)
                ctx.draw(Fig("48s", 36).line, at: CGPoint(x: c.x, y: c.y + 4), anchor: .bottom)
                ctx.draw(Text("中位").font(.ui(.caption, .bold)).foregroundStyle(.secondary), at: CGPoint(x: c.x, y: c.y + 9), anchor: .top)
            }
            .frame(maxHeight: .infinity)
            HStack {
                note("慢的一成 ", "> 4m", .red)
                Spacer()
                note("今天 ", "38 次", .orange)
            }
        }
    }
}
// MARK: - Away

/// While you were away: a glass, the share the agents kept working as water in it with bubbles
/// rising, the headroom left over tinted red for the time they sat stuck.
private struct Away: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Tile(hue: .blue, glow: .bottom) {
            HStack {
                corner("你不在时", .blue, symbol: "figure.walk")
                Spacer()
                note("离开 ", "2.0h", .blue)
            }
            Canvas { ctx, size in
                let dark = scheme == .dark, r = min(size.width, size.height) / 2 - 2
                let c = CGPoint(x: size.width / 2, y: size.height / 2), ball = disc(c, r), level = 0.81
                ctx.fill(ball, with: .color(.primary.opacity(dark ? 0.06 : 0.04)))
                ctx.fill(ball, with: .radialGradient(Gradient(colors: [.red.opacity(0), .red.opacity(0.16)]), center: c, startRadius: r * 0.6, endRadius: r))
                var water = ctx
                water.clip(to: ball)
                let sea = c.y + r - 2 * r * CGFloat(level)
                func wave(_ dy: CGFloat, _ phase: Double) -> Path {
                    var p = Path(); p.move(to: CGPoint(x: c.x - r, y: c.y + r))
                    for k in 0...40 {
                        let x = c.x - r + 2 * r * CGFloat(k) / 40
                        p.addLine(to: CGPoint(x: x, y: sea + dy + 3 * CGFloat(sin(Double(k) / 40 * 2 * .pi * 1.5 + phase))))
                    }
                    p.addLine(to: CGPoint(x: c.x + r, y: c.y + r)); p.closeSubpath()
                    return p
                }
                water.fill(wave(-2, 2.2), with: .color(.blue.opacity(0.3)))
                water.fill(wave(0, 0), with: .linearGradient(Gradient(colors: [Color(red: 0.35, green: 0.68, blue: 1), .blue]),
                                                             startPoint: CGPoint(x: 0, y: sea), endPoint: CGPoint(x: 0, y: c.y + r)))
                for (dx, dy, br) in [(-0.62, 0.3, 3.0), (0.6, 0.38, 2.5), (-0.34, 0.74, 2.0), (0.3, 0.76, 1.8), (0.64, -0.18, 1.6), (-0.6, -0.26, 1.6)] {
                    water.stroke(disc(CGPoint(x: c.x + r * CGFloat(dx), y: c.y + r * CGFloat(dy)), CGFloat(br)), with: .color(.white.opacity(0.55)), lineWidth: 1)
                }
                // The glass: a highlight at the top left and a rim of light.
                ctx.fill(ball, with: .radialGradient(Gradient(colors: [.white.opacity(dark ? 0.22 : 0.5), .white.opacity(0)]),
                                                     center: CGPoint(x: c.x - r * 0.4, y: c.y - r * 0.5), startRadius: 0, endRadius: r * 0.7))
                ctx.stroke(arc(c, r - 3, -2.2, -0.9), with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                ctx.draw(Fig("81%", 36, ink: .white, unit: .white.opacity(0.8)).line, at: CGPoint(x: c.x, y: c.y + r * 0.2), anchor: .center)
                ctx.draw(Text("仍在干活").font(.ui(.caption, .bold)).foregroundStyle(.white.opacity(0.85)), at: CGPoint(x: c.x, y: c.y + r * 0.2 + 22), anchor: .center)
            }
            .frame(maxHeight: .infinity)
            HStack {
                note("干活 ", "1.6h", .blue)
                Spacer()
                note("卡住 ", "22m", .red)
            }
        }
    }
}
// MARK: - Agents

/// Who did the work: a ring each, nested, filled to its share of the hours with a bright tip, the
/// total in the middle and a key beside.
private struct Agents: View {
    let rows: [(logo: String, name: String, hours: String, share: Double, turns: Int)] = [
        ("claudecode", "Claude Code", "5.6h", 0.58, 24), ("codex", "Codex", "3.0h", 0.31, 13), ("cursor", "Cursor", "1.0h", 0.11, 4),
    ]
    private let width: CGFloat = 12, gap: CGFloat = 4

    var body: some View {
        Tile(hue: .blue) {
            HStack {
                corner("谁在干", .blue, symbol: "person.2.fill")
                Spacer()
                note("最卖力 ", "Claude Code", .blue)
            }
            HStack(spacing: Space.xxl) {
                ZStack {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in ring(i, r.share) }
                    VStack(spacing: 0) {
                        Fig("9.6h", 22)
                        Text("合计").font(.ui(.micro, .semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: Space.l) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        HStack(spacing: Space.m) {
                            Logo(name: r.logo, size: 14, ink: .white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(LinearGradient(colors: [tone(i).opacity(0.8), tone(i)], startPoint: .top, endPoint: .bottom)))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(r.name).font(.ui(.footnote, .semibold)).lineLimit(1)
                                Text("\(Int(r.share * 100))% · \(r.turns) 轮").font(.ui(.caption, .medium).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Space.s)
                            Fig(r.hours, 20)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func tone(_ i: Int) -> Color { Color.blue.opacity(1 - 0.28 * Double(i)) }

    private func ring(_ i: Int, _ share: Double) -> some View {
        let d = 140 - CGFloat(i) * 2 * (width + gap) - width
        return ZStack {
            Circle().stroke(Color.blue.opacity(0.1), lineWidth: width)
            Circle().trim(from: 0, to: share)
                .stroke(AngularGradient(colors: [tone(i).opacity(0.55), tone(i)], center: .center, startAngle: .zero, endAngle: .degrees(360 * share)),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .shadow(color: Color.blue.opacity(0.35), radius: 3)
            Circle().fill(.white).frame(width: 5, height: 5).offset(y: -d / 2).rotationEffect(.degrees(360 * share + 90))
        }
        .rotationEffect(.degrees(-90))
        .frame(width: d, height: d)
    }
}
// MARK: - Projects

/// Where the work went: a sphere a project, its size its hours, nestled together; a red bead on
/// each rim, as large as the time that project waited for you.
private struct Projects: View {
    let rows: [(name: String, hours: Double, waited: Double)] = [("YaaKanban", 5.6, 18), ("artrix-skills", 2.6, 4), ("wave-patch", 1.4, 12)]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Tile(hue: .green, glow: .topTrailing) {
            HStack {
                corner("在哪干", .green, symbol: "folder.fill")
                Spacer()
                note("3 个项目 · 等你 ", "34m", .red)
            }
            Canvas { ctx, size in
                let dark = scheme == .dark, k = min(size.height / 2 - 4, 80) / CGFloat(5.6).squareRoot()
                let r = rows.map { CGFloat($0.hours).squareRoot() * k }
                // Each sphere sits against the last: the first centred, the second against the top, the third the floor.
                var c = [CGPoint(x: r[0], y: size.height / 2)]
                for (i, y) in [(1, r[1] + 2), (2, size.height - r[2] - 2)] {
                    let d = r[i - 1] + r[i] + 3, dy = y - c[i - 1].y
                    c.append(CGPoint(x: c[i - 1].x + (d * d - dy * dy).squareRoot(), y: y))
                }
                let shift = (size.width - (c[2].x + r[2])) / 2
                c = c.map { CGPoint(x: $0.x + shift, y: $0.y) }
                for i in rows.indices { sphere(ctx, c[i], r[i], Color.green, dark: dark) }
                for (i, row) in rows.enumerated() {
                    let big = i == 0
                    ctx.draw(Fig(String(format: "%.1fh", row.hours), big ? 30 : 20, ink: .white, unit: .white.opacity(0.8)).line,
                             at: CGPoint(x: c[i].x, y: c[i].y + (big ? 2 : 1)), anchor: .bottom)
                    ctx.draw(Text(row.name).font(.ui(big ? .footnote : .caption, .bold)).foregroundStyle(.white.opacity(0.9)),
                             at: CGPoint(x: c[i].x, y: c[i].y + (big ? 4 : 3)), anchor: .top)
                    // The bead for its wait, on the rim away from its neighbours.
                    let a = [-2.4, -2.2, 0.75][i], br = 3 + CGFloat(row.waited) / 3
                    let b = CGPoint(x: c[i].x + (r[i] + br * 0.2) * CGFloat(cos(a)), y: c[i].y + (r[i] + br * 0.2) * CGFloat(sin(a)))
                    var lifted = ctx
                    lifted.addFilter(.shadow(color: .red.opacity(0.4), radius: 3))
                    lifted.fill(disc(b, br), with: .color(.red))
                    ctx.fill(disc(b, br), with: .radialGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0)]),
                                                                center: CGPoint(x: b.x - br * 0.35, y: b.y - br * 0.4), startRadius: 0, endRadius: br))
                    let out = CGPoint(x: b.x + (br + 4) * CGFloat(cos(a)), y: b.y + (br + 4) * CGFloat(sin(a)))
                    ctx.draw(Text("\(Int(row.waited))m").font(.figure(11, .bold)).foregroundStyle(.red), at: out,
                             anchor: cos(a) < 0 ? .trailing : .leading)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Rhythm

/// The week's rhythm: a cell a half hour from 8:00, a row a day, lit in indigo by how many agents ran; today
/// last, its hours to come hollow, now a knob; each day's hours at the end of its row.
private struct Rhythm: View {
    let days = ["二", "三", "四", "五", "六", "日", "今"]
    let totals = ["8.4h", "11.2h", "9.1h", "7.8h", "2.6h", "1.9h", "9.6h"]
    var body: some View {
        Tile(hue: .indigo, glow: .bottomTrailing) {
            HStack {
                corner("本周节奏", .indigo, symbol: "square.grid.3x3.fill")
                Spacer()
                note("最忙 ", "周三下午", .indigo)
            }
            Canvas { ctx, size in
                let cols = 32, rows = 7, label: CGFloat = 20, tail: CGFloat = 52, axis: CGFloat = 16, nowCol = 20
                let pitch = (size.width - label - tail) / CGFloat(cols), row = (size.height - axis) / CGFloat(rows), d = row - 3, dw = pitch - 3
                let left = label
                for r in 0..<rows {
                    let y = CGFloat(r) * row, today = r == rows - 1
                    ctx.draw(Text(days[r]).font(.ui(.caption, today ? .bold : .medium)).foregroundStyle(today ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)),
                             at: CGPoint(x: 0, y: y + d / 2), anchor: .leading)
                    for col in 0..<cols {
                        let rect = CGRect(x: left + CGFloat(col) * pitch, y: y, width: dw, height: d), shape = Path(roundedRect: rect, cornerRadius: d * 0.32)
                        if today, col > nowCol {
                            ctx.stroke(shape, with: .color(.indigo.opacity(0.25)), lineWidth: 1)
                            continue
                        }
                        let v = level(r, col)
                        ctx.fill(shape, with: .color(v < 0.12 ? Color.primary.opacity(0.06) : Color.indigo.opacity(0.18 + 0.82 * v)))
                    }
                    ctx.draw(Fig(totals[r], 13, ink: today ? .indigo : .primary).line, at: CGPoint(x: size.width, y: y + d / 2), anchor: .trailing)
                }
                knob(ctx, CGPoint(x: left + CGFloat(nowCol) * pitch + dw / 2, y: CGFloat(rows - 1) * row + d / 2), .indigo, 4.5)
                for (col, t) in [(0, "8:00"), (8, "12:00"), (16, "16:00"), (24, "20:00"), (31, "24:00")] {
                    ctx.draw(Text(t).font(.figure(9, .semibold)).foregroundStyle(.tertiary),
                             at: CGPoint(x: left + CGFloat(col) * pitch + (col == 31 ? dw : 0), y: CGFloat(rows) * row + 4), anchor: col == 31 ? .topTrailing : .topLeading)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Made-up but plausible: mornings and afternoons, a dip at lunch, quiet weekends, a busy Wednesday.
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

/// Every other figure as a chip, the way the board's small capsules sit beside the big widgets.
private struct Ledger: View {
    let cells: [(symbol: String, hue: Color, title: String, value: String, delta: String?, good: Bool)] = [
        ("square.stack.3d.up.fill", .blue, "同时在跑", "2.4个", "↑ 0.3", true),
        ("gauge.with.needle.fill", .green, "利用率", "86%", "↑ 4%", true),
        ("arrow.uturn.left", .orange, "接手速度", "3m40s", "↑ 50s", false),
        ("hand.point.up.left.fill", .orange, "每次介入", "7m", "↑ 1m", true),
        ("checkmark.seal.fill", .green, "吞吐", "12.8轮/h", "↑ 1.1", true),
        ("timer", .blue, "最长连跑", "47m", "↓ 6m", false),
        ("tray.full.fill", .red, "当前积压", "2个", nil, true),
        ("arrow.left.arrow.right", .gray, "切换", "23次", "↓ 4", true),
        ("wrench.and.screwdriver.fill", .gray, "工具调用", "1,284", "↑ 210", true),
        ("text.word.spacing", .gray, "token", "3.1M", "↑ 0.4M", true),
    ]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.l), count: 5), spacing: Space.l) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                HStack(spacing: Space.m + 2) {
                    Image(systemName: c.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [c.hue.opacity(0.7), c.hue], startPoint: .top, endPoint: .bottom))
                                Circle().fill(RadialGradient(colors: [.white.opacity(0.4), .white.opacity(0)], center: UnitPoint(x: 0.32, y: 0.22), startRadius: 0, endRadius: 16))
                            }
                            .shadow(color: c.hue.opacity(0.35), radius: 3, y: 1)
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Fig(c.value, 20)
                        HStack(spacing: Space.xs) {
                            Text(c.title).font(.ui(.caption, .medium)).foregroundStyle(.secondary).lineLimit(1)
                            if let d = c.delta { Text(d).font(.ui(.caption, .bold).monospacedDigit()).foregroundStyle(c.good ? Palette.good : Palette.bad).fixedSize() }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, Space.s + 1).padding(.vertical, Space.s + 1).padding(.trailing, Space.s)
                .surface(Capsule(style: .continuous))
            }
        }
    }
}

