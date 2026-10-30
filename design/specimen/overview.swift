import AppKit
import SwiftUI

// The Overview page, ninth take. Cards follow the appearance: white on the light canvas, a lifted
// dark gray on the dark one. One hue per card, deeper in light and brighter in dark, lights its
// label, its units and its chart; figures stay in the primary ink at one size, so the page reads as a
// grid. The top bar carries the day's totals, a row of small chips under it the counts. Two accents,
// leverage and away, let their colour fill the foot of the card.

/// One hue at the strengths a card draws with.
private struct Tint {
    let hue: Color
    var mid: Color { hue.opacity(0.6) }
    var dim: Color { hue.opacity(0.2) }
    var faint: Color { hue.opacity(0.1) }
    /// Axis text: gray, so the hue is left for the data.
    var axis: Color { ink3 }

    private init(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) {
        hue = Color(light: NSColor(red: light.0, green: light.1, blue: light.2, alpha: 1), dark: NSColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1))
    }

    /// Agent work and what it produced.
    static let work = Tint((0.1, 0.64, 0.34), (0.3, 0.86, 0.5))
    /// Agents running.
    static let run = Tint((0.1, 0.46, 0.96), (0.32, 0.64, 1))
    /// An agent waiting on you.
    static let wait = Tint((0.9, 0.24, 0.21), (1, 0.4, 0.36))
    /// You answering.
    static let reply = Tint((0.93, 0.52, 0), (1, 0.66, 0.2))
}

private let cardFill = Color(light: .white, dark: NSColor(white: 0.165, alpha: 1))
/// Text at three strengths, following the appearance.
private let ink1 = Color.primary.opacity(0.9), ink2 = Color.primary.opacity(0.55), ink3 = Color.primary.opacity(0.36)

/// Quarter hours from 08:00; now is 18:00.
private enum Day {
    static let n = 48, now = 40
    static func wave(_ i: Int, _ base: Double, _ amp: Double, _ period: Double, _ phase: Double = 0) -> Double {
        i > now ? 0 : max(0, base + amp * sin(Double(i) / period + phase))
    }
    static let running: [Double] = (0..<n).map { (i: Int) -> Double in
        wave(i, 1.15, 0.8, 5) + (i < 4 ? 0 : wave(i, 0.75, 0.6, 3.6, 1)) + ((22...37).contains(i) ? wave(i, 0.85, 0.4, 2) : 0)
    }
    static let yesterday: [Double] = (0..<n).map { (i: Int) -> Double in
        max(0, 1.3 + 0.7 * sin(Double(i) / 4.4 + 2)) + max(0, 0.6 * sin(Double(i) / 2.7))
    }
    /// When you were at the computer.
    static let present: [Range<Int>] = [2..<8, 15..<20, 29..<31, 36..<41]
    /// Waits as (start minute from 08:00, minutes, you were away).
    static let waits: [(Int, Int, Bool)] = [(135, 8, true), (198, 4, false), (330, 9, true), (375, 8, false), (500, 5, true)]
    /// Seconds per reply.
    static let replies: [Double] = (0..<38).map { (i: Int) -> Double in
        i >= 34 ? [205, 240, 270, 290][i - 34] : 48 * exp(0.62 * sin(Double(i) * 2.399 + 0.6) * 1.3)
    }
}

// MARK: - Anatomy

/// A card's surface: white with a soft two-part shadow on the light canvas, a lifted gray on the
/// dark one.
private struct Surface: View {
    var radius: CGFloat = 22
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(cardFill)
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 1, y: 1)
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 14, y: 6)
    }
}

/// A card: label row, then the content, all at one padding. `art` fills the card behind it, clipped.
private struct Panel<Content: View, Art: View>: View {
    var pad: CGFloat = 20
    @ViewBuilder var content: Content
    @ViewBuilder var art: Art
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { art.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)) }
            .background(Surface())
    }
}

extension Panel where Art == EmptyView {
    init(pad: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.init(pad: pad, content: content, art: { EmptyView() })
    }
}

/// The label row every card opens with: what it is in its hue, the context opposite in gray.
private struct Head: View {
    let title: String
    let tint: Tint
    var context: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint.hue)
            Spacer(minLength: 8)
            if let context { Text(context).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(ink2) }
        }
        .frame(height: 16)
    }
}

/// Figure sizes: every card's, and the two accents'.
private enum FigureSize { static let card: CGFloat = 34, accent: CGFloat = 46 }

/// A figure with its unit: the figure in the primary ink, the unit smaller in the card's hue.
private func figure(_ value: String, _ unit: String = "", _ t: Tint, _ size: CGFloat = FigureSize.card, ink: Color = ink1) -> Text {
    let v = Text(value).font(.system(size: size, weight: .semibold).monospacedDigit()).tracking(-size * 0.02).foregroundColor(ink)
    guard !unit.isEmpty else { return v }
    return v + Text(verbatim: "\u{2009}" + unit).font(.system(size: (size * 0.5).rounded(), weight: .semibold)).foregroundColor(t.hue)
}

/// The figure line: the figure, then a two-line note beside it, sitting on the figure's baseline.
private struct FigureRow: View {
    let fig: Text
    var note: String? = nil
    var delta: Text? = nil
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            fig.lineLimit(1).fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                if let delta { delta.font(.system(size: 12, weight: .medium).monospacedDigit()) }
                if let note { Text(note).font(.system(size: 12, weight: .medium)).foregroundStyle(ink2) }
            }
            .padding(.bottom, 3)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

/// A change: the arrow and amount in the primary ink, what it's against dim.
private func delta(_ up: Bool, _ amount: String, _ against: String = "比昨天") -> Text {
    Text(verbatim: (up ? "↑ " : "↓ ") + amount).foregroundColor(ink1) + Text(verbatim: " " + against).foregroundColor(ink3)
}

/// A key: a swatch and its word.
private struct Key: View {
    let swatch: AnyView
    let text: String
    var body: some View {
        HStack(spacing: 6) { swatch; Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(ink2) }
    }
}

// MARK: - Drawing

private func disc(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }

/// A line through points, smoothed (Catmull-Rom).
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

/// Angles clockwise from twelve o'clock.
private func at(_ c: CGPoint, _ r: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a))) }
private func arc(_ c: CGPoint, _ r: CGFloat, _ a: Double, _ b: Double) -> Path {
    var p = Path()
    p.addArc(center: c, radius: r, startAngle: .radians(a - .pi / 2), endAngle: .radians(b - .pi / 2), clockwise: false)
    return p
}

/// Axis text inside a chart.
private func tick(_ t: String, _ c: Color, _ size: CGFloat = 10.5) -> Text {
    Text(t).font(.system(size: size, weight: .medium).monospacedDigit()).foregroundColor(c)
}

/// How strong a glow is: soft on a white card, where a haze turns muddy; fuller on a dark one.
private func glowStrength(_ ctx: GraphicsContext) -> Double { ctx.environment.colorScheme == .dark ? 0.7 : 0.3 }

/// "Now": a disc of the card's hue with a white core, ringed in the card's colour so it sits clear of
/// the line under it.
private func knob(_ ctx: GraphicsContext, _ p: CGPoint, _ hue: Color, r: CGFloat = 5) {
    var halo = ctx
    halo.addFilter(.blur(radius: 5))
    halo.opacity = glowStrength(ctx)
    halo.fill(disc(p, r + 3), with: .color(hue))
    ctx.fill(disc(p, r + 2), with: .color(cardFill))
    ctx.fill(disc(p, r), with: .color(hue))
    ctx.fill(disc(p, r * 0.45), with: .color(.white))
}

/// A stroke with a glow of its own colour under it.
private func glow(_ ctx: GraphicsContext, _ path: Path, _ shading: GraphicsContext.Shading, width: CGFloat, blur: CGFloat = 7, cap: CGLineCap = .round) {
    var g = ctx
    g.addFilter(.blur(radius: blur))
    g.opacity = glowStrength(ctx)
    g.stroke(path, with: shading, style: StrokeStyle(lineWidth: width + 2, lineCap: cap, lineJoin: .round))
    ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: .round))
}

// MARK: - Page

struct OverviewPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TopBar().padding(.bottom, 4)
            Chips(items: [
                ("gauge.with.needle", "利用率", "62%", .run), ("square.stack.3d.up.fill", "并发峰值", "3.4", .run),
                ("hammer.fill", "工具调用", "1,286", .work), ("number", "Token", "3.1M", .work), ("checkmark.seal.fill", "已验收", "7", .work),
            ])
            HStack(spacing: 16) { Leverage().frame(width: 330); Running() }.frame(height: 256)
            HStack(spacing: 16) { Waiting(); Replies(); Away() }.frame(height: 244)
            HStack(spacing: 16) { Agents().frame(width: 520); Projects() }.frame(height: 236)
            Rhythm().frame(height: 244)
            Chips(items: [
                ("text.bubble.fill", "你发的提示", "29", .reply), ("hand.raised.slash.fill", "打断", "4", .reply),
                ("hand.raised.fill", "待你回复", "1", .wait), ("exclamationmark.triangle.fill", "卡住", "2 次", .wait),
            ], more: ("会话明细", "6"))
        }
        .padding(.horizontal, 40).padding(.top, 34).padding(.bottom, 36)
    }
}

/// The page's top bar: the title and date, the day's four totals, then the range controls.
private struct TopBar: View {
    private let totals: [(String, String, String)] = [("会话", "6", ""), ("轮次", "41", ""), ("Agent 工时", "9.6", "h"), ("你在场", "3.2", "h")]
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("概览").font(.system(size: 24, weight: .bold)).tracking(-0.3)
                Text("10月27日 周一").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 24)
            HStack(spacing: 32) {
                ForEach(totals, id: \.0) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.0).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        (Text(t.1).font(.system(size: 19, weight: .semibold).monospacedDigit())
                            + Text(verbatim: t.2.isEmpty ? "" : "\u{2009}" + t.2).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary))
                    }
                }
            }
            Spacer(minLength: 24)
            HStack(spacing: Space.xs) {
                IconButton(symbol: "chevron.left", help: "") {}
                IconButton(symbol: "chevron.right", help: "") {}.opacity(0.3)
                Segmented(items: [(0, "日"), (1, "周"), (2, "月")], selection: .constant(0)).padding(.leading, Space.m)
            }
        }
        .frame(height: 44)
    }
}

/// A row of small cards, one count each: a glyph in its hue, the word, the figure. `more` ends the
/// row with a link.
private struct Chips: View {
    let items: [(String, String, String, Tint)]
    var more: (String, String)? = nil
    var body: some View {
        HStack(spacing: 12) {
            ForEach(items, id: \.1) { it in
                HStack(spacing: 10) {
                    Image(systemName: it.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(it.3.hue)
                        .frame(width: 30, height: 30).background(Circle().fill(it.3.faint))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(it.1).font(.system(size: 11, weight: .medium)).foregroundStyle(ink2)
                        Text(it.2).font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(ink1)
                    }
                    Spacer(minLength: 0)
                }
                .chip()
            }
            if let more {
                HStack(spacing: 8) {
                    Text(more.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink1)
                    Text(more.1).font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(ink3)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(ink3)
                }
                .chip()
            }
        }
    }
}

private extension View {
    func chip() -> some View {
        padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 56).background(Surface(radius: 16))
    }
}

// MARK: - Accents

/// An accent's colour fill: deep at the crest, lighter at the foot, in both appearances.
private struct Wash {
    let top: Color, foot: Color, line: Color
    static let work = Wash(top: Color(light: NSColor(red: 0.2, green: 0.74, blue: 0.43, alpha: 1), dark: NSColor(red: 0.1, green: 0.5, blue: 0.3, alpha: 1)),
                           foot: Color(light: NSColor(red: 0.85, green: 0.96, blue: 0.89, alpha: 1), dark: NSColor(red: 0.2, green: 0.36, blue: 0.27, alpha: 1)),
                           line: Tint.work.hue)
    static let run = Wash(top: Color(light: NSColor(red: 0.22, green: 0.55, blue: 1, alpha: 1), dark: NSColor(red: 0.12, green: 0.32, blue: 0.78, alpha: 1)),
                          foot: Color(light: NSColor(red: 0.86, green: 0.92, blue: 1, alpha: 1), dark: NSColor(red: 0.2, green: 0.28, blue: 0.45, alpha: 1)),
                          line: Tint.run.hue)
}

/// Leverage, the day's headline: how many hours of agent work each hour of yours bought. The day's
/// running curve fills the card's foot.
private struct Leverage: View {
    private let t = Tint.work
    var body: some View {
        Panel {
            Head(title: "杠杆", tint: t, context: "今天")
            FigureRow(fig: figure("3.0", "×", t, FigureSize.accent), note: "Agent 9.6h ÷ 你 3.2h", delta: delta(true, "0.4×"))
        } art: {
            DayWave(wash: .work)
        }
    }
}

/// The day's running curve as a filled wave, the crest lit, now as the knob.
private struct DayWave: View {
    let wash: Wash
    var body: some View {
        Canvas { ctx, size in
            let top = size.height * 0.42, base = size.height + 4
            let vals = Day.running.enumerated().map { i, v in i <= Day.now ? v : Day.running[Day.now] * max(0, 1 - Double(i - Day.now) / 3) }
            let pts = vals.enumerated().map { i, v in
                CGPoint(x: size.width * CGFloat(i) / CGFloat(Day.n - 1), y: base - CGFloat(v / 3.4) * (base - top))
            }
            let crest = smooth(pts)
            var area = crest
            area.addLine(to: CGPoint(x: size.width, y: base + 10)); area.addLine(to: CGPoint(x: 0, y: base + 10)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [wash.top, wash.foot]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: base)))
            glow(ctx, crest, .color(wash.line), width: 2, blur: 6)
            knob(ctx, pts[Day.now], wash.line, r: 4.5)
        }
    }
}

/// While you were away: the share of that time agents kept working. The card fills to that share.
private struct Away: View {
    private let t = Tint.run
    var body: some View {
        Panel {
            Head(title: "你不在时", tint: t, context: "离开 2.0h")
            FigureRow(fig: figure("81", "%", t, FigureSize.accent), note: "1.6h 仍在干活 · 22m 卡住")
        } art: {
            AwayFill(level: 0.81, wash: .run)
        }
    }
}

/// Fills the card below its label band to `level`, a gentle crest along the top.
private struct AwayFill: View {
    let level: Double
    let wash: Wash
    var body: some View {
        Canvas { ctx, size in
            let band: CGFloat = 104, y0 = band + (size.height - band) * CGFloat(1 - level)
            let pts = (0...24).map { i -> CGPoint in
                let x = size.width * CGFloat(i) / 24
                return CGPoint(x: x, y: y0 + 4 * CGFloat(sin(Double(i) / 24 * 2 * .pi * 1.1 + 0.8)))
            }
            let crest = smooth(pts)
            var area = crest
            area.addLine(to: CGPoint(x: size.width, y: size.height)); area.addLine(to: CGPoint(x: 0, y: size.height)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [wash.top, wash.foot]), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: size.height)))
            glow(ctx, crest, .color(wash.line), width: 2, blur: 6)
        }
    }
}

// MARK: - Running

/// How many agents ran through the day, yesterday dotted behind, your time at the computer as a strip.
private struct Running: View {
    private let t = Tint.run
    var body: some View {
        Panel {
            Head(title: "同时在跑", tint: t, context: "现在 2 个")
            HStack(alignment: .lastTextBaseline) {
                FigureRow(fig: figure("2.4", "个", t), note: "平均 · 峰值 3.4 在 14:30", delta: delta(true, "0.3"))
                HStack(spacing: 14) {
                    Key(swatch: AnyView(Capsule().fill(t.hue).frame(width: 14, height: 3)), text: "今天")
                    Key(swatch: AnyView(HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Circle().fill(t.mid).frame(width: 3, height: 3) } }), text: "昨天")
                    Key(swatch: AnyView(Capsule().fill(ink2).frame(width: 14, height: 4)), text: "你在")
                }
                .padding(.bottom, 6)
            }
            RunCurve(t: t).padding(.top, 14)
        }
    }
}

private struct RunCurve: View {
    let t: Tint
    var body: some View {
        Canvas { ctx, size in
            let axis: CGFloat = 16, strip: CGFloat = 4, gap: CGFloat = 12
            let base = size.height - axis - strip - gap, top: CGFloat = 4
            let x = { (i: Double) in size.width * CGFloat(i / Double(Day.n - 1)) }
            let y = { (v: Double) in base - CGFloat(v / 3.6) * (base - top) }
            // Levels, as dotted hairlines in the hue.
            for l in [1.0, 2.0, 3.0] {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y(l))); p.addLine(to: CGPoint(x: size.width - 16, y: y(l)))
                ctx.stroke(p, with: .color(t.dim), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 4]))
                ctx.draw(tick("\(Int(l))", t.axis), at: CGPoint(x: size.width, y: y(l)), anchor: .trailing)
            }
            // Yesterday, dotted.
            let yp = smooth(Day.yesterday.enumerated().map { CGPoint(x: x(Double($0)), y: y($1)) })
            ctx.stroke(yp, with: .color(t.mid), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [0.1, 5]))
            // Today: an area dimming to nothing, the line brightening towards now.
            let pts = (0...Day.now).map { CGPoint(x: x(Double($0)), y: y(Day.running[$0])) }
            let line = smooth(pts)
            var area = line
            area.addLine(to: CGPoint(x: pts.last!.x, y: base)); area.addLine(to: CGPoint(x: 0, y: base)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [t.hue.opacity(0.32), t.hue.opacity(0)]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: base)))
            glow(ctx, line, .linearGradient(Gradient(colors: [t.hue.opacity(0.55), t.hue]), startPoint: .zero, endPoint: CGPoint(x: pts.last!.x, y: 0)), width: 2.4)
            // Now: a drop to the baseline and the knob.
            let now = pts.last!
            var drop = Path(); drop.move(to: now); drop.addLine(to: CGPoint(x: now.x, y: base + gap + strip))
            ctx.stroke(drop, with: .color(ink3), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            knob(ctx, now, t.hue)
            // Your time at the computer.
            let sy = base + gap + strip / 2
            var track = Path(); track.move(to: CGPoint(x: 0, y: sy)); track.addLine(to: CGPoint(x: x(Double(Day.now)), y: sy))
            ctx.stroke(track, with: .color(Color.primary.opacity(0.08)), style: StrokeStyle(lineWidth: strip, lineCap: .round))
            for r in Day.present {
                var p = Path(); p.move(to: CGPoint(x: x(Double(r.lowerBound)), y: sy)); p.addLine(to: CGPoint(x: x(Double(min(r.upperBound, Day.now))), y: sy))
                ctx.stroke(p, with: .color(ink2), style: StrokeStyle(lineWidth: strip, lineCap: .round))
            }
            // Hours.
            for (i, h) in [(0, "8:00"), (12, "11:00"), (24, "14:00"), (36, "17:00"), (47, "20:00")] {
                let anchor: UnitPoint = i == 0 ? .bottomLeading : i == 47 ? .bottomTrailing : .bottom
                ctx.draw(tick(h, t.axis), at: CGPoint(x: x(Double(i)), y: size.height), anchor: anchor)
            }
            ctx.draw(tick("现在", ink1), at: CGPoint(x: now.x, y: size.height), anchor: .bottom)
        }
    }
}

// MARK: - Waiting

/// Time agents waited on you: the day as a clock face from 08:00, each wait a bead on it, filled when
/// you were away and hollow when you were there but busy; the waits listed beside it.
private struct Waiting: View {
    private let t = Tint.wait
    var body: some View {
        Panel {
            Head(title: "在等你", tint: t, context: "5 次")
            FigureRow(fig: figure("34", "m", t), note: "最长 9m", delta: delta(false, "9m"))
            HStack(alignment: .center, spacing: 18) {
                WaitDial(t: t).frame(width: 128, height: 128).padding(-8)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Day.waits, id: \.0) { w in
                        HStack(spacing: 7) {
                            Circle().fill(w.2 ? t.hue : t.mid).frame(width: 6, height: 6)
                            Text(clock(w.0)).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(ink2)
                            Spacer(minLength: 0)
                            Text("\(w.1)m").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(w.2 ? t.hue : t.mid)
                        }
                    }
                    HStack(spacing: 10) {
                        (Text("● ").foregroundColor(t.hue) + Text("离开 22m").foregroundColor(ink3))
                        (Text("● ").foregroundColor(t.mid) + Text("在场 12m").foregroundColor(ink3))
                    }
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit()).padding(.top, 3)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private func clock(_ m: Int) -> String { String(format: "%d:%02d", 8 + m / 60, m % 60) }

private struct WaitDial: View {
    let t: Tint
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = size.width / 2 - 14, w: CGFloat = 10
            let ang = { (m: Int) in Double(m) / 720 * 2 * .pi }
            let now = ang(600)
            ctx.stroke(arc(c, r, 0, now), with: .color(t.dim), style: StrokeStyle(lineWidth: w, lineCap: .round))
            ctx.stroke(arc(c, r, now, 2 * .pi), with: .color(t.dim), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5]))
            for wt in Day.waits {
                let a = ang(wt.0), b = max(ang(wt.0 + wt.1), a + 0.05)
                if wt.2 {
                    glow(ctx, arc(c, r, a, b), .color(t.hue), width: w, blur: 5)
                } else {
                    ctx.stroke(arc(c, r, a, b), with: .color(t.mid), style: StrokeStyle(lineWidth: w, lineCap: .round))
                }
            }
            // Hour ticks inside the ring, four of them named.
            for h in 0..<12 {
                let a = Double(h) / 12 * 2 * .pi
                if h % 3 == 0 {
                    ctx.draw(tick("\(8 + h)", t.axis, 10), at: at(c, r - 18, a), anchor: .center)
                } else {
                    ctx.fill(disc(at(c, r - 17, a), 1), with: .color(t.dim))
                }
            }
            knob(ctx, at(c, r, now), t.hue, r: 3.6)
        }
        .overlay { Image(systemName: "hand.raised.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.hue) }
    }
}

// MARK: - Replies

/// How fast you answer once an agent asks: replies on a log scale from 10 s to 5 min, the middle half
/// lit and beamed towards the centre, the median as the knob, each reply a bead above.
private struct Replies: View {
    private let t = Tint.reply
    var body: some View {
        Panel {
            Head(title: "回复速度", tint: t, context: "38 次")
            FigureRow(fig: figure("48", "s", t), note: "中位 · 74% 在 1 分钟内", delta: delta(false, "12s"))
            ReplyArc(t: t).padding(.top, 2)
        }
    }
}

private struct ReplyArc: View {
    let t: Tint
    var body: some View {
        Canvas { ctx, size in
            let half = 1.08, r = (size.width / 2 - 8) / CGFloat(sin(half)), c = CGPoint(x: size.width / 2, y: 26 + r), w: CGFloat = 12
            let ang = { (s: Double) in -half + 2 * half * log(s / 10) / log(30) }
            let q1 = ang(25), q3 = ang(90), med = ang(48)
            // The beam from the lit band towards the centre.
            var beam = Path(); beam.move(to: c); beam.addArc(center: c, radius: r, startAngle: .radians(q1 - .pi / 2), endAngle: .radians(q3 - .pi / 2), clockwise: false); beam.closeSubpath()
            ctx.fill(beam, with: .radialGradient(Gradient(colors: [t.hue.opacity(0), t.hue.opacity(0), t.hue.opacity(0.3)]), center: c, startRadius: 0, endRadius: r))
            ctx.stroke(arc(c, r, -half, half), with: .color(t.dim), style: StrokeStyle(lineWidth: w, lineCap: .round))
            glow(ctx, arc(c, r, q1, q3), .color(t.hue), width: w, blur: 8)
            // Each reply.
            for (i, s) in Day.replies.sorted().enumerated() {
                let row = CGFloat(i % 2) * 5
                ctx.fill(disc(at(c, r + 13 + row, ang(min(max(s, 10), 300))), 1.5), with: .color(s > 180 ? t.hue : t.mid))
            }
            // The scale, inside the arc.
            for (s, l) in [(10.0, "10s"), (30, "30s"), (60, "1m"), (120, "2m"), (300, "5m")] {
                ctx.fill(disc(at(c, r, ang(s)), 1.2), with: .color(cardFill))
                ctx.draw(tick(l, s == 60 ? ink1 : t.axis), at: at(c, r - 22, ang(s)), anchor: .center)
            }
            knob(ctx, at(c, r, med), t.hue, r: 4.2)
        }
    }
}

// MARK: - Agents

/// Who did the work: one lane per agent, its share of the day's running as a line on a shared scale.
private struct Agents: View {
    private let t = Tint.work
    private let rows: [(logo: String, name: String, hours: String, share: Double, turns: Int)] = [
        ("claudecode", "Claude Code", "6.1", 0.64, 24), ("codex", "Codex", "2.6", 0.27, 12), ("cursor", "Cursor", "0.9", 0.09, 5),
    ]
    var body: some View {
        Panel {
            Head(title: "谁在干", tint: t, context: "3 个 Agent · 9.6h")
            FigureRow(fig: figure("64", "%", t), note: "由 Claude Code 完成", delta: delta(true, "8%"))
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { k, r in
                    HStack(spacing: 12) {
                        Logo(name: r.logo, size: 14, ink: t.hue).frame(width: 28, height: 28).background(Circle().fill(t.faint))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink1)
                            Text("\(Int(r.share * 100))% · \(r.turns) 轮").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(ink3)
                        }
                        .frame(width: 96, alignment: .leading)
                        Spark(t: t, k: k).frame(height: 26)
                        figure(r.hours, "h", t, 15).frame(width: 48, alignment: .trailing)
                    }
                }
            }
            .padding(.top, 14)
        }
    }
}

/// One agent's lane: its running through the day as a line with a fading area, on the same scale as
/// the others so the lanes compare.
private struct Spark: View {
    let t: Tint
    let k: Int
    private func value(_ i: Int) -> Double {
        let r = Day.running[i]
        switch k {
        case 0: return r * (0.55 + 0.12 * sin(Double(i) / 3))
        case 1: return r * (0.3 + 0.12 * sin(Double(i) / 4 + 2))
        default: return (18...30).contains(i) ? r * 0.28 * max(0, sin(Double(i - 18) / 12 * .pi)) : 0.04
        }
    }
    var body: some View {
        Canvas { ctx, size in
            let base = size.height - 1
            let pts = (0...Day.now).map { CGPoint(x: size.width * CGFloat($0) / CGFloat(Day.n - 1), y: base - CGFloat(value($0) / 2.4) * (base - 2)) }
            var rule = Path(); rule.move(to: CGPoint(x: 0, y: base)); rule.addLine(to: CGPoint(x: size.width, y: base))
            ctx.stroke(rule, with: .color(t.faint), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 4]))
            let line = smooth(pts)
            var area = line
            area.addLine(to: CGPoint(x: pts.last!.x, y: base)); area.addLine(to: CGPoint(x: 0, y: base)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [t.hue.opacity(k == 0 ? 0.3 : 0.18), t.hue.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: base)))
            ctx.stroke(line, with: .color(k == 0 ? t.hue : t.mid), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            ctx.fill(disc(pts.last!, 2.6), with: .color(k == 0 ? t.hue : t.mid))
        }
    }
}

// MARK: - Projects

/// Where the work went: a circle per project, area by hours, the largest lit.
private struct Projects: View {
    private let t = Tint.work
    private let items: [(name: String, hours: Double, waited: Int)] = [("YaaKanban", 3.2, 18), ("artrix-skills", 1.6, 12), ("wave-patch", 0.8, 4)]
    private func fill(_ i: Int) -> Color { i == 0 ? t.hue : t.hue.opacity(i == 1 ? 0.42 : 0.22) }
    var body: some View {
        Panel {
            Head(title: "在哪干", tint: t, context: "3 个项目")
            FigureRow(fig: figure("58", "%", t), note: "在 YaaKanban")
            HStack(alignment: .center, spacing: 20) {
                GeometryReader { geo in
                    let s = geo.size, unit = s.height * 0.4 / sqrt(items[0].hours), g: CGFloat = 4
                    let r = items.map { CGFloat(sqrt($0.hours)) * unit }
                    let c0 = CGPoint(x: r[0], y: s.height / 2 + 6)
                    let c1 = CGPoint(x: c0.x + (r[0] + r[1] + g) * 0.954, y: c0.y - (r[0] + r[1] + g) * 0.3)
                    let c2 = touching(c0, r[0] + r[2] + g, c1, r[1] + r[2] + g)
                    let cs = [c0, c1, c2]
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().fill(fill(i)).frame(width: 2 * r[i], height: 2 * r[i])
                                .overlay { if i < 2 { Text(String(format: "%.1fh", items[i].hours)).font(.system(size: i == 0 ? 17 : 12, weight: .semibold).monospacedDigit()).foregroundStyle(i == 0 ? cardFill : ink1) } }
                                .position(cs[i])
                        }
                    }
                }
                .frame(width: 166)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(fill(i)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink1).lineLimit(1)
                                (Text("等你 ").foregroundColor(ink3) + Text("\(p.waited)m").foregroundColor(Tint.wait.mid))
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                            }
                            Spacer(minLength: 0)
                            figure(String(format: "%.1f", p.hours), "h", t, 15)
                        }
                    }
                }
            }
            .padding(.top, 12)
        }
    }
}

/// The lower point at distance `d0` from `a` and `d1` from `b`.
private func touching(_ a: CGPoint, _ d0: CGFloat, _ b: CGPoint, _ d1: CGFloat) -> CGPoint {
    let dx = b.x - a.x, dy = b.y - a.y, d = sqrt(dx * dx + dy * dy)
    let l = (d0 * d0 - d1 * d1 + d * d) / (2 * d), h = sqrt(max(0, d0 * d0 - l * l))
    let m = CGPoint(x: a.x + dx * l / d, y: a.y + dy * l / d)
    let p1 = CGPoint(x: m.x - dy * h / d, y: m.y + dx * h / d), p2 = CGPoint(x: m.x + dy * h / d, y: m.y - dx * h / d)
    return p1.y > p2.y ? p1 : p2
}

// MARK: - Rhythm

/// The week: a row of quarter-hour cells per day, brighter where more agents ran; today's rest hollow,
/// now as the knob; each day's hours at the end of its row.
private struct Rhythm: View {
    private let t = Tint.run
    private let days = ["周二", "周三", "周四", "周五", "周六", "周日", "今天"]
    private let totals = ["7.8", "9.1", "8.4", "6.9", "2.1", "1.2", "9.6"]
    var body: some View {
        Panel {
            Head(title: "本周节奏", tint: t, context: "最忙 周三 14–17 点")
            HStack(alignment: .lastTextBaseline) {
                FigureRow(fig: figure("45.1", "h", t), note: "7 天 Agent 时长", delta: delta(true, "6.2h", "比上周"))
                HStack(spacing: 4) {
                    Text("少").foregroundStyle(ink3)
                    ForEach(0..<5, id: \.self) { l in RoundedRectangle(cornerRadius: 2, style: .continuous).fill(cell(l)).frame(width: 10, height: 10) }
                    Text("多").foregroundStyle(ink3)
                }
                .font(.system(size: 11, weight: .medium)).padding(.bottom, 6)
            }
            WeekGrid(t: t, days: days, totals: totals).padding(.top, 12)
        }
    }
    private func cell(_ l: Int) -> Color { l == 0 ? t.faint : t.hue.opacity([0, 0.3, 0.5, 0.75, 1][l]) }
}

private struct WeekGrid: View {
    let t: Tint
    let days: [String]
    let totals: [String]
    private func level(_ d: Int, _ i: Int) -> Int {
        if d == 6 { return i > Day.now ? -1 : min(4, Int(Day.running[i] * 1.25)) }
        let quiet = d == 4 || d == 5
        let v = max(0, 1.6 + 1.5 * sin(Double(i) / (4 + Double(d) * 0.4) + Double(d) * 1.7) + 0.8 * sin(Double(i * (d + 3)) * 0.9))
        return min(4, Int(v * (quiet ? 0.35 : 1)))
    }
    var body: some View {
        Canvas { ctx, size in
            let left: CGFloat = 40, right: CGFloat = 46, axis: CGFloat = 16
            let pitchX = (size.width - left - right) / CGFloat(Day.n), pitchY = (size.height - axis) / 7
            let cw = pitchX - 3, ch = min(pitchY - 4, 14)
            for d in 0..<7 {
                let cy = pitchY * (CGFloat(d) + 0.5)
                let today = d == 6
                ctx.draw(tick(days[d], today ? ink1 : ink3, 11), at: CGPoint(x: 0, y: cy), anchor: .leading)
                for i in 0..<Day.n {
                    let r = CGRect(x: left + pitchX * CGFloat(i) + 1.5, y: cy - ch / 2, width: cw, height: ch)
                    let p = Path(roundedRect: r, cornerRadius: 2.5, style: .continuous)
                    let l = level(d, i)
                    if l < 0 {
                        ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2.5, style: .continuous), with: .color(t.faint), lineWidth: 1)
                    } else {
                        ctx.fill(p, with: .color(l == 0 ? t.faint : t.hue.opacity([0, 0.3, 0.5, 0.75, 1][l])))
                    }
                }
                let total = tick(totals[d] + "h", today ? t.hue : ink2, 11.5)
                ctx.draw(total, at: CGPoint(x: size.width, y: cy), anchor: .trailing)
            }
            let nowRect = CGPoint(x: left + pitchX * (CGFloat(Day.now) + 0.5), y: pitchY * 6.5)
            knob(ctx, nowRect, t.hue, r: 4)
            for (i, h) in [(0, "8:00"), (12, "11:00"), (24, "14:00"), (36, "17:00"), (48, "20:00")] {
                let anchor: UnitPoint = i == 0 ? .bottomLeading : i == 48 ? .bottomTrailing : .bottom
                ctx.draw(tick(h, t.axis), at: CGPoint(x: left + pitchX * CGFloat(i), y: size.height), anchor: anchor)
            }
        }
    }
}
