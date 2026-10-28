import AppKit
import SwiftUI

// The Overview page, fifth take, after the widget board: a wall of tiles, each one idea with its own
// hue and its own picture (capsules, ticks, a gauge, rings, a line, a dot matrix), never a plain
// bar chart. Hues are the sidebar's (brand green, red, orange, blue, green), so the page and the
// session cards speak one language. Figures in the corners, units small and tinted, now a knob.

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
    static let wait: [Double] = (0..<n).map { (i: Int) -> Double in
        i > now ? 0 : [6, 13, 23, 25, 33].reduce(0.0) { $0 + max(0, 0.75 - 0.32 * abs(Double(i - $1))) }
    }
    /// When you were at the computer.
    static let present: [Range<Int>] = [2..<8, 15..<20, 29..<31, 36..<41]
    static func clock(_ i: Int) -> String { String(format: "%d:%02d", 8 + i / 4, (i % 4) * 15) }
    /// Centre of column i, so every time strip on the page shares one grid.
    static func x(_ i: Int, _ w: CGFloat) -> CGFloat { w * (CGFloat(i) + 0.5) / CGFloat(n) }
    static func bar(_ w: CGFloat) -> CGFloat { max(3, (w / CGFloat(n) * 0.52).rounded()) }
}

/// A widget: the card, with its hue as a soft glow from one corner.
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
                    tile.fill(RadialGradient(colors: [hue.opacity(scheme == .dark ? 0.24 : 0.14), hue.opacity(0)],
                                             center: glow, startRadius: 0, endRadius: 340))
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

/// A figure with its units small and tinted, as on the widgets: "34m", "3.0×", "5.6h".
private struct Fig: View {
    let text: String
    var size: CGFloat
    var ink: Color = .primary
    var unit: Color = .secondary

    init(_ text: String, _ size: CGFloat, ink: Color = .primary, unit: Color = .secondary) {
        self.text = text; self.size = size; self.ink = ink; self.unit = unit
    }

    var body: some View {
        runs.reduce(Text(verbatim: "")) { line, run in
            line + Text(verbatim: run.text)
                .font(run.figure ? .figure(size) : .system(size: (size * 0.46).rounded(), weight: .bold))
                .foregroundStyle(run.figure ? ink : unit)
        }
        .lineLimit(1).fixedSize()
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

/// Now, wherever it sits on a track: a white knob with a ring in the hue.
private func knob(_ ctx: GraphicsContext, _ p: CGPoint, _ hue: Color, _ r: CGFloat = 6) {
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r - 4, y: p.y - r - 4, width: 2 * r + 8, height: 2 * r + 8)), with: .color(hue.opacity(0.22)))
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r - 1.5, y: p.y - r - 1.5, width: 2 * r + 3, height: 2 * r + 3)), with: .color(hue))
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r + 1, y: p.y - r + 1, width: 2 * r - 2, height: 2 * r - 2)), with: .color(.white))
}

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
            Leverage().frame(height: 272)
            HStack(spacing: Space.l) { Waiting(); Replies().frame(width: 270) }.frame(height: 206)
            HStack(spacing: Space.l) { Agents().frame(width: 330); Projects() }.frame(height: 206)
            HStack(spacing: Space.l) { Rhythm(); Away().frame(width: 270) }.frame(height: 214)
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
/// The output: leverage large; on the right, a capsule a quarter hour, as tall as the agents
/// running then, coloured from mint to the brand green by how many; past now, dim; now, a knob.
/// Your own time at the computer runs under them as a line with lit stretches.
private struct Leverage: View {
    var body: some View {
        Tile(hue: Brand.green) {
            HStack(alignment: .top, spacing: 32) {
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
                .frame(width: 220, alignment: .leading)
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack {
                        corner("同时在跑", .secondary)
                        Spacer()
                        Text("最忙 ").font(.ui(.footnote, .bold)).foregroundStyle(.secondary)
                            + Text("9:30 · 3.7 个").font(.ui(.footnote, .bold).monospacedDigit()).foregroundStyle(Brand.green)
                    }
                    Capsules().frame(maxHeight: .infinity)
                    Lane().frame(height: 6).padding(.top, Space.xs)
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
}

private struct Capsules: View {
    var body: some View {
        Canvas { ctx, size in
            let w = Day.bar(size.width), top = 4.2
            func y(_ v: Double) -> CGFloat { size.height - w / 2 - 2 - (size.height - w - 4) * CGFloat(v / top) }
            for i in 0..<Day.n {
                let x = Day.x(i, size.width)
                guard i <= Day.now else {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y(0) - 1.5, width: 3, height: 3)), with: .color(.primary.opacity(0.14)))
                    continue
                }
                // A quarter hour's span, from the fewest to the most agents running in it.
                let hi = Day.running[i], lo = max(0, hi - 0.5 - 0.35 * abs(sin(Double(i) * 1.7)))
                let a = y(hi), b = y(lo)
                let r = CGRect(x: x - w / 2, y: a - w / 2, width: w, height: b - a + w)
                let k = min(1, hi / 3.4)
                ctx.fill(Path(roundedRect: r, cornerRadius: w / 2),
                         with: .linearGradient(Gradient(colors: [Brand.lime.opacity(0.35 + 0.4 * k), Brand.green.opacity(0.45 + 0.55 * k)]),
                                               startPoint: CGPoint(x: 0, y: r.maxY), endPoint: CGPoint(x: 0, y: r.minY)))
                ctx.fill(Path(ellipseIn: CGRect(x: x - w / 2 + 1, y: a - w / 2 + 1, width: w - 2, height: w - 2)), with: .color(.white.opacity(0.85)))
                if i == Day.now { knob(ctx, CGPoint(x: x, y: a), Brand.green, 5) }
            }
        }
    }
}

/// Your time at the computer: a dotted line with lit stretches, on the page's time grid.
private struct Lane: View {
    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2, bw = Day.bar(size.width)
            for i in 0...Day.now {
                ctx.fill(Path(ellipseIn: CGRect(x: Day.x(i, size.width) - 1, y: mid - 1, width: 2, height: 2)), with: .color(.primary.opacity(0.2)))
            }
            for r in Day.present {
                let a = Day.x(r.lowerBound, size.width) - bw / 2, b = Day.x(r.upperBound - 1, size.width) + bw / 2
                ctx.fill(Path(roundedRect: CGRect(x: a, y: 0, width: b - a, height: size.height), cornerRadius: size.height / 2), with: .color(Palette.you))
            }
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
/// Where you held the agents up: the total in red, how it split, and a tick a quarter hour lit by
/// how long they waited then, over your lane, so the lit ticks line up with the time you were away.
private struct Waiting: View {
    var body: some View {
        Tile(hue: .red) {
            HStack {
                corner("agent 在等你", .red, symbol: "hand.raised.fill")
                Spacer()
                Badge(text: "↓ 9m 比昨天同期", tint: Palette.good, compact: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.xxl + Space.xs) {
                Fig("34m", 52, ink: .red, unit: .red.opacity(0.7))
                part("22m", "你离开时")
                part("6m", "全部停工")
            }
            Spacer(minLength: 0)
            Canvas { ctx, size in
                let bw = Day.bar(size.width)
                for i in 0..<Day.n {
                    let v = Day.wait[i], x = Day.x(i, size.width)
                    let r = CGRect(x: x - bw / 2, y: 0, width: bw, height: size.height)
                    let style: Color = i > Day.now ? .primary.opacity(0.05) : v > 0.05 ? .red.opacity(0.3 + 0.7 * min(1, v / 0.75)) : .primary.opacity(0.1)
                    ctx.fill(Path(roundedRect: r, cornerRadius: bw / 2), with: .color(style))
                }
            }
            .frame(height: 30)
            Lane().frame(height: 6).padding(.top, Space.xxs)
            Axis().frame(height: 12)
        }
    }

    private func part(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Fig(v, 20)
            Text(t).font(.ui(.caption, .medium)).foregroundStyle(.secondary)
        }
    }
}

/// How fast you answer: a gauge from 10s to 5m on a log scale, the middle half of your replies lit
/// in orange, the slow tail in red, the median as the knob.
private struct Replies: View {
    var body: some View {
        Tile(hue: .orange, glow: .bottom) {
            HStack {
                corner("回复速度", .orange, symbol: "arrowshape.turn.up.left.fill")
                Spacer()
                Badge(text: "↓ 12s", tint: Palette.good, compact: true)
            }
            ZStack(alignment: .bottom) {
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height - 4), R = min(size.width / 2 - 10, size.height - 12)
                    func t(_ s: Double) -> Double { log(s / 10) / log(30.0) }
                    func p(_ f: Double) -> CGPoint { let a = Double.pi * (1 - f); return CGPoint(x: c.x + R * CGFloat(cos(a)), y: c.y - R * CGFloat(sin(a))) }
                    func arc(_ a: Double, _ b: Double) -> Path {
                        var path = Path(); path.move(to: p(a))
                        for k in 1...60 { path.addLine(to: p(a + (b - a) * Double(k) / 60)) }
                        return path
                    }
                    let thick = StrokeStyle(lineWidth: 12, lineCap: .round)
                    ctx.stroke(arc(0, 1), with: .color(.primary.opacity(0.08)), style: thick)
                    ctx.stroke(arc(t(180), 1), with: .color(.red.opacity(0.35)), style: thick)
                    ctx.stroke(arc(t(25), t(90)), with: .color(.orange), style: thick)
                    for k in 0...10 {
                        let f = Double(k) / 10, q = p(f), o = CGPoint(x: c.x + (q.x - c.x) * 0.82, y: c.y + (q.y - c.y) * 0.82)
                        ctx.fill(Path(ellipseIn: CGRect(x: o.x - 1, y: o.y - 1, width: 2, height: 2)), with: .color(.primary.opacity(0.25)))
                    }
                    knob(ctx, p(t(48)), .orange, 6)
                    ctx.draw(Text("10s").font(.figure(9, .semibold)).foregroundStyle(.tertiary), at: CGPoint(x: c.x - R, y: c.y + 2), anchor: .top)
                    ctx.draw(Text("5m").font(.figure(9, .semibold)).foregroundStyle(.tertiary), at: CGPoint(x: c.x + R, y: c.y + 2), anchor: .top)
                }
                VStack(spacing: 0) {
                    Fig("48s", 34)
                    Text("中位 · P90 4m").font(.ui(.caption, .medium)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
            }
        }
    }
}
/// Who did the work: a ring each, filled to its share, the logo inside.
private struct Agents: View {
    let rows: [(logo: String, name: String, hours: String, share: Double)] = [
        ("claudecode", "Claude Code", "5.6h", 0.58), ("codex", "Codex", "3.0h", 0.31), ("cursor", "Cursor", "1.0h", 0.11),
    ]
    var body: some View {
        Tile(hue: .blue) {
            HStack {
                corner("谁在干", .blue, symbol: "person.2.fill")
                Spacer()
                Text("最卖力 ").font(.ui(.footnote, .bold)).foregroundStyle(.secondary) + Text("Claude Code").font(.ui(.footnote, .bold)).foregroundStyle(.blue)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    VStack(spacing: Space.s) {
                        ZStack {
                            Circle().stroke(Color.blue.opacity(0.12), lineWidth: 7)
                            Circle().trim(from: 0, to: r.share).stroke(Color.blue.opacity(1 - 0.25 * Double(i)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Logo(name: r.logo, size: 22, ink: .primary)
                        }
                        .frame(width: 66, height: 66)
                        Fig(r.hours, 20)
                        Text(r.name).font(.ui(.caption, .medium)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Where the work went: one line, a stretch for each project as long as its hours, a station at
/// each start, and how long it waited for you under it.
private struct Projects: View {
    let rows: [(name: String, hours: String, share: Double, waited: String)] = [
        ("YaaKanban", "5.6h", 0.58, "18m"), ("artrix-skills", "2.6h", 0.27, "4m"), ("wave-patch", "1.4h", 0.15, "12m"),
    ]
    /// Drawn widths: the shares, with a floor so the shortest still holds its label.
    let widths: [Double] = [0.52, 0.26, 0.22

    ]
    var body: some View {
        Tile(hue: .green, glow: .topTrailing) {
            HStack {
                corner("在哪干", .green, symbol: "folder.fill")
                Spacer()
                Text("3 个项目").font(.ui(.footnote, .bold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            GeometryReader { g in
                let gap: CGFloat = 4, w = g.size.width - gap * CGFloat(rows.count - 1)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        VStack(alignment: .leading, spacing: Space.m) {
                            Capsule().fill(Color.green.opacity(1 - 0.3 * Double(i)))
                                .overlay(alignment: .leading) { Circle().fill(.white).frame(width: 8, height: 8).padding(.leading, 4) }
                                .frame(height: 16)
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Fig(r.hours, 26)
                                Text(r.name).font(.ui(.footnote, .semibold)).lineLimit(1)
                                (Text("等你 ") + Text(r.waited).foregroundStyle(.red)).font(.ui(.caption, .medium)).foregroundStyle(.secondary)
                            }
                            .padding(.leading, 2)
                        }
                        .frame(width: w * widths[i])
                    }
                }
            }
            .frame(height: 98)
            Spacer(minLength: 0)
        }
    }
}
/// The week's rhythm: a dot a half hour, a row a day, lit in blue by how many agents ran; today's
/// row last and in full, its hours to come as empty rings.
private struct Rhythm: View {
    let days = ["二", "三", "四", "五", "六", "日", "今"]
    var body: some View {
        Tile(hue: .indigo, glow: .bottomTrailing) {
            HStack {
                corner("本周节奏", .indigo, symbol: "square.grid.3x3.fill")
                Spacer()
                Text("最忙 ").font(.ui(.footnote, .bold)).foregroundStyle(.secondary) + Text("周三下午").font(.ui(.footnote, .bold)).foregroundStyle(.indigo)
            }
            Spacer(minLength: 0)
            Canvas { ctx, size in
                let cols = 24, rows = 7, label: CGFloat = 18
                let pitch = min((size.width - label) / CGFloat(cols), size.height / CGFloat(rows)), d = pitch - 3
                for r in 0..<rows {
                    let y = CGFloat(r) * pitch
                    ctx.draw(Text(days[r]).font(.ui(.caption, r == 6 ? .bold : .medium)).foregroundStyle(r == 6 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)),
                             at: CGPoint(x: 0, y: y + d / 2), anchor: .leading)
                    for c in 0..<cols {
                        let rect = CGRect(x: label + CGFloat(c) * pitch, y: y, width: d, height: d)
                        let shape = Path(roundedRect: rect, cornerRadius: d * 0.3)
                        if r == 6, c > 20 { ctx.stroke(shape.strokedPath(StrokeStyle(lineWidth: 1)), with: .color(.indigo.opacity(0.3))); continue }
                        let weekend = r == 4 || r == 5
                        let v = max(0, sin(Double(c) / 3.6 + Double(r)) * 0.55 + 0.45 - (weekend ? 0.45 : 0) + (r == 1 && (12...17).contains(c) ? 0.45 : 0))
                        let o = v < 0.15 ? 0.08 : 0.2 + 0.8 * min(1, v)
                        ctx.fill(shape, with: .color(v < 0.15 ? Color.primary.opacity(0.06) : Color.indigo.opacity(o)))
                    }
                }
            }
            .frame(height: 140)
        }
    }
}

/// While you were away: a capsule for the time, split into the agents working and the agents stuck.
private struct Away: View {
    var body: some View {
        Tile(hue: .blue, glow: .bottom) {
            corner("你不在时", .blue, symbol: "figure.walk")
            Fig("81%", 52, ink: .blue, unit: .blue.opacity(0.7))
            Text("agent 仍在干活").font(.ui(.callout, .medium)).foregroundStyle(.secondary).padding(.top, -Space.s)
            Spacer(minLength: 0)
            GeometryReader { g in
                HStack(spacing: 3) {
                    Capsule().fill(Color.blue).frame(width: (g.size.width - 6) * 0.81)
                    Capsule().fill(Color.red)
                    Capsule().fill(Color.primary.opacity(0.1)).frame(width: 10)
                }
            }
            .frame(height: 14)
            HStack {
                Text("干活 ").foregroundStyle(.secondary) + Text("1.6h").font(.figure(13, .bold))
                Spacer()
                Text("卡住 ").foregroundStyle(.secondary) + Text("22m").font(.figure(13, .bold)).foregroundStyle(.red)
            }
            .font(.ui(.caption, .medium))
        }
    }
}

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
                    Image(systemName: c.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(c.hue)
                        .frame(width: 34, height: 34).background(c.hue.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Fig(c.value, 20)
                        HStack(spacing: Space.xs) {
                            Text(c.title).font(.ui(.caption, .medium)).foregroundStyle(.secondary).lineLimit(1)
                            if let d = c.delta { Text(d).font(.ui(.caption, .bold).monospacedDigit()).foregroundStyle(c.good ? Palette.good : Palette.bad).fixedSize() }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, Space.m).padding(.vertical, Space.m).padding(.trailing, Space.s)
                .surface(Capsule(style: .continuous))
            }
        }
    }
}
