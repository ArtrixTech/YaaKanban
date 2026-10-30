import SwiftUI
import AppKit

// --- the parts that go into the app ---

/// Leverage on a cool-to-hot scale: 1× and under blue, about 3× violet, 8× and over red.
struct LeverageHeat {
    let level: Double?
    init(_ leverage: Double?) { level = leverage.map { min(max(log2(max($0, 1)) / 3, 0), 1) } }
    private var h: Double { 0.6 + 0.4 * (level ?? 0) }
    private var sat: Double { level == nil ? 0.12 : 0.82 }
    var deep: Color { Color(hue: h.truncatingRemainder(dividingBy: 1), saturation: sat, brightness: 0.32) }
    var main: Color { Color(hue: h.truncatingRemainder(dividingBy: 1), saturation: sat, brightness: 0.86) }
    func glow(_ shift: Double) -> Color { Color(hue: (h + shift + 1).truncatingRemainder(dividingBy: 1), saturation: sat * 0.75, brightness: 1) }
}

/// The leverage panel's light: deep at the top, bright at the foot, with three soft lights
/// drifting on slow, unrelated loops and a faint sheen crossing now and then.
struct HeatField: View {
    let heat: LeverageHeat
    let t: Double
    var bright = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, all = Path(CGRect(origin: .zero, size: size))
            ctx.fill(all, with: .linearGradient(Gradient(colors: [heat.deep, heat.main]), startPoint: .zero, endPoint: CGPoint(x: w * 0.3, y: h)))
            let lights: [(period: Double, phase: Double, shift: Double, x: Double, y: Double)] = [
                (13, 0, 0.04, 0.2, 0.85), (19, 2.1, -0.05, 0.85, 0.7), (29, 4.2, 0.0, 0.5, 1.0)]
            ctx.drawLayer { l in
                l.blendMode = .screen
                for (i, s) in lights.enumerated() {
                    let a = 2 * .pi * t / s.period + s.phase
                    let c = CGPoint(x: w * (s.x + 0.32 * sin(a)), y: h * (s.y + 0.16 * cos(a * 1.3)))
                    let r = h * (0.62 + 0.08 * sin(a * 0.7 + Double(i)))
                    l.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .radialGradient(Gradient(colors: [heat.glow(s.shift).opacity(bright ? 0.6 : 0.45), .clear]),
                                                 center: c, startRadius: 0, endRadius: r))
                }
            }
            // The sheen: a soft diagonal band, crossing once every 12 s and idle the rest.
            let p = (t / 12).truncatingRemainder(dividingBy: 1) * 3 - 1
            ctx.drawLayer { l in
                l.translateBy(x: w * p, y: 0)
                l.rotate(by: .degrees(24))
                l.fill(Path(CGRect(x: 0, y: -h, width: w * 0.35, height: h * 3)),
                       with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.09), .clear]),
                                             startPoint: .zero, endPoint: CGPoint(x: w * 0.35, y: 0)))
            }
            // Keeps the top deep, where the figure is read against it.
            ctx.fill(all, with: .linearGradient(Gradient(colors: [.black.opacity(0.32), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.6)))
        }
    }
}

/// The black side: the panel's hue bleeding faintly in from the seam, breathing slowly.
struct SeamGlow: View {
    let heat: LeverageHeat
    let t: Double
    var body: some View {
        Canvas { ctx, size in
            let r = size.height * 1.1, c = CGPoint(x: 0, y: size.height * (0.55 + 0.1 * sin(2 * .pi * t / 17)))
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [heat.main.opacity(0.16 + 0.05 * sin(2 * .pi * t / 9)), .clear]),
                                           center: c, startRadius: 0, endRadius: r))
        }
    }
}

// --- specimen layout ---

struct Dot: View {
    let n: Int; let tint: Color
    var body: some View {
        HStack(spacing: 3) { Circle().fill(tint).frame(width: 6, height: 6); Text("\(n)").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.85)) }
    }
}

struct Card: View {
    let lev: Double?
    let t: Double
    let counts: [(Color, Int)]
    var body: some View {
        let heat = LeverageHeat(lev)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(lev.map { String(format: "%.1f", $0) } ?? "–").font(.system(size: 30, weight: .semibold)).monospacedDigit().tracking(-0.6)
                    Text("×").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.75)).baselineOffset(10)
                }
                .foregroundStyle(.white)
                Text("今天的杠杆").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(14)
            .frame(width: 104, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(HeatField(heat: heat, t: t))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("概览").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                    Spacer(minLength: 4)
                    Text("↓0.6×").font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.18)))
                }
                Text("Agent 2.5时 ÷ 你 34分").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.45)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                HStack(spacing: 8) {
                    ForEach(counts.indices, id: \.self) { i in Dot(n: counts[i].1, tint: counts[i].0) }
                    Spacer(minLength: 4)
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        .frame(width: 30, height: 20).background(Capsule().fill(.white.opacity(0.12)))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background { ZStack { Color(white: 0.07); SeamGlow(heat: heat, t: t) } }
        }
        .frame(width: 260, height: 112)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 1) }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .environment(\.colorScheme, .dark)
    }
}

let blue = Color(red: 0.04, green: 0.52, blue: 1), purple = Color(red: 0.75, green: 0.52, blue: 1)
let green = Color(red: 0.19, green: 0.82, blue: 0.35), orange = Color(red: 1, green: 0.62, blue: 0.04)
let levs: [Double?] = [1.1, 2.0, 3.0, 4.4, 8.0, nil]

struct Sheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(levs.indices, id: \.self) { i in
                HStack(spacing: 14) {
                    ForEach([0.0, 4.0, 8.0], id: \.self) { t in
                        Card(lev: levs[i], t: t + Double(i), counts: i % 2 == 0 ? [(blue, 6)] : [(purple, 1), (orange, 1), (green, 2), (blue, 3)])
                    }
                }
            }
        }
        .padding(24).background(Color(white: 0.955))
    }
}

@main struct Main {
    @MainActor static func main() {
        let r = ImageRenderer(content: Sheet()); r.scale = 2
        let rep = NSBitmapImageRep(data: r.nsImage!.tiffRepresentation!)!
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/card/split.png"))
    }
}
