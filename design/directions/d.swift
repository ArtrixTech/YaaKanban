import SwiftUI

// D · Dark tinted tiles (the Habits pin): each tile a deep wash of its hue on black, its data as a
// grid of rounded cells lit in tints of the hue, a pill along the bottom with the summary.

private struct TileD<Content: View>: View {
    let hue: Color
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
            .background {
                ZStack {
                    shape.fill(Color(white: 0.05))
                    shape.fill(LinearGradient(colors: [hue.opacity(0.18), hue.opacity(0.34)], startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(LinearGradient(colors: [hue.opacity(0.35), hue.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
            .environment(\.colorScheme, .dark)
    }
}

private func title(_ symbol: String, _ t: String, _ hue: Color, _ trailing: String = "") -> some View {
    HStack(spacing: 7) {
        Image(systemName: symbol).foregroundStyle(hue)
        Text(t)
        Spacer()
        Text(trailing).foregroundStyle(.white.opacity(0.6))
    }
    .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 4)
}

/// The summary pill along the tile's foot, a lighter wash of the hue.
private func pill(_ hue: Color, @ViewBuilder _ content: () -> some View) -> some View {
    HStack(spacing: 6) { content() }
        .font(.system(size: 15, weight: .semibold).monospacedDigit())
        .frame(maxWidth: .infinity).frame(height: 38)
        .background(Capsule().fill(hue.opacity(0.28)))
}

/// Cells lit by level (0 off, then three tints), the next ones outlined as still to come.
private func cells(_ levels: [Double], cols: Int, hue: Color, from future: Int = .max) -> some View {
    Canvas { ctx, size in
        let rows = (levels.count + cols - 1) / cols, gap: CGFloat = 4
        let d = min((size.width - gap * CGFloat(cols - 1)) / CGFloat(cols), (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
        let x0 = (size.width - (d * CGFloat(cols) + gap * CGFloat(cols - 1))) / 2
        for (k, v) in levels.enumerated() {
            let r = CGRect(x: x0 + CGFloat(k % cols) * (d + gap), y: CGFloat(k / cols) * (d + gap), width: d, height: d)
            let p = Path(roundedRect: r, cornerRadius: d * 0.28)
            if k >= future { ctx.stroke(p.strokedPath(StrokeStyle(lineWidth: 1.2)), with: .color(hue.opacity(0.45))); continue }
            switch v {
            case ..<0.15: ctx.fill(p, with: .color(.white.opacity(0.06)))
            case ..<0.45: ctx.fill(p, with: .color(hue.opacity(0.45)))
            case ..<0.75: ctx.fill(p, with: .color(hue))
            default: ctx.fill(p, with: .color(hue)); ctx.fill(p, with: .color(.white.opacity(0.5)))
            }
        }
    }
}

struct BoardD: View {
    var body: some View {
        // The day in quarter hours, 8:00 to 24:00: 16 columns an hour, 4 rows a quarter.
        let day = (0..<64).map { k -> Double in let q = (k % 16) * 4 + k / 16; return q < Day.n ? Day.running[q] / 3 : 0 }
        let waitCells = (0..<60).map { k -> Double in Day.waits.contains { $0.contains(k * 48 / 60) } ? [0.9, 0.6, 0.35][k % 3] : 0 }
        let replyCells = Day.replies.map { $0 < 30 ? 0.9 : $0 < 60 ? 0.6 : $0 < 180 ? 0.3 : 0.05 } + Array(repeating: -1, count: 2)
        let awayCells = (0..<60).map { k -> Double in (15..<21).contains(k) || (43..<48).contains(k) ? 0.05 : [0.9, 0.6, 0.6, 0.3][k % 4] }
        return Board(tag: "D", title: "暗色染底 · 点阵", note: "参考 Habits：每卡一色深染、圆角格子点阵、底部药丸汇总", dark: true) {
            TileD(hue: Hue.work) {
                title("bolt.fill", "杠杆 · 同时在跑", Hue.work, "8:00 – 24:00，一格一刻钟")
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        Fig(text: "3.0×", size: 60, weight: .semibold, design: .rounded, ink: .white, unit: Hue.work, unitScale: 0.5)
                        Text("↑ 0.4× 比昨天").font(.system(size: 13, weight: .semibold)).foregroundStyle(Hue.work)
                    }
                    .frame(width: 150, alignment: .leading).padding(.leading, 4)
                    cells(day, cols: 16, hue: Hue.work, from: 16 * 4).overlay(alignment: .topLeading) { EmptyView() }
                }
                pill(Hue.work) { Text("Agent 9.6h"); Text("·").opacity(0.5); Text("你在电脑前 3.2h").opacity(0.75) }
            }
        } a: {
            TileD(hue: Hue.wait) {
                title("hand.raised.fill", "在等你", Hue.wait, "一格 12 分钟")
                cells(waitCells, cols: 12, hue: Hue.wait, from: 50)
                pill(Hue.wait) { Text("34m"); Text("× 5 次").opacity(0.7) }
            }
        } b: {
            TileD(hue: Hue.reply) {
                title("arrowshape.turn.up.left.fill", "回复速度", Hue.reply, "一格一次")
                cells(replyCells, cols: 10, hue: Hue.reply, from: 38)
                pill(Hue.reply) { Text("中位 48s"); Text("↓ 12s").opacity(0.7) }
            }
        } c: {
            TileD(hue: Hue.away) {
                title("figure.walk", "你不在时", Hue.away, "一格 2 分钟")
                cells(awayCells, cols: 12, hue: Hue.away)
                pill(Hue.away) { Text("81%"); Text("仍在干活").opacity(0.7) }
            }
        }
    }
}
