import AppKit
import SwiftUI

// The Overview page, fourth take. Same surfaces, type and colours as the rest of the window: white
// cards on the canvas, the settings page's header, and only the colours the sidebar already uses
// (blue running, red waiting on you, green and red for change). Tension comes from scale and space.

enum Palette {
    /// Agents running, one blue in three strengths, darkest for the one that did the most.
    static let agents: [Color] = [.blue, .blue.opacity(0.55), .blue.opacity(0.28)]
    static let wait = Color.red
    static let you = Color.primary.opacity(0.75)
    static let good = Color.green, bad = Color.red
}

private let widget = RoundedRectangle(cornerRadius: Radius.widget, style: .continuous)

/// Quarter hours from 08:00; now is 18:00.
private enum Day {
    static let n = 48, now = 40
    static func wave(_ i: Int, _ base: Double, _ amp: Double, _ period: Double, _ phase: Double = 0) -> Double {
        i > now ? 0 : max(0, base + amp * sin(Double(i) / period + phase))
    }
    static let agents: [[Double]] = [
        (0..<n).map { (i: Int) -> Double in wave(i, 1.15, 0.8, 5) },
        (0..<n).map { (i: Int) -> Double in i < 4 ? 0 : wave(i, 0.75, 0.6, 3.6, 1) },
        (0..<n).map { (i: Int) -> Double in (22...37).contains(i) ? wave(i, 0.85, 0.4, 2) : 0 },
    ]
    static let wait: [Double] = (0..<n).map { (i: Int) -> Double in
        i > now ? 0 : [6, 13, 23, 25, 33].reduce(0.0) { $0 + max(0, 0.75 - 0.32 * abs(Double(i - $1))) }
    }
    static let total: [Double] = (0..<n).map { (i: Int) -> Double in agents.reduce(wait[i]) { $0 + $1[i] } }
    /// When you were at the computer.
    static let present: [Range<Int>] = [2..<8, 15..<20, 29..<31, 36..<41]
    static func clock(_ i: Int) -> String { String(format: "%d:%02d", 8 + i / 4, (i % 4) * 15) }
    /// Centre of column i, so every time chart on the page shares one grid.
    static func x(_ i: Int, _ w: CGFloat) -> CGFloat { w * (CGFloat(i) + 0.5) / CGFloat(n) }
    static func bar(_ w: CGFloat) -> CGFloat { max(3, (w / CGFloat(n) * 0.56).rounded()) }
}

/// A row title for a page section, in the settings groups' voice, with its takeaway on the same line.
private func section(_ title: String, _ line: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
        Text(title).font(.ui(.headline, .semibold))
        Text(line).font(.ui(.callout)).foregroundStyle(.secondary)
    }
    .padding(.leading, Space.xs).padding(.top, Space.page).padding(.bottom, Space.m + 2)
}
struct OverviewPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                PageHeader(title: "概览", symbol: "chart.xyaxis.line", tint: .accentColor,
                           lead: "10月27日 周一 · 6 个会话 · 41 轮")
                Spacer()
                HStack(spacing: Space.xs) {
                    IconButton(symbol: "chevron.left", help: "") {}
                    IconButton(symbol: "chevron.right", help: "") {}.opacity(0.3)
                    Segmented(items: [(0, "日"), (1, "周"), (2, "月")], selection: .constant(0)).padding(.leading, Space.m)
                }
                .padding(.top, Space.xs)
            }
            Hero().padding(.top, Space.xxl + Space.xs)
            section("卡点", "agent 今天等了你 34 分钟，三分之二在你离开的时候。")
            HStack(spacing: Space.l) {
                Friction()
                Replies().frame(width: 248)
            }
            .frame(height: 214)
            section("谁在干 · 在哪干", "Claude Code 扛了一半以上，YaaKanban 占了 58% 的工时。")
            HStack(spacing: Space.l) { AgentBoard(); ProjectBoard() }.frame(height: 244)
            section("全部指标", "和过去 7 天比。")
            Ledger()
            lanes.padding(.top, Space.l)
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
        .padding(.horizontal, Space.xl).frame(height: 46).surface(widget)
    }
}
/// The output on one plain card: leverage large on the left; on the right, how many agents were
/// running each quarter hour, waits on top in red, and your own time at the computer under them.
private struct Hero: View {
    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 0) {
                Text("杠杆").font(.ui(.footnote, .semibold)).foregroundStyle(.secondary)
                (Text("3.0").font(.figure(84)) + Text("×").font(.system(size: 40, weight: .bold)).foregroundStyle(.secondary))
                    .padding(.top, Space.xs)
                Badge(text: "↑ 0.4× 比昨天同期", tint: Palette.good, compact: true).padding(.top, Space.xs)
                Text("agent 干了 9.6 小时，你在电脑前 3.2 小时。")
                    .font(.ui(.callout)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.l)
                Spacer(minLength: Space.xl)
                HStack(alignment: .top, spacing: Space.xxl + Space.xs) {
                    stat("81%", "你不在时仍在干活")
                    stat("2.4", "平均同时在跑")
                }
            }
            .frame(width: 210, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.m) {
                legend
                Columns().frame(maxHeight: .infinity)
                Lane().frame(height: 8).padding(.top, Space.xs)
                Axis().frame(height: 12)
            }
        }
        .padding(Space.xxl + Space.xs)
        .frame(height: 300)
        .surface(widget)
    }

    private func stat(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Measure(v, size: 22)
            Text(t).font(.ui(.caption)).foregroundStyle(.secondary)
        }
    }

    private var legend: some View {
        HStack(spacing: Space.l) {
            Text("同时在跑").font(.ui(.footnote, .semibold)).foregroundStyle(.secondary)
            Spacer()
            ForEach(Array(["Claude Code", "Codex", "Cursor"].enumerated()), id: \.offset) { i, name in key(Palette.agents[i], name) }
            key(Palette.wait, "等你")
            key(Palette.you, "你在电脑前", capsule: true)
        }
    }

    private func key(_ c: Color, _ t: String, capsule: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: capsule ? 12 : 6, height: capsule ? 4 : 8)
            Text(t).font(.ui(.caption, .medium)).foregroundStyle(.secondary)
        }
    }
}
/// One column per quarter hour: agents stacked from the base, darkest first, the wait capping them
/// in red, parted by a hairline of the card. Past now, a dot on the floor. The busiest column named.
private struct Columns: View {
    var body: some View {
        Canvas { ctx, size in
            let top = 4.5, base = size.height - 1, h = size.height - 22, gap: CGFloat = 1.5
            let bw = Day.bar(size.width)
            func y(_ v: Double) -> CGFloat { base - h * CGFloat(v / top) }
            for v in [1.0, 2, 3, 4] {
                var line = Path(); line.move(to: CGPoint(x: 0, y: y(v))); line.addLine(to: CGPoint(x: size.width - 14, y: y(v)))
                ctx.stroke(line, with: .color(.primary.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                ctx.draw(Text("\(Int(v))").font(.figure(9, .bold)).foregroundStyle(.tertiary), at: CGPoint(x: size.width, y: y(v)), anchor: .trailing)
            }
            for i in 0..<Day.n {
                let x = Day.x(i, size.width) - bw / 2
                guard i <= Day.now else {
                    ctx.fill(Path(ellipseIn: CGRect(x: x + bw / 2 - 1.5, y: base - 3, width: 3, height: 3)), with: .color(.primary.opacity(0.15)))
                    continue
                }
                var acc = 0.0
                let parts: [(Color, Double)] = Day.agents.indices.map { (Palette.agents[$0], Day.agents[$0][i]) } + [(Palette.wait, Day.wait[i])]
                for (c, v) in parts where v > 0.04 {
                    let lo = y(acc), hi = y(acc + v)
                    let r = CGRect(x: x, y: hi, width: bw, height: max(1.5, lo - hi - (acc > 0 ? gap : 0)))
                    ctx.fill(Path(roundedRect: r, cornerRadius: min(2, bw / 2)), with: .color(c))
                    acc += v
                }
            }
            let peak = Day.total.indices.max { Day.total[$0] < Day.total[$1] }!
            let px = Day.x(peak, size.width)
            ctx.draw(Text("最忙 \(Day.clock(peak))").font(.ui(.caption, .semibold)).foregroundStyle(.primary)
                     + Text("  \(String(format: "%.1f", Day.total[peak])) 个").font(.ui(.caption)).foregroundStyle(.secondary),
                     at: CGPoint(x: px - bw / 2, y: y(Day.total[peak]) - 10), anchor: .leading)
        }
    }
}

/// Your time at the computer as capsules on a dotted track, on the same grid as the columns.
private struct Lane: View {
    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2, bw = Day.bar(size.width)
            for i in 0...Day.now {
                ctx.fill(Path(ellipseIn: CGRect(x: Day.x(i, size.width) - 1, y: mid - 1, width: 2, height: 2)), with: .color(.primary.opacity(0.18)))
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
/// Where you held the agents up: the total, how it split, and every wait through the day on the
/// hero's grid, over your lane, so the gaps line up with the time you were away.
private struct Friction: View {
    var body: some View {
        Widget(title: "agent 在等你", symbol: "hand.raised.fill", accessory: { Badge(text: "↓ 9m 比昨天同期", tint: Palette.good, compact: true) }) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xxl + Space.xs) {
                Measure("34m", size: 40)
                part("22m", "你离开时")
                part("6m", "全部停工")
            }
            Spacer(minLength: 0)
            Canvas { ctx, size in
                let bw = Day.bar(size.width)
                for i in 0..<Day.n {
                    let v = Day.wait[i], x = Day.x(i, size.width)
                    if i <= Day.now, v > 0.05 {
                        let h = max(4, size.height * CGFloat(v / 1.1))
                        ctx.fill(Path(roundedRect: CGRect(x: x - bw / 2, y: size.height - h, width: bw, height: h), cornerRadius: min(2, bw / 2)), with: .color(Palette.wait))
                    } else {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: size.height - 3, width: 3, height: 3)), with: .color(.primary.opacity(i <= Day.now ? 0.15 : 0.08)))
                    }
                }
            }
            .frame(height: 54)
            Lane().frame(height: 6).padding(.top, Space.xxs)
            Axis().frame(height: 12)
        }
    }

    private func part(_ v: String, _ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Measure(v, size: 18)
            Text(t).font(.ui(.caption)).foregroundStyle(.secondary)
        }
    }
}

/// How long the agents waited for each reply, in six bins; the slow ones in red, the median marked.
private struct Replies: View {
    let bins: [(String, Int)] = [("<15s", 3), ("30s", 6), ("1m", 9), ("2m", 4), ("5m", 3), ("5m+", 1)]
    var body: some View {
        Widget(title: "回复速度", accessory: { Badge(text: "↓ 12s", tint: Palette.good, compact: true) }) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Measure("48s", size: 40)
                Text("中位 · P90 4m").font(.ui(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: Space.s) {
                ForEach(Array(bins.enumerated()), id: \.offset) { i, b in
                    VStack(spacing: Space.xs) {
                        Text("\(b.1)").font(.figure(10, .bold)).foregroundStyle(i == 2 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(i >= 4 ? AnyShapeStyle(Palette.wait) : i == 2 ? AnyShapeStyle(Palette.you) : AnyShapeStyle(Color.primary.opacity(0.14)))
                            .frame(height: CGFloat(b.1) * 6)
                        Text(b.0).font(.figure(9, .semibold)).foregroundStyle(.tertiary).fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
/// A thin track with segments laid from the left.
private struct Meter: View {
    let parts: [(Color, Double)]
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in Capsule().fill(p.0).frame(width: max(4, g.size.width * p.1)) }
                Spacer(minLength: 0)
            }
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .frame(height: 5)
    }
}

/// One ranked row: a tile, name and caption, the figure, and a meter under them.
private func boardRow<Tile: View>(_ tile: Tile, _ name: String, _ badge: Badge?, _ caption: Text, _ value: String, _ parts: [(Color, Double)]) -> some View {
    HStack(alignment: .top, spacing: Space.l) {
        tile
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: Space.s) { Text(name).font(.ui(.body, .semibold)); badge }
                    caption.font(.ui(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                Measure(value, size: 22)
            }
            Meter(parts: parts)
        }
    }
}

private struct AgentBoard: View {
    let rows: [(logo: String, name: String, hours: String, share: Double, caption: String)] = [
        ("claudecode", "Claude Code", "5.6h", 0.58, "3 个会话 · 26 轮"),
        ("codex", "Codex", "3.0h", 0.31, "2 个会话 · 11 轮"),
        ("cursor", "Cursor", "1.0h", 0.11, "1 个会话 · 4 轮"),
    ]
    var body: some View {
        Widget("谁在干") {
            VStack(spacing: Space.l + 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    boardRow(LogoTile(name: r.logo, size: 30), r.name, i == 0 ? Badge(text: "最卖力", tint: .blue, compact: true) : nil,
                             Text(r.caption), r.hours, [(Palette.agents[i], r.share / 0.58)])
                }
            }
            .padding(.top, Space.xs)
            Spacer(minLength: 0)
        }
    }
}

private struct ProjectBoard: View {
    let rows: [(name: String, hours: String, run: Double, wait: Double, waited: String)] = [
        ("YaaKanban", "5.6h", 0.86, 0.1, "18m"),
        ("artrix-skills", "2.6h", 0.42, 0.03, "4m"),
        ("wave-patch", "1.4h", 0.2, 0.08, "12m"),
    ]
    var body: some View {
        Widget("在哪干") {
            VStack(spacing: Space.l + 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    boardRow(IconTile(symbol: "folder.fill", tint: .gray, size: 30), r.name, nil,
                             Text("等你 ") + Text(r.waited).foregroundStyle(Palette.wait), r.hours,
                             [(Palette.agents[0], r.run), (Palette.wait, r.wait)])
                }
            }
            .padding(.top, Space.xs)
            Spacer(minLength: 0)
        }
    }
}
/// Every other figure on one card: label, figure with the last seven days beside it (today in
/// ink), and the change.
private struct Ledger: View {
    let cells: [(String, String, String?, Bool)] = [
        ("平均同时在跑", "2.4个", "↑ 0.3", true), ("Agent 利用率", "86%", "↑ 4%", true), ("接手速度", "3m 40s", "↑ 50s", false),
        ("每次介入", "7m", "↑ 1m", true), ("吞吐", "12.8轮/h", "↑ 1.1", true),
        ("最长连跑", "47m", "↓ 6m", false), ("当前积压", "2个", nil, true), ("切换", "23次", "↓ 4", true),
        ("工具调用", "1,284", "↑ 210", true), ("token", "3.1M", "↑ 0.4M", true),
    ]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xl, alignment: .leading), count: 5), alignment: .leading, spacing: Space.xxl + Space.xs) {
            ForEach(Array(cells.enumerated()), id: \.offset) { k, c in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(c.0).font(.ui(.caption, .medium)).foregroundStyle(.secondary)
                    HStack(alignment: .bottom, spacing: Space.s) {
                        Measure(c.1, size: 24)
                        Spacer(minLength: 0)
                        spark(k)
                    }
                    Text(c.2 ?? "—").font(.ui(.caption, .semibold).monospacedDigit())
                        .foregroundStyle(c.2 == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(c.3 ? Palette.good : Palette.bad))
                }
            }
        }
        .padding(Space.xxl + Space.xs)
        .surface(widget)
    }

    private func spark(_ k: Int) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<7, id: \.self) { d in
                let v = 0.35 + 0.5 * abs(sin(Double(d * 3 + k * 7) * 0.7))
                Capsule().fill(d == 6 ? AnyShapeStyle(.primary.opacity(0.75)) : AnyShapeStyle(.primary.opacity(0.12)))
                    .frame(width: 3, height: 18 * (d == 6 ? 0.9 : v))
            }
        }
        .padding(.bottom, 4)
    }
}
