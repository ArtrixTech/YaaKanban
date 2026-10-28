import SwiftUI

// C · Giant type (the Lovable cards): the figure is the picture, set huge and cropped by the tile,
// a gradient wave rising through its foot. Black and cream tiles, small labels in the corners.

private let cream = Color(red: 0.96, green: 0.95, blue: 0.92), ink = Color(white: 0.07)

private struct TileC<Labels: View, Content: View>: View {
    var fill: Color = ink
    let labels: Labels
    @ViewBuilder var content: Content
    var body: some View {
        // The picture is oversized on purpose; it must not size the tile, and the labels sit on
        // the tile, not on the picture.
        Color.clear.overlay { ZStack { content } }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(fill))
            .overlay { labels }
    }
}

private func giant(_ t: String, _ size: CGFloat, _ ink: Color) -> some View {
    Text(t).font(.system(size: size, weight: .bold).monospacedDigit()).tracking(-size * 0.05).foregroundStyle(ink)
        .lineLimit(1).fixedSize()
}

/// Labels pinned to a tile's four corners.
private func corners(_ tl: String, _ tr: String, _ bl: String = "", _ br: String = "", c: Color) -> some View {
    VStack {
        HStack { Text(tl); Spacer(); Text(tr) }
        Spacer()
        if !bl.isEmpty || !br.isEmpty { HStack { Text(bl); Spacer(); Text(br) } }
    }
    .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(c).padding(16)
}

/// A soft wave of colour along the bottom, its crest following the given heights.
private func wave(_ heights: [Double], _ colors: [Color], top: CGFloat) -> some View {
    Canvas { ctx, size in
        let pts = heights.enumerated().map { CGPoint(x: size.width * CGFloat($0.offset) / CGFloat(heights.count - 1),
                                                     y: size.height - top * CGFloat($0.element)) }
        var p = smooth(pts); p.addLine(to: CGPoint(x: size.width, y: size.height)); p.addLine(to: CGPoint(x: 0, y: size.height)); p.closeSubpath()
        var soft = ctx; soft.addFilter(.blur(radius: 18))
        soft.fill(p, with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
        var crisp = ctx; crisp.addFilter(.blur(radius: 3))
        crisp.fill(p.offsetBy(dx: 0, dy: 16), with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
    }
    .allowsHitTesting(false)
}

struct BoardC: View {
    var body: some View {
        Board(tag: "C", title: "巨字", note: "参考 Lovable 卡片：数字本身就是画面，被卡片裁切，渐变从底部漫上来", dark: true) {
            TileC(labels: corners("杠杆 · 今天", "Agent 9.6h · 你 3.2h · ↑ 0.4× 比昨天", c: .white)) {
                giant("3.0×", 260, .white).frame(maxWidth: .infinity, alignment: .leading).offset(x: 18, y: 62)
                wave(Day.running.map { $0 / 3 * 0.8 + 0.15 }, [Color(red: 0.05, green: 0.6, blue: 0.75), Hue.work, Hue.lime], top: 95)
            }
        } a: {
            TileC(fill: cream, labels: corners("在等你", "5 次 · 最长 9m · ↓ 9m", c: ink)) {
                giant("34m", 168, ink).frame(maxWidth: .infinity, alignment: .leading).offset(x: 10, y: 52)
                Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.2), Hue.wait, Color(red: 0.85, green: 0.1, blue: 0.45)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 52))
                    .frame(width: 84, height: 84).blur(radius: 1.5).offset(x: 40, y: 34)
            }
        } b: {
            TileC(labels: corners("回复速度 · 中位", "38 次 · ↓ 12s", c: .white)) {
                giant("48s", 168, .white)
                    .overlay {
                        LinearGradient(colors: [.white.opacity(0), Hue.reply, Color(red: 1, green: 0.2, blue: 0.5)], startPoint: UnitPoint(x: 0.5, y: 0.25), endPoint: UnitPoint(x: 0.5, y: 0.75))
                            .mask(giant("48s", 168, .white))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).offset(x: 10, y: 52)
                wave((0..<24).map { 0.35 + 0.25 * sin(Double($0) / 3.2) }, [Hue.reply, Color(red: 1, green: 0.25, blue: 0.45)], top: 60)
            }
        } c: {
            TileC(fill: Hue.away, labels: corners("你不在时", "离开 2.0h", "仍在干活", "卡住 22m", c: .white)) {
                LinearGradient(colors: [Color(red: 0.25, green: 0.3, blue: 0.95), Hue.away, Hue.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(red: 1, green: 0.35, blue: 0.55).opacity(0.85), .clear], center: UnitPoint(x: 0.95, y: 1), startRadius: 0, endRadius: 150)
                giant("81%", 120, .white).offset(y: 10)
            }
        }
    }
}
