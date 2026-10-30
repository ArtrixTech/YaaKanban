import AppKit
import SwiftUI

// The Overview page, second take: one story told top to bottom. A headline says how the day went,
// a dark hero shows the output (leverage, and the agents running while you came and went), then
// where you held them up, who did the work and where, and every other figure in one ledger.

/// A tuned palette in place of the system's stock hues: matched in brightness, so no series shouts.
enum Palette {
    static let claude = Color(red: 1.0, green: 0.55, blue: 0.36)   // coral
    static let codex = Color(red: 0.26, green: 0.8, blue: 0.86)    // cyan
    static let cursor = Color(red: 0.6, green: 0.5, blue: 1.0)     // violet
    static let wait = Color(red: 1.0, green: 0.31, blue: 0.42)     // rose
    static let you = Color(red: 0.72, green: 0.95, blue: 0.3)      // lime
    static let good = Color(red: 0.2, green: 0.78, blue: 0.5), bad = wait
    /// You, readable on a light card too.
    static let youInk = Color(light: NSColor(red: 0.2, green: 0.62, blue: 0.1, alpha: 1), dark: NSColor(red: 0.72, green: 0.95, blue: 0.3, alpha: 1))
    /// Agents working, where a single ink is meant rather than one per agent.
    static let work = Color.primary.opacity(0.82)
}

/// The hero's ground in both appearances: deep at the top, a little lighter at the bottom.
private let ink = LinearGradient(colors: [Color(red: 0.035, green: 0.04, blue: 0.075), Color(red: 0.09, green: 0.1, blue: 0.16)],
                                 startPoint: .top, endPoint: .bottom)
private let widget = RoundedRectangle(cornerRadius: Radius.widget, style: .continuous)
private let gutter: CGFloat = 24

/// Quarter hours from 08:00; now is 18:00.
private enum Day {
    static let n = 48, now = 40
    static func wave(_ i: Int, _ base: Double, _ amp: Double, _ period: Double, _ phase: Double = 0) -> Double {
        i > now ? 0 : max(0, base + amp * sin(Double(i) / period + phase))
    }
    static let claude: [Double] = (0..<n).map { (i: Int) -> Double in wave(i, 1.15, 0.8, 5) }
    static let codex: [Double] = (0..<n).map { (i: Int) -> Double in i < 4 ? 0 : wave(i, 0.75, 0.6, 3.6, 1) }
    static let cursor: [Double] = (0..<n).map { (i: Int) -> Double in (22...37).contains(i) ? wave(i, 0.85, 0.4, 2) : 0 }
    static let wait: [Double] = (0..<n).map { (i: Int) -> Double in
        i > now ? 0 : [6, 13, 23, 25, 33].reduce(0.0) { $0 + max(0, 0.75 - 0.32 * abs(Double(i - $1))) }
    }
    static let layers: [(Color, [Double])] = [(Palette.claude, claude), (Palette.codex, codex), (Palette.cursor, cursor), (Palette.wait, wait)]
    static let total: [Double] = (0..<n).map { (i: Int) -> Double in layers.reduce(0.0) { $0 + $1.1[i] } }
    /// When you were at the computer.
    static let present: [Range<Int>] = [2..<8, 15..<20, 29..<31, 36..<41]
    static func clock(_ i: Int) -> String { String(format: "%d:%02d", 8 + i / 4, (i % 4) * 15) }
    static func x(_ i: Double, _ w: CGFloat) -> CGFloat { gutter + (w - gutter) * CGFloat(i / Double(n - 1)) }
}
struct OverviewPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            (Text("一个你，") + Text("干了 3 个人的活").foregroundStyle(Brand.green) + Text("。"))
                .font(.system(size: 34, weight: .heavy)).tracking(-0.6)
                .padding(.top, Space.xxl)
            Text("agent 一共干了 9.6 小时，你在电脑前 3.2 小时。6 个会话，完成 41 轮。")
                .font(.ui(.body)).foregroundStyle(.secondary).padding(.top, Space.s)
            Hero().padding(.top, Space.xxl)
            head("卡点", "agent 今天等了你 34 分钟，三分之二在你离开的时候。")
            HStack(spacing: Space.l) {
                Friction().frame(maxWidth: .infinity)
                Replies().frame(width: 200)
                AwayRing().frame(width: 200)
            }
            .frame(height: 218)
            head("谁在干 · 在哪干", "Claude Code 扛了一半以上，YaaKanban 占了 58% 的工时。")
            HStack(spacing: Space.l) { AgentBoard(); ProjectBoard() }.frame(height: 236)
            head("全部指标", "箭头和昨天同期比。")
            Ledger()
            lanes.padding(.top, Space.l)
        }
        .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 32)
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            Text("概览").font(.ui(.headline, .bold))
            Spacer()
            IconButton(symbol: "chevron.left", help: "") {}
            Text("10月27日 周一").font(.ui(.callout, .medium).monospacedDigit()).frame(minWidth: 110)
            IconButton(symbol: "chevron.right", help: "") {}.opacity(0.3)
            Segmented(items: [(0, "日"), (1, "周"), (2, "月")], selection: .constant(0)).padding(.leading, Space.s)
        }
    }

    private func head(_ title: String, _ line: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.l) {
            Text(title).font(.system(size: 17, weight: .heavy)).tracking(-0.2)
            Text(line).font(.ui(.callout)).foregroundStyle(.secondary)
        }
        .padding(.top, 36).padding(.bottom, Space.l)
    }

    private var lanes: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "chevron.right").font(.ui(.caption, .bold)).foregroundStyle(.tertiary)
            Text("会话明细").font(.ui(.callout, .semibold))
            Text("6 个会话").font(.ui(.footnote)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Space.xl).frame(height: 44).surface(widget)
    }
}
/// The output: leverage large on the left; on the right the agents stacked through the day, with
/// your own time at the computer as a lime lane under them.
private struct Hero: View {
    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                Text("杠杆").font(.ui(.footnote, .bold)).tracking(1.5).foregroundStyle(.white.opacity(0.5))
                (Text("3.0").font(.figure(92)) + Text("×").font(.system(size: 46, weight: .heavy)).foregroundStyle(Palette.you))
                    .foregroundStyle(.white).shadow(color: Palette.you.opacity(0.25), radius: 24)
                    .padding(.top, -4)
                HStack(spacing: Space.s) {
                    Text("↑ 0.4×").font(.ui(.footnote, .bold).monospacedDigit()).foregroundStyle(Palette.you)
                    Text("比昨天同期").font(.ui(.footnote)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: Space.xl)
                HStack(alignment: .top, spacing: Space.xxl) {
                    stat("9.6h", "agent 工时", .white)
                    stat("3.2h", "你在场", Palette.you)
                    stat("41", "完成轮次", .white)
                }
            }
            .frame(width: 232, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.l) {
                    Text("同时在跑").font(.ui(.footnote, .bold)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    dot(Palette.claude, "Claude Code"); dot(Palette.codex, "Codex"); dot(Palette.cursor, "Cursor")
                    dot(Palette.wait, "等你"); dot(Palette.you, "你在场")
                }
                Stream().frame(height: 186)
                Presence(tint: Palette.you, track: .white.opacity(0.14)).frame(height: 12)
                Axis(ink: .white.opacity(0.4)).frame(height: 12)
            }
        }
        .padding(26)
        .frame(height: 316)
        .background(widget.fill(ink))
        .overlay(alignment: .topLeading) {
            // A faint lime glow behind the figure.
            RadialGradient(colors: [Palette.you.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: 180)
                .frame(width: 360, height: 300).offset(x: -60, y: -40).allowsHitTesting(false)
        }
        .clipShape(widget)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ v: String, _ t: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.figure(22)).foregroundStyle(c)
            Text(t).font(.ui(.caption, .medium)).foregroundStyle(.white.opacity(0.45))
        }
    }

    private func dot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(t).font(.ui(.caption, .medium)).foregroundStyle(.white.opacity(0.6))
        }
    }
}
/// Agents stacked as smooth layers, each edged in the ground's ink so they part cleanly; scale
/// lines faint; a callout on the busiest moment; now as a line with a dot on top of the stack.
private struct Stream: View {
    var body: some View {
        Canvas { ctx, size in
            let top = 5.0, h = size.height - 18, base = size.height
            func y(_ v: Double) -> CGFloat { base - h * CGFloat(v / top) }
            for v in [1.0, 2, 3, 4] {
                var line = Path(); line.move(to: CGPoint(x: gutter, y: y(v))); line.addLine(to: CGPoint(x: size.width, y: y(v)))
                ctx.stroke(line, with: .color(.white.opacity(0.06)), style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
                ctx.draw(Text("\(Int(v))").font(.figure(9, .bold)).foregroundStyle(.white.opacity(0.3)), at: CGPoint(x: 6, y: y(v)), anchor: .leading)
            }
            var below = [Double](repeating: 0, count: Day.n)
            for (color, series) in Day.layers {
                let above = zip(below, series).map(+)
                let points = { (s: [Double]) in (0...Day.now).map { CGPoint(x: Day.x(Double($0), size.width), y: y(s[$0])) } }
                var area = smooth(points(above))
                for q in points(below).reversed() { area.addLine(to: q) }
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [color, color.opacity(0.78)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: base)))
                ctx.stroke(smooth(points(above)), with: .color(Color(red: 0.05, green: 0.06, blue: 0.1)), lineWidth: 1.5)
                below = above
            }
            // Past now: a dotted floor.
            var floor = Path(); floor.move(to: CGPoint(x: Day.x(Double(Day.now), size.width), y: base - 0.5))
            floor.addLine(to: CGPoint(x: size.width, y: base - 0.5))
            ctx.stroke(floor, with: .color(.white.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            // The busiest moment.
            let peak = Day.total.indices.max { Day.total[$0] < Day.total[$1] }!
            let p = CGPoint(x: Day.x(Double(peak), size.width), y: y(Day.total[peak]))
            var lead = Path(); lead.move(to: p); lead.addLine(to: CGPoint(x: p.x, y: 6))
            ctx.stroke(lead, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(.white))
            ctx.draw(Text("最忙 \(Day.clock(peak)) · \(String(format: "%.1f", Day.total[peak])) 个同时").font(.ui(.caption, .semibold)).foregroundStyle(.white),
                     at: CGPoint(x: p.x + 6, y: 6), anchor: .leading)
            // Now.
            let nx = Day.x(Double(Day.now), size.width), ny = y(Day.total[Day.now])
            ctx.fill(Path(CGRect(x: nx - 0.75, y: ny, width: 1.5, height: base - ny)), with: .color(.white.opacity(0.8)))
            ctx.fill(Path(ellipseIn: CGRect(x: nx - 9, y: ny - 9, width: 18, height: 18)), with: .color(.white.opacity(0.18)))
            ctx.fill(Path(ellipseIn: CGRect(x: nx - 4, y: ny - 4, width: 8, height: 8)), with: .color(.white))
        }
    }

    private func smooth(_ p: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: p[0])
        for i in 1..<p.count {
            let mid = CGPoint(x: (p[i - 1].x + p[i].x) / 2, y: (p[i - 1].y + p[i].y) / 2)
            path.addQuadCurve(to: mid, control: p[i - 1])
        }
        path.addLine(to: p[p.count - 1])
        return path
    }
}

/// Your time at the computer, as a lane aligned with the chart above it.
private struct Presence: View {
    let tint: Color, track: Color
    var body: some View {
        Canvas { ctx, size in
            ctx.draw(Text("你").font(.ui(.caption, .bold)).foregroundStyle(tint), at: CGPoint(x: 6, y: size.height / 2), anchor: .leading)
            var line = Path(); line.move(to: CGPoint(x: gutter, y: size.height / 2)); line.addLine(to: CGPoint(x: Day.x(Double(Day.now), size.width), y: size.height / 2))
            ctx.stroke(line, with: .color(track), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 4]))
            for r in Day.present {
                let a = Day.x(Double(r.lowerBound), size.width), b = Day.x(Double(r.upperBound - 1), size.width)
                ctx.fill(Path(roundedRect: CGRect(x: a, y: 2, width: max(6, b - a), height: size.height - 4), cornerRadius: (size.height - 4) / 2),
                         with: .color(tint))
            }
        }
    }
}

private struct Axis: View {
    let ink: Color
    var body: some View {
        GeometryReader { g in
            ForEach([(0, "08:00"), (12, "11:00"), (24, "14:00"), (Day.now, "现在"), (Day.n - 1, "20:00")], id: \.0) { i, t in
                Text(t).font(.figure(10, i == Day.now ? .heavy : .bold)).foregroundStyle(i == Day.now ? .primary : ink).fixedSize()
                    .position(x: min(max(Day.x(Double(i), g.size.width), gutter + 12), g.size.width - 14), y: 6)
            }
        }
    }
}
/// Where you held the agents up: the total in rose, and every wait through the day, over your lane.
private struct Friction: View {
    var body: some View {
        Widget(title: "agent 在等你", accessory: { Badge(text: "↓ 9m 比昨天同期", tint: Palette.good, compact: true) }) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xxl) {
                (Text("34").font(.figure(56)) + Text("m").font(.system(size: 26, weight: .heavy)))
                    .foregroundStyle(Palette.wait)
                VStack(alignment: .leading, spacing: 2) {
                    Text("22m").font(.figure(17)); Text("你离开时").font(.ui(.caption)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("6m").font(.figure(17)); Text("全部停工").font(.ui(.caption)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Canvas { ctx, size in
                for i in 0...Day.now {
                    let v = Day.wait[i], x = Day.x(Double(i), size.width)
                    if v > 0.05 {
                        let h = max(6, size.height * CGFloat(v / 1.1))
                        ctx.fill(Path(roundedRect: CGRect(x: x - 2.5, y: size.height - h, width: 5, height: h), cornerRadius: 2.5), with: .color(Palette.wait))
                    } else {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: size.height - 3, width: 3, height: 3)), with: .color(.primary.opacity(0.15)))
                    }
                }
            }
            .frame(height: 44)
            Presence(tint: Palette.youInk, track: .primary.opacity(0.2)).frame(height: 10)
            Axis(ink: .secondary).frame(height: 12)
        }
    }
}

/// Each reply as a dot on a log scale of how long the agent waited; the median marked.
private struct Replies: View {
    let waits: [Double] = [8, 12, 15, 18, 20, 22, 25, 27, 30, 32, 35, 38, 40, 42, 44, 48, 50, 55, 58, 65, 70, 90, 120, 180, 240, 300]
    var body: some View {
        Widget(title: "回复速度", accessory: { Badge(text: "↓ 12s", tint: Palette.good, compact: true) }) {
            Measure("48s", size: 40)
            Text("中位 · P90 4m").font(.ui(.caption)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Canvas { ctx, size in
                func x(_ s: Double) -> CGFloat { size.width * CGFloat(log(s / 5) / log(400.0 / 5)) }
                var seen: [Int: Int] = [:]
                for w in waits {
                    let col = Int(x(w) / 7), k = seen[col, default: 0]; seen[col] = k + 1
                    let c = w >= 180 ? Palette.wait : w <= 60 ? Palette.good : Color.orange
                    ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(col) * 7, y: size.height - 18 - CGFloat(k) * 7, width: 6, height: 6)), with: .color(c))
                }
                let m = x(48)
                ctx.fill(Path(CGRect(x: m - 0.5, y: 0, width: 1, height: size.height - 12)), with: .color(.primary.opacity(0.5)))
                for (s, t) in [(10.0, "10s"), (60, "1m"), (300, "5m")] {
                    ctx.draw(Text(t).font(.figure(9, .bold)).foregroundStyle(.secondary), at: CGPoint(x: x(s), y: size.height - 4))
                }
            }
            .frame(height: 64)
        }
    }
}

/// Of your time away: how much the agents kept working.
private struct AwayRing: View {
    var body: some View {
        Widget("你不在时") {
            HStack {
                Spacer()
                ZStack {
                    let style = StrokeStyle(lineWidth: 12, lineCap: .round)
                    Circle().stroke(Color.primary.opacity(0.06), lineWidth: 12)
                    Circle().trim(from: 0.02, to: 0.79).stroke(Palette.work, style: style).rotationEffect(.degrees(-90))
                    Circle().trim(from: 0.83, to: 0.98).stroke(Palette.wait, style: style).rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Measure("81%", size: 26)
                        Text("在干活").font(.ui(.micro, .semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 108, height: 108)
                Spacer()
            }
            Spacer(minLength: 0)
            HStack {
                Text("干活 1.6h").font(.figure(11, .bold))
                Spacer()
                Text("卡住 22m").font(.figure(11, .bold)).foregroundStyle(Palette.wait)
            }
        }
    }
}
private func rank(_ i: Int) -> some View {
    Text("\(i)").font(.figure(22)).foregroundStyle(i == 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary)).frame(width: 18)
}

private struct AgentBoard: View {
    let rows: [(logo: String, name: String, tint: Color, hours: String, share: Double, caption: String)] = [
        ("claudecode", "Claude Code", Palette.claude, "5.6h", 0.58, "3 个会话 · 26 轮"),
        ("codex", "Codex", Palette.codex, "3.0h", 0.31, "2 个会话 · 11 轮"),
        ("cursor", "Cursor", Palette.cursor, "1.0h", 0.11, "1 个会话 · 4 轮"),
    ]
    var body: some View {
        Widget("谁在干") {
            VStack(spacing: Space.m + 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    HStack(spacing: Space.l) {
                        rank(i + 1)
                        LogoTile(name: r.logo, size: 32)
                        VStack(alignment: .leading, spacing: Space.xs + 1) {
                            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                                Text(r.name).font(.ui(.body, .semibold))
                                if i == 0 { Badge(text: "最卖力", symbol: "crown.fill", tint: Palette.claude, compact: true) }
                                Spacer()
                                Measure(r.hours, size: 20)
                            }
                            GeometryReader { g in
                                Capsule().fill(Color.primary.opacity(0.06))
                                    .overlay(alignment: .leading) { Capsule().fill(r.tint).frame(width: g.size.width * r.share / 0.58) }
                            }
                            .frame(height: 6)
                            Text(r.caption).font(.ui(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ProjectBoard: View {
    let rows: [(name: String, hours: String, run: Double, wait: Double, caption: String)] = [
        ("YaaKanban", "5.6h", 0.86, 0.1, "等你 18m"),
        ("artrix-skills", "2.6h", 0.42, 0.03, "等你 4m"),
        ("wave-patch", "1.4h", 0.2, 0.08, "等你 12m"),
    ]
    var body: some View {
        Widget("在哪干") {
            VStack(spacing: Space.m + 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    HStack(spacing: Space.l) {
                        rank(i + 1)
                        VStack(alignment: .leading, spacing: Space.xs + 1) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(r.name).font(.ui(.body, .semibold))
                                Spacer()
                                Measure(r.hours, size: 20)
                            }
                            GeometryReader { g in
                                HStack(spacing: 2) {
                                    Capsule().fill(Palette.work).frame(width: g.size.width * r.run)
                                    Capsule().fill(Palette.wait).frame(width: g.size.width * r.wait)
                                    Spacer(minLength: 0)
                                }
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                            }
                            .frame(height: 6)
                            Text(r.caption).font(.ui(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 44)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Every other figure, on one card in a grid: label, figure, change.
private struct Ledger: View {
    let cells: [(String, String, String?, Bool)] = [
        ("平均同时在跑", "2.4个", "↑ 0.3", true), ("Agent 利用率", "86%", "↑ 4%", true), ("接手速度", "3m 40s", "↑ 50s", false),
        ("每次介入", "7m", "↑ 1m", true), ("吞吐", "12.8轮/h", nil, true),
        ("最长连跑", "47m", nil, true), ("当前积压", "2个", nil, true), ("切换", "23次", "↓ 4", true),
        ("工具调用", "1,284", nil, true), ("token", "3.1M", nil, true),
    ]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.l, alignment: .leading), count: 5), alignment: .leading, spacing: Space.xxl) {
            ForEach(cells, id: \.0) { title, value, delta, good in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title).font(.ui(.caption, .semibold)).foregroundStyle(.secondary)
                    Measure(value, size: 24)
                    Text(delta ?? " ").font(.ui(.caption, .bold).monospacedDigit()).foregroundStyle(good ? Palette.good : Palette.bad)
                }
            }
        }
        .padding(Space.xxl)
        .surface(widget)
    }
}
