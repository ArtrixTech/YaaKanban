import SwiftUI

// B · Saturated tiles, one hue each, deep at the top and lighter at the bottom (the colour-tile
// pins). White bold corner labels, one glowing object in the middle, a glass pill marking now.

private func tone(_ h: Color) -> (deep: Color, light: Color) {
    switch h {
    case Hue.work: (Color(red: 0.05, green: 0.5, blue: 0.22), Color(red: 0.3, green: 0.78, blue: 0.2))
    case Hue.wait: (Color(red: 0.62, green: 0.06, blue: 0.12), Color(red: 0.95, green: 0.22, blue: 0.2))
    case Hue.reply: (Color(red: 0.78, green: 0.38, blue: 0.0), Color(red: 1, green: 0.72, blue: 0.1))
    default: (Color(red: 0.02, green: 0.3, blue: 0.72), Color(red: 0.12, green: 0.58, blue: 0.95))
    }
}

private struct TileB<Content: View>: View {
    let hue: Color
    var glow = UnitPoint.center
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous), t = tone(hue)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
            .background {
                ZStack {
                    shape.fill(LinearGradient(colors: [t.deep, t.light], startPoint: .top, endPoint: .bottom))
                    shape.fill(RadialGradient(colors: [.white.opacity(0.28), .white.opacity(0)], center: glow, startRadius: 0, endRadius: 170))
                }
                .shadow(color: t.deep.opacity(0.35), radius: 14, y: 6)
            }
            .environment(\.colorScheme, .dark)
    }
}

private func corners(_ tl: String, _ tr: String) -> some View {
    HStack { Text(tl); Spacer(); Text(tr) }.font(.system(size: 15, weight: .bold).monospacedDigit())
}
private func figB(_ t: String, _ size: CGFloat) -> Fig {
    Fig(text: t, size: size, weight: .bold, ink: .white, unit: .white.opacity(0.7), unitScale: 0.55, tracking: -size * 0.015)
}

/// A glass pill: a pale wash, a bright top edge, a soft shadow.
func glass(_ ctx: GraphicsContext, _ r: CGRect, _ hue: Color) {
    let p = Path(roundedRect: r, cornerRadius: min(r.width, r.height) / 2)
    var lifted = ctx
    lifted.addFilter(.shadow(color: .black.opacity(0.25), radius: 6, y: 3))
    lifted.fill(p, with: .color(hue))
    ctx.fill(p, with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0.12)]),
                                      startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
    ctx.stroke(p.strokedPath(StrokeStyle(lineWidth: 1)), with: .linearGradient(Gradient(colors: [.white.opacity(0.8), .white.opacity(0.1)]),
                                      startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
}

struct BoardB: View {
    var body: some View {
        Board(tag: "B", title: "饱和色块", note: "参考彩色小组件：整卡一色、白色粗体角标、中间一个发光物件") {
            TileB(hue: Hue.work, glow: UnitPoint(x: 0.82, y: 0.45)) {
                corners("杠杆", "同时在跑 · 现在 2 个")
                HStack(alignment: .center, spacing: 20) {
                    figB("3.0×", 78)
                    Canvas { ctx, size in
                        let r = CGRect(x: 0, y: 20, width: size.width, height: size.height - 36)
                        let pts = dayPoints(r)
                        var future = Path(); future.move(to: pts.last!); future.addLine(to: CGPoint(x: size.width, y: pts.last!.y))
                        ctx.stroke(future, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.5, 7]))
                        var glow = ctx; glow.addFilter(.blur(radius: 8))
                        glow.stroke(smooth(pts), with: .color(Hue.lime), lineWidth: 8)
                        ctx.stroke(smooth(pts), with: .color(.white), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        let p = pts.last!
                        glass(ctx, CGRect(x: p.x - 30, y: p.y - 17, width: 60, height: 34), Hue.work)
                        ctx.draw(Text("2.4").font(.system(size: 16, weight: .bold)).foregroundStyle(.white), at: p)
                    }
                }
                .frame(maxHeight: .infinity)
                HStack { Text("Agent 9.6h · 你 3.2h"); Spacer(); Text("↑ 0.4× 比昨天") }.font(.system(size: 13, weight: .semibold)).opacity(0.85)
            }
        } a: {
            TileB(hue: Hue.wait) {
                corners("在等你", "5 次")
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2), R = size.height / 2 - 2
                    var under = ctx; under.addFilter(.blur(radius: 10))
                    under.fill(disc(CGPoint(x: c.x, y: c.y + 6), R * 0.8), with: .color(.black.opacity(0.4)))
                    ctx.fill(disc(c, R * 0.78), with: .radialGradient(Gradient(colors: [Color(red: 0.75, green: 0.1, blue: 0.14), Color(red: 0.4, green: 0.02, blue: 0.06)]),
                                                                    center: CGPoint(x: c.x - R * 0.2, y: c.y - R * 0.25), startRadius: 0, endRadius: R))
                    ctx.stroke(arc(c, R, 0, 2 * .pi), with: .color(.white.opacity(0.18)), lineWidth: 3)
                    let a = { (q: Int) in 2 * Double.pi * Double(q) / Double(Day.n) }
                    for w in Day.waits { ctx.stroke(arc(c, R, a(w.lowerBound), a(w.upperBound)), with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round)) }
                    var dot = ctx; dot.addFilter(.shadow(color: .white, radius: 4))
                    dot.fill(disc(at(c, R, a(Day.now)), 5), with: .color(.white))
                    ctx.draw(Image(systemName: "hourglass").resizable(), in: CGRect(x: c.x - 13, y: c.y - 15, width: 26, height: 30))
                }
                .frame(maxHeight: .infinity)
                HStack(alignment: .lastTextBaseline) { figB("34m", 30); Spacer(); Text("最长 9m").font(.system(size: 15, weight: .bold)) }
            }
        } b: {
            TileB(hue: Hue.reply, glow: UnitPoint(x: 0.45, y: 0.55)) {
                corners("回复速度", "38 次")
                Canvas { ctx, size in
                    var s = Path(); let y0 = size.height * 0.78, y1 = size.height * 0.22
                    s.move(to: CGPoint(x: -10, y: y0))
                    s.addCurve(to: CGPoint(x: size.width + 10, y: y1), control1: CGPoint(x: size.width * 0.45, y: y0), control2: CGPoint(x: size.width * 0.55, y: y1))
                    var glow = ctx; glow.addFilter(.blur(radius: 6))
                    glow.stroke(s, with: .color(.white.opacity(0.8)), lineWidth: 6)
                    ctx.stroke(s, with: .color(.white.opacity(0.9)), lineWidth: 2)
                    let m = CGPoint(x: size.width * 0.5, y: (y0 + y1) / 2)
                    glass(ctx, CGRect(x: m.x - 38, y: m.y - 19, width: 76, height: 38), Hue.reply)
                    ctx.draw(Text("48s").font(.system(size: 19, weight: .bold)).foregroundStyle(.white), at: m)
                }
                .frame(maxHeight: .infinity)
                HStack { Text("10s"); Spacer(); Text("中位"); Spacer(); Text("5m") }.font(.system(size: 15, weight: .bold)).opacity(0.85)
            }
        } c: {
            TileB(hue: Hue.away, glow: UnitPoint(x: 0.5, y: 0.6)) {
                HStack(alignment: .firstTextBaseline) { figB("81%", 22); Spacer(); Text("离开 2.0h").font(.system(size: 15, weight: .bold)) }
                Canvas { ctx, size in
                    var wave = Path(); let mid = size.height * 0.62
                    wave.move(to: CGPoint(x: 8, y: mid))
                    for i in 1...60 { let x = 8 + (size.width - 16) * CGFloat(i) / 60; wave.addLine(to: CGPoint(x: x, y: mid - 26 * CGFloat(sin(Double(i) / 60 * .pi * 1.0)))) }
                    ctx.stroke(wave, with: .color(Hue.cyan.opacity(0.55)), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    let p = CGPoint(x: size.width * 0.5, y: mid - 26)
                    for (k, o) in [(3.0, 0.08), (2.2, 0.12), (1.5, 0.18)] {
                        ctx.stroke(Path(roundedRect: CGRect(x: p.x - 9 * k, y: p.y - 22 * k * 0.8, width: 18 * k, height: 44 * k * 0.8), cornerRadius: 9 * k),
                                   with: .color(.white.opacity(o)), lineWidth: 1.5)
                    }
                    glass(ctx, CGRect(x: p.x - 11, y: p.y - 26, width: 22, height: 52), Hue.away)
                }
                .frame(maxHeight: .infinity)
                HStack { Text("13:10"); Spacer(); Text("卡住 22m"); Spacer(); Text("15:10") }.font(.system(size: 15, weight: .bold)).opacity(0.85)
            }
        }
    }
}
