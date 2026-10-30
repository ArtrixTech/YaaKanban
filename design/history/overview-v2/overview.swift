import SwiftUI

// The Overview page as a grid of widgets, with made-up figures for one day.

private let running = Color.blue, waiting = Color.red
private let agents: [(logo: String, name: String, tint: Color, hours: Double)] = [
    ("claudecode", "Claude Code", .orange, 5.6), ("codex", "Codex", .teal, 3.0), ("cursor", "Cursor", .purple, 1.0),
]
private let gap = Space.l

struct OverviewPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            header.padding(.bottom, Space.xs)
            Text("今天你带着 6 个会话忙了 3.2h，agent 一共干了 9.6h，相当于 3.0 个你；agent 找你时，你一般 48s 内回复；完成 41 轮。")
                .font(.ui(.body)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Space.s)
            HStack(spacing: gap) {
                agentHours.frame(maxWidth: .infinity)
                leverage.frame(width: 196)
                reply.frame(width: 196)
            }
            .frame(height: 186)
            ActivityWidget().frame(height: 244)
            HStack(spacing: gap) {
                away.frame(width: 196)
                utilization.frame(width: 196)
                projects.frame(maxWidth: .infinity)
            }
            .frame(height: 186)
            HStack(spacing: gap) {
                small("平均同时在跑", "2.4 个", "峰值 4", delta: ("↑ 0.3", .green))
                small("全部停工", "6m", "没有在跑、有在等你", delta: ("↓ 3m", .green))
                small("接手速度", "3m 40s", "P90 18m", delta: ("↑ 50s", .red))
                small("每次介入", "7m", "共 82 次")
            }
            .frame(height: 112)
            HStack(spacing: gap) {
                small("吞吐", "12.8 轮/h", "1,284 次工具调用 · 3.1M token")
                small("当前积压", "2 个", "最久的等了 14 分钟")
                small("切换", "23 次", "每活跃小时 7.2 次")
                small("最忙的时候", "3.5 个", "14:00–14:15 同时在跑")
            }
            .frame(height: 112)
            HStack(spacing: gap) {
                highlight("最卖力", "迁移 Settings 到主窗口", "claudecode", "2.1h", "14 轮 · YaaKanban")
                highlight("最长连跑", "整理设计系统 token", "codex", "47m", "没有停下等你")
            }
            .frame(height: 88)
            HStack(spacing: Space.s) {
                Image(systemName: "chevron.right").font(.ui(.caption, .bold)).foregroundStyle(.tertiary)
                Text("会话明细").font(.ui(.callout, .semibold))
                Text("6 个会话").font(.ui(.footnote)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Space.xl).frame(height: 44)
            .surface(RoundedRectangle(cornerRadius: Radius.widget, style: .continuous))
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
    private var agentHours: some View {
        Widget(title: "Agent 总工时", accessory: { Badge(text: "↑ 1.4h 比昨天同期", tint: .green, compact: true) }) {
            Measure("9.6h", size: 40)
            // One dot per six minutes of agent time, in each agent's color.
            DotMatrix(counts: agents.map { (Int($0.hours * 10), $0.tint) }, rows: 4)
            Spacer(minLength: 0)
            HStack(spacing: Space.l) {
                ForEach(agents, id: \.name) { a in
                    HStack(spacing: Space.xs) {
                        LogoTile(name: a.logo, size: 16)
                        Text(String(format: "%.1fh", a.hours)).font(.figure(13, .bold)).foregroundStyle(a.tint)
                    }
                }
            }
        }
    }

    private var leverage: some View {
        Widget(title: "杠杆", accessory: { Badge(text: "↑ 0.4×", tint: .green, compact: true) }) {
            Measure("3.0×", size: 40)
            Spacer(minLength: 0)
            People(value: 3.0)
            Text("相当于 3 个你在干活").font(.ui(.caption)).foregroundStyle(.tertiary)
        }
    }

    private var reply: some View {
        Widget(title: "回复速度", accessory: { Badge(text: "↓ 12s", tint: .green, compact: true) }) {
            Measure("48s", size: 40)
            Spacer(minLength: 0)
            ReplyStrip()
            Text("中位 48s · P90 4m").font(.ui(.caption).monospacedDigit()).foregroundStyle(.tertiary)
        }
    }

    private var away: some View {
        Widget("你不在时") {
            HStack { Spacer(); Ring(share: 0.81).frame(width: 78, height: 78); Spacer() }
            Spacer(minLength: 0)
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("在干活").font(.ui(.micro, .semibold)).foregroundStyle(.secondary)
                    Text("1.6h").font(.figure(13, .bold)).foregroundStyle(running)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("卡住").font(.ui(.micro, .semibold)).foregroundStyle(.secondary)
                    Text("22m").font(.figure(13, .bold)).foregroundStyle(waiting)
                }
            }
        }
    }

    private var utilization: some View {
        Widget(title: "Agent 利用率", accessory: { Badge(text: "↑ 4%", tint: .green, compact: true) }) {
            Measure("86%", size: 40)
            Spacer(minLength: 0)
            Stripes(share: 0.86)
            Text("运行 ÷（运行 + 卡着等你）").font(.ui(.caption)).foregroundStyle(.tertiary)
        }
    }

    private var projects: some View {
        Widget("按项目") {
            VStack(spacing: Space.m + 2) {
                ProjectRow(name: "YaaKanban", time: "5.6h", run: 0.82, wait: 0.1)
                ProjectRow(name: "artrix-skills", time: "2.6h", run: 0.36, wait: 0.04)
                ProjectRow(name: "wave-patch", time: "1.7h", run: 0.2, wait: 0.07)
            }
            Spacer(minLength: 0)
        }
    }

    private func small(_ title: String, _ value: String, _ caption: String, delta: (String, Color)? = nil) -> some View {
        Widget(title: title, accessory: { if let delta { Badge(text: delta.0, tint: delta.1, compact: true) } }) {
            Measure(value, size: 26)
            Spacer(minLength: 0)
            Text(caption).font(.ui(.caption)).foregroundStyle(.tertiary).lineLimit(1)
        }
    }

    private func highlight(_ title: String, _ session: String, _ logo: String, _ value: String, _ caption: String) -> some View {
        Widget(title) {
            HStack(spacing: Space.l) {
                LogoTile(name: logo, size: 30)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(session).font(.ui(.body, .semibold)).lineLimit(1)
                    Text(caption).font(.ui(.caption)).foregroundStyle(.tertiary)
                }
                Spacer()
                Measure(value, size: 26)
            }
        }
    }
}
private struct DotMatrix: View {
    let counts: [(Int, Color)]
    let rows: Int
    let pitch: CGFloat = 12

    var body: some View {
        let colors = counts.flatMap { Array(repeating: $0.1, count: $0.0) }
        let cols = (colors.count + rows - 1) / rows
        Canvas { ctx, _ in
            for (i, c) in colors.enumerated() {
                let rect = CGRect(x: CGFloat(i / rows) * pitch, y: CGFloat(i % rows) * pitch, width: pitch - 4, height: pitch - 4)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(c))
            }
        }
        .frame(width: CGFloat(cols) * pitch, height: CGFloat(rows) * pitch - 4)
    }
}

private struct People: View {
    let value: Double
    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: "person.fill").font(.system(size: 17)).foregroundStyle(Brand.green.opacity(Double(i) < value ? 1 : 0.2))
            }
        }
    }
}

/// Each reply this period as a bar, the slowest tenth in orange.
private struct ReplyStrip: View {
    let waits: [Double] = [20, 35, 12, 48, 60, 30, 240, 15, 42, 55, 18, 70, 25, 38, 180, 22, 50, 44, 28, 65, 32, 16, 90, 40, 27, 58, 36, 300]
    var body: some View {
        let top = waits.max()!.squareRoot()
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(waits.enumerated()), id: \.offset) { _, w in
                Capsule().fill(w >= 180 ? Color.orange : Color.primary.opacity(0.22))
                    .frame(height: max(4, 30 * w.squareRoot() / top))
            }
        }
        .frame(height: 30)
    }
}

/// Of the time away, the share the agents spent working (blue) and blocked (red).
private struct Ring: View {
    let share: Double
    var body: some View {
        let style = StrokeStyle(lineWidth: 9, lineCap: .round)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: 9)
            Circle().trim(from: 0.015, to: share - 0.015).stroke(running, style: style).rotationEffect(.degrees(-90))
            Circle().trim(from: share + 0.015, to: 0.985).stroke(waiting, style: style).rotationEffect(.degrees(-90))
            Measure("81%", size: 22)
        }
    }
}

private struct Stripes: View {
    let share: Double
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { i in
                Capsule().fill(Double(i) < share * 20 ? running : Color.primary.opacity(0.08))
            }
        }
        .frame(height: 22)
    }
}

private struct ProjectRow: View {
    let name: String, time: String
    let run: Double, wait: Double
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.ui(.footnote, .medium))
                Spacer()
                Measure(time, size: 15)
            }
            GeometryReader { g in
                HStack(spacing: 2) {
                    Capsule().fill(running).frame(width: g.size.width * run)
                    Capsule().fill(waiting).frame(width: g.size.width * wait)
                    Spacer(minLength: 0)
                }
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .frame(height: 8)
        }
    }
}
/// Sessions at once through the day, a quarter-hour per bar: running in blue with waiting on you
/// on top in red, yesterday's running behind in gray, and the time away as a band.
private struct ActivityWidget: View {
    // 08:00 to 20:00; nothing after now (18:00).
    let run: [Double] = (0..<48).map { (i: Int) -> Double in
        if i >= 40 { return 0 }
        let wave: Double = 1.4 * sin(Double(i) / 4.2)
        let jitter: Double = Double(i % 3) * 0.3
        let later: Double = i > 26 ? 0.8 : 0
        return max(0, (1.6 + wave + jitter + later).rounded())
    }
    let wait: [Double] = (0..<48).map { [5, 9, 14, 17, 23, 31, 33, 37].contains($0) ? 1 : 0 }
    let ghost: [Double] = (0..<48).map { (i: Int) -> Double in max(0, (1.2 + 1.1 * sin(Double(i + 3) / 5)).rounded()) }
    let away = 22..<28, now = 40, top = 5.0, height: CGFloat = 140

    var body: some View {
        Widget(title: "同时在跑 / 在等你的会话数", accessory: {
            HStack(spacing: Space.l) {
                legend(running, "在跑", "9.6h"); legend(waiting, "等你", "34m")
                legend(.primary.opacity(0.15), "你不在", "1.5h"); legend(.primary.opacity(0.07), "昨天", nil)
            }
        }) {
            Spacer(minLength: 0)
            GeometryReader { g in
                let slot = g.size.width / CGFloat(run.count)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Color.primary.opacity(0.04))
                        .frame(width: slot * CGFloat(away.count), height: height + 6)
                        .offset(x: slot * CGFloat(away.lowerBound), y: -6)
                    Text("你不在").font(.ui(.micro, .semibold)).foregroundStyle(.tertiary)
                        .offset(x: slot * CGFloat(away.lowerBound) + 6, y: -2)
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(run.indices, id: \.self) { i in bar(i).frame(width: slot) }
                    }
                    .frame(height: height, alignment: .bottom)
                    Capsule().fill(Color.primary.opacity(0.5)).frame(width: 2, height: height + 6)
                        .offset(x: slot * CGFloat(now) - 1, y: -6)
                }
            }
            .frame(height: height)
            GeometryReader { g in
                let slot = g.size.width / CGFloat(run.count)
                ForEach([(0, "08:00"), (12, "11:00"), (24, "14:00"), (now, "现在"), (48, "20:00")], id: \.0) { i, t in
                    Text(t).font(.ui(.caption, i == now ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(i == now ? .secondary : .tertiary).fixedSize()
                        .position(x: min(max(slot * CGFloat(i), 16), g.size.width - 16), y: 6)
                }
            }
            .frame(height: 12)
        }
    }

    private func bar(_ i: Int) -> some View {
        let unit = height / top
        return ZStack(alignment: .bottom) {
            Capsule().fill(Color.primary.opacity(0.07)).frame(height: max(0, ghost[i] * unit))
            VStack(spacing: 2) {
                if wait[i] > 0 { Capsule().fill(waiting).frame(height: wait[i] * unit - 2) }
                if run[i] > 0 { Capsule().fill(running).frame(height: run[i] * unit) }
            }
        }
        .padding(.horizontal, 2)
    }

    private func legend(_ c: Color, _ t: String, _ v: String?) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.ui(.caption)).foregroundStyle(.secondary)
            if let v { Text(v).font(.figure(11, .bold)) }
        }
    }
}
