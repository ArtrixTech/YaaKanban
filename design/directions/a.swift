import SwiftUI

// A · Black tiles, one neon hue each, on the light canvas (the Live Activities pins). Figures are
// thin and large; the hue lights the label, the figure's units and the one picture.

private struct TileA<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color(white: 0.04))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8))
            .environment(\.colorScheme, .dark)
    }
}

private func head(_ l: String, _ r: String, _ hue: Color) -> some View {
    HStack { Text(l).foregroundStyle(hue); Spacer(); Text(r).foregroundStyle(.white.opacity(0.9)) }
        .font(.system(size: 14, weight: .medium))
}

private func figA(_ t: String, _ size: CGFloat, _ hue: Color) -> Fig {
    Fig(text: t, size: size, weight: .regular, ink: .white, unit: hue, unitScale: 0.42, tracking: -size * 0.02)
}

struct BoardA: View {
    var body: some View {
        Board(tag: "A", title: "黑底霓虹", note: "参考 Live Activities：黑卡、细数字、一色发光图形") {
            TileA {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("杠杆").font(.system(size: 14, weight: .medium)).foregroundStyle(Hue.work)
                        figA("3.0×", 76, Hue.work).padding(.top, 2)
                        Text("↑ 0.4× 比昨天").font(.system(size: 13, weight: .medium)).foregroundStyle(Hue.work)
                        Spacer()
                        HStack(spacing: 22) {
                            figA("9.6h", 24, Hue.work); figA("3.2h", 24, .white.opacity(0.5))
                        }
                    }
                    .frame(width: 200, alignment: .leading)
                    VStack(spacing: 8) {
                        head("同时在跑", "现在 2 个", Hue.work)
                        Canvas { ctx, size in
                            let r = CGRect(x: 0, y: 10, width: size.width, height: size.height - 30)
                            let pts = dayPoints(r)
                            for i in (Day.now + 1)..<Day.n {
                                ctx.fill(disc(CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(Day.n - 1), y: r.maxY), 1.5), with: .color(.white.opacity(0.25)))
                            }
                            var area = smooth(pts); area.addLine(to: CGPoint(x: pts.last!.x, y: r.maxY)); area.addLine(to: CGPoint(x: 0, y: r.maxY))
                            ctx.fill(area, with: .linearGradient(Gradient(colors: [Hue.work.opacity(0.35), Hue.work.opacity(0)]),
                                                                 startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
                            var glow = ctx; glow.addFilter(.blur(radius: 6))
                            glow.stroke(smooth(pts), with: .color(Hue.work.opacity(0.8)), lineWidth: 4)
                            ctx.stroke(smooth(pts), with: .linearGradient(Gradient(colors: [Hue.work, Hue.lime]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            ctx.fill(disc(pts.last!, 6), with: .color(.white))
                            for (i, t) in [(0, "8:00"), (16, "12:00"), (32, "16:00"), (Day.now, "现在"), (47, "20:00")] {
                                ctx.draw(Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(i == Day.now ? Hue.work : .white.opacity(0.4)),
                                         at: CGPoint(x: min(max(r.width * CGFloat(i) / CGFloat(Day.n - 1), 14), size.width - 16), y: size.height - 4))
                            }
                        }
                    }
                }
            }
        } a: {
            TileA {
                head("Agent 在等你", "↓ 9m", Hue.wait)
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height - 8), R = min(size.width / 2 - 14, size.height - 20)
                    let span = 1.9, a0 = -span / 2
                    let a = { (q: Int) in a0 + span * Double(q) / Double(Day.n) }
                    ctx.stroke(arc(c, R, a0, a0 + span), with: .color(Hue.wait.opacity(0.28)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    let big = Day.waits[2]
                    var beam = Path(); beam.move(to: c); beam.addLine(to: at(c, R, a(big.lowerBound))); beam.addArc(center: c, radius: R,
                        startAngle: .radians(a(big.lowerBound) - .pi / 2), endAngle: .radians(a(big.upperBound) - .pi / 2), clockwise: false); beam.closeSubpath()
                    ctx.fill(beam, with: .radialGradient(Gradient(colors: [Hue.wait.opacity(0), Hue.wait.opacity(0.45)]), center: c, startRadius: 0, endRadius: R))
                    for w in Day.waits {
                        ctx.stroke(arc(c, R, a(w.lowerBound), a(w.upperBound)), with: .color(Hue.wait), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    }
                    ctx.fill(disc(at(c, R, a(Day.now)), 5), with: .color(.white))
                }
                HStack(alignment: .lastTextBaseline) { figA("34m", 40, Hue.wait); Spacer(); Text("最长 9m").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5)) }
            }
        } b: {
            TileA {
                head("回复速度", "38 次", Hue.reply)
                Spacer()
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle().stroke(Hue.reply.opacity(0.25), lineWidth: 9)
                        Circle().trim(from: 0, to: 0.74).stroke(Hue.reply, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                        Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 20)).foregroundStyle(Hue.reply)
                    }
                    .frame(width: 70, height: 70)
                    VStack(alignment: .leading, spacing: 2) {
                        figA("48s", 44, Hue.reply)
                        Text("74% 在 1 分钟内").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
            }
        } c: {
            TileA {
                head("你不在时", "离开 2.0h", Hue.away)
                Spacer()
                HStack { Text("13:10").font(.system(size: 13, weight: .medium)); Spacer(); Text("15:10").font(.system(size: 13, weight: .medium)) }
                    .foregroundStyle(.white.opacity(0.6))
                Canvas { ctx, size in
                    let y = size.height / 2, w = size.width
                    ctx.stroke(Path { $0.move(to: CGPoint(x: 6, y: y)); $0.addLine(to: CGPoint(x: w - 6, y: y)) },
                               with: .linearGradient(Gradient(colors: [Hue.away, Hue.cyan]), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)),
                               style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    for (a, b) in [(0.26, 0.36), (0.72, 0.8)] {
                        ctx.stroke(Path { $0.move(to: CGPoint(x: 6 + (w - 12) * a, y: y)); $0.addLine(to: CGPoint(x: 6 + (w - 12) * b, y: y)) },
                                   with: .color(Hue.wait), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    }
                    for x in [6.0, w - 6] { ctx.fill(disc(CGPoint(x: x, y: y), 7), with: .color(.white)) }
                }
                .frame(height: 24)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    figA("81%", 40, Hue.away); Text("仍在干活").font(.system(size: 13, weight: .medium)).foregroundStyle(Hue.away)
                }
                .padding(.top, 6)
            }
        }
    }
}
