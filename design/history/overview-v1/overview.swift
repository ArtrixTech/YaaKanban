import SwiftUI

// The Overview page (dashboard) on the design system, with made-up figures for one day.

private func lift<S: Shape>(_ shape: S) -> some View { Color.clear.surface(shape) }
private let card = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
private let tile = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
private let running = Color.blue, waiting = Color.red

struct OverviewPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            header
            Text("今天你带着 6 个会话忙了 3.2h，agent 一共干了 9.6h，相当于 3.0 个你，比昨天同期多 1.4h；agent 找你时，你一般 48s 内回复；完成 41 轮。")
                .font(.ui(.body)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.l) {
                FigureCard(title: "Agent 总工时", value: "9.6h", delta: "↑ 1.4h 比昨天同期", good: true, note: "所有 agent 在跑的时间相加")
                FigureCard(title: "杠杆", value: "3.0×", delta: "↑ 0.4× 比昨天同期", good: true, note: "agent 总工时 ÷ 你在场的时间")
                FigureCard(title: "回复速度", value: "48s", delta: "↓ 12s 比昨天同期", good: true, note: "agent 等你回复的中位 · P90 4m")
                FigureCard(title: "离开时被卡住", value: "22m", delta: "↑ 9m 比昨天同期", good: false, note: "你不在时 agent 在问你或卡住")
            }
            HStack(spacing: Space.l) {
                Fact(symbol: "trophy", title: "最卖力", logo: "claudecode", value: "迁移 Settings 到主窗口", caption: "跑了 2.1h · 14 轮")
                Fact(symbol: "flame", title: "最长连跑", logo: "codex", value: "47m", caption: "整理设计系统 token")
                Fact(symbol: "chart.bar.fill", title: "最忙的时候", value: "3.5 个同时在跑", caption: "14:00–14:30")
                Fact(symbol: "moon.zzz", title: "你不在时", value: "81%", caption: "在干活 1.6h，卡住 22m")
            }
            Chart()
            HStack(alignment: .top, spacing: Space.l) {
                VStack(spacing: Space.l) { AgentMixCard(); ProjectsCard() }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.l), GridItem(.flexible())], spacing: Space.l) {
                    Tile(symbol: "square.stack.3d.up", title: "平均同时在跑", value: "2.4 个会话", delta: "↑ 0.3", good: true, caption: "agent 在跑时 · 峰值 4")
                    Tile(symbol: "pause.circle", title: "全部停工", value: "6m", delta: "↓ 3m", good: true, caption: "有 agent 卡着等你，且没有在跑的")
                    Tile(symbol: "gauge.with.dots.needle.67percent", title: "Agent 利用率", value: "86%", delta: "↑ 4%", good: true, caption: "运行 ÷（运行 + 卡着等你）")
                    Tile(symbol: "checkmark.circle", title: "接手速度", value: "3m 40s", delta: "↑ 50s", good: false, caption: "完成到你查看的中位 · P90 18m")
                    Tile(symbol: "hand.point.up.left", title: "每次介入", value: "7m", delta: nil, good: true, caption: "每条提示或回答 · 共 82 次")
                    Tile(symbol: "bolt", title: "吞吐", value: "12.8 轮/h", delta: nil, good: true, caption: "1,284 次工具调用 · 3.1M token")
                }
            }
            HStack(spacing: Space.s) {
                Image(systemName: "chevron.right").font(.ui(.caption, .bold)).foregroundStyle(.tertiary)
                Text("会话明细").font(.ui(.callout, .semibold))
                Text("6 个会话").font(.ui(.footnote)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Space.xl).frame(height: 40).background(lift(card))
        }
        .padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 32)
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            Text("概览").font(.ui(.title, .bold)).tracking(-0.2)
            Spacer()
            IconButton(symbol: "chevron.left", help: "") {}
            Text("10月27日 周一").font(.ui(.callout, .medium).monospacedDigit()).frame(minWidth: 110)
            IconButton(symbol: "chevron.right", help: "") {}.opacity(0.3)
            Segmented(items: [(0, "日"), (1, "周"), (2, "月")], selection: .constant(0)).padding(.leading, Space.s)
        }
    }
}

private struct FigureCard: View {
    let title: String, value: String, delta: String, good: Bool, note: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.ui(.footnote, .semibold)).foregroundStyle(.secondary)
            Text(value).font(.figure(30)).padding(.top, Space.xxs)
            Text(delta).font(.ui(.footnote, .medium).monospacedDigit()).foregroundStyle(good ? .green : .red)
            Text(note).font(.ui(.caption)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(Space.xl).frame(maxWidth: .infinity, alignment: .leading).background(lift(card))
    }
}

private struct Fact: View {
    let symbol: String, title: String
    var logo: String?
    let value: String, caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(title, systemImage: symbol).font(.ui(.footnote, .semibold)).foregroundStyle(.secondary)
            HStack(spacing: Space.s) {
                if let logo { LogoTile(name: logo, size: 16) }
                Text(value).font(.ui(.headline, .semibold)).lineLimit(1)
            }
            Text(caption).font(.ui(.caption)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(Space.l + 2).frame(maxWidth: .infinity, alignment: .leading).background(lift(tile))
    }
}

private struct Tile: View {
    let symbol: String, title: String, value: String
    let delta: String?
    let good: Bool
    let caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(title, systemImage: symbol).font(.ui(.footnote, .semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(value).font(.figure(20))
                if let delta { Text(delta).font(.ui(.caption, .medium).monospacedDigit()).foregroundStyle(good ? .green : .red) }
            }
            Text(caption).font(.ui(.caption)).foregroundStyle(.tertiary).lineLimit(2)
        }
        .padding(Space.l + 2).frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading).background(lift(tile))
    }
}

private func swatch(_ c: Color, _ t: String) -> some View {
    HStack(spacing: Space.xs) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 6); Text(t) }
}

private struct Chart: View {
    // Half-hour slices, 08:00 to 20:00.
    let run: [Double] = [0, 0.5, 1, 1, 1.5, 2, 2.5, 2, 3, 2.5, 2, 1, 0.5, 0.5, 1.5, 2.5, 3, 3.5, 3, 2.5, 2, 1.5, 0, 0]
    let wait: [Double] = [0, 0, 0.5, 0, 0, 0.5, 0, 1, 0, 0.5, 0, 0, 0, 0.5, 0, 0, 0.5, 0, 0.5, 0, 0.5, 0, 0, 0]
    let ghost: [Double] = [0, 0, 0.5, 1, 1, 1.5, 1.5, 2, 2, 2, 1.5, 1, 0.5, 1, 1, 1.5, 2, 2, 2.5, 2, 1.5, 1, 0.5, 0]
    let away: [Range<Int>] = [11..<14]
    let now = 18

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("同时在跑 / 在等你的会话数").font(.ui(.callout, .semibold))
                Spacer()
                HStack(spacing: Space.l) {
                    swatch(running, "在跑"); swatch(waiting, "等你处理"); swatch(.primary.opacity(0.08), "你不在")
                    HStack(spacing: Space.xs) {
                        Path { p in p.move(to: CGPoint(x: 0, y: 3)); p.addLine(to: CGPoint(x: 12, y: 3)) }
                            .stroke(Color.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])).frame(width: 12, height: 6)
                        Text("上期在跑")
                    }
                }
                .font(.ui(.caption)).foregroundStyle(.secondary)
            }
            Canvas { ctx, size in
                let gutter: CGFloat = 22, top = 4.0
                let plot = CGRect(x: gutter, y: 4, width: size.width - gutter, height: size.height - 4)
                let bw = plot.width / CGFloat(run.count)
                func y(_ v: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(v / top) }
                for a in away {
                    ctx.fill(Path(roundedRect: CGRect(x: plot.minX + CGFloat(a.lowerBound) * bw, y: plot.minY, width: CGFloat(a.count) * bw, height: plot.height),
                                  cornerRadius: 4), with: .color(.primary.opacity(0.05)))
                }
                for v in [0.0, 2, 4] {
                    if v == 0 { ctx.fill(Path(CGRect(x: plot.minX, y: y(v) - 0.25, width: plot.width, height: 0.5)), with: .color(.primary.opacity(0.1))) }
                    ctx.draw(Text(String(Int(v))).font(.ui(.micro).monospacedDigit()).foregroundStyle(.tertiary),
                             at: CGPoint(x: plot.minX - 6, y: min(max(y(v), 6), plot.maxY - 4)), anchor: .trailing)
                }
                for i in run.indices {
                    let x0 = plot.minX + CGFloat(i) * bw + 2, w = bw - 4
                    if run[i] > 0 {
                        ctx.fill(Path(roundedRect: CGRect(x: x0, y: y(run[i]), width: w, height: plot.maxY - y(run[i])), cornerRadius: 2.5), with: .color(running))
                    }
                    if wait[i] > 0 {
                        ctx.fill(Path(roundedRect: CGRect(x: x0, y: y(run[i] + wait[i]), width: w, height: y(run[i]) - y(run[i] + wait[i]) - 1.5),
                                      cornerRadius: 2.5), with: .color(waiting))
                    }
                }
                var line = Path()
                for (i, v) in ghost.enumerated() {
                    let a = CGPoint(x: plot.minX + CGFloat(i) * bw, y: y(v))
                    i == 0 ? line.move(to: a) : line.addLine(to: a)
                    line.addLine(to: CGPoint(x: a.x + bw, y: y(v)))
                }
                ctx.stroke(line, with: .color(.primary.opacity(0.35)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round, dash: [3, 2]))
                let nx = plot.minX + CGFloat(now) * bw
                ctx.fill(Path(roundedRect: CGRect(x: nx - 1, y: plot.minY, width: 2, height: plot.height), cornerRadius: 1), with: .color(.primary.opacity(0.35)))
            }
            .frame(height: 180)
            HStack {
                ForEach(["08:00", "11:00", "14:00", "17:00", "20:00"], id: \.self) { t in
                    Text(t).font(.ui(.caption).monospacedDigit()).foregroundStyle(.tertiary)
                    if t != "20:00" { Spacer() }
                }
            }
            .padding(.leading, 22)
        }
        .padding(Space.xl + 2).background(lift(card))
    }
}

private struct AgentMixCard: View {
    let rows: [(String, String, Color, Double, String)] = [
        ("claudecode", "Claude Code", .orange, 0.58, "5.6h · 58% · 3 个会话"),
        ("codex", "Codex", .teal, 0.31, "3.0h · 31% · 2 个会话"),
        ("cursor", "Cursor", .purple, 0.11, "1.0h · 11% · 1 个会话"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("军团构成").font(.ui(.callout, .semibold))
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(rows, id: \.1) { r in Capsule().fill(r.2).frame(width: g.size.width * r.3 - 2) }
                }
            }
            .frame(height: 8)
            ForEach(rows, id: \.1) { r in
                HStack(spacing: Space.s) {
                    Circle().fill(r.2).frame(width: 6, height: 6)
                    LogoTile(name: r.0, size: 16)
                    Text(r.1).font(.ui(.footnote, .medium))
                    Spacer()
                    Text(r.4).font(.ui(.caption).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(Space.xl).frame(maxWidth: .infinity, alignment: .leading).background(lift(card))
    }
}

private struct ProjectsCard: View {
    let rows: [(String, Double, Double, String)] = [
        ("YaaKanban", 0.7, 0.08, "在跑 5.1h · 等你 34m"),
        ("artrix-skills", 0.32, 0.03, "在跑 2.4h · 等你 12m"),
        ("wave-patch", 0.18, 0.06, "在跑 1.3h · 等你 26m"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("按项目").font(.ui(.callout, .semibold))
            ForEach(rows, id: \.0) { r in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text(r.0).font(.ui(.footnote, .medium))
                        Spacer()
                        Text(r.3).font(.ui(.caption).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { g in
                        HStack(spacing: 2) {
                            Capsule().fill(running).frame(width: g.size.width * r.1)
                            Capsule().fill(waiting).frame(width: g.size.width * r.2)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(Space.xl).frame(maxWidth: .infinity, alignment: .leading).background(lift(card))
    }
}
