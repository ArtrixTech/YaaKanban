import SwiftUI
import AppKit

struct BrandGlyph: View {
    var size: CGFloat

    var body: some View {
        let u = size / 38
        HStack(alignment: .top, spacing: 4 * u) {
            column(36, 0.95, u)
            column(24, 0.75, u)
            ZStack(alignment: .top) {
                column(14, 0.55, u)
                Circle().fill(LinearGradient(colors: [Color(red: 0.06, green: 0.73, blue: 0.51), Color(red: 0.29, green: 0.87, blue: 0.5)],
                                             startPoint: .top, endPoint: .bottom))
                    .frame(width: 10 * u, height: 10 * u)
                    .offset(y: 26 * u)
            }
        }
        .frame(width: 38 * u, height: 36 * u, alignment: .topLeading)
        .accessibilityLabel(Text(verbatim: "YaaKanban"))
    }

    private func column(_ h: CGFloat, _ opacity: Double, _ u: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4 * u, style: .continuous).fill(Color.primary.opacity(opacity))
            .frame(width: 10 * u, height: h * u)
    }
}


/// Leverage on a cool-to-hot scale, by doublings: 1x and under blue, about 3x violet, 8x and over red.
struct LeverageHeat {
    let level: Double?
    init(_ leverage: Double?) { level = leverage.map { min(max(log2(max($0, 1)) / 3, 0), 1) } }
    var hue: Double { 0.6 + 0.4 * (level ?? 0) }
    var sat: Double { level == nil ? 0.12 : 0.85 }
    func color(_ shift: Double = 0, sat s: Double = 1, b: Double) -> Color {
        Color(hue: (hue + shift + 1).truncatingRemainder(dividingBy: 1), saturation: sat * s, brightness: b)
    }
}

/// Light rising from the pane's foot: a broad glow in the heat's hue, a paler core along the edge,
/// lobes either side a shade off in hue, each drifting and changing shape on its own slow loop.
struct FootGlow: View {
    let heat: LeverageHeat; let t: Double; var bright = false
    private static let lobes: [(x: Double, period: Double, phase: Double, shift: Double)] = [
        (0.25, 19, 0, 0.035), (0.75, 23, 2.2, -0.035), (0.5, 29, 4.1, 0)]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, all = Path(CGRect(origin: .zero, size: size))
            ctx.fill(all, with: .color(heat.color(b: 0.07)))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: h * 0.3))
                l.blendMode = .screen
                l.opacity = bright ? 1 : 0.85
                for s in Self.lobes {
                    let a = 2 * .pi * t / s.period + s.phase
                    let c = CGPoint(x: w * (s.x + 0.12 * sin(a)), y: h * (1.05 + 0.08 * cos(a * 1.3)))
                    let rx = w * (0.32 + 0.08 * sin(a * 0.7)), ry = h * (0.5 + 0.12 * cos(a * 0.9))
                    l.fill(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)), with: .color(heat.color(s.shift, b: heat.level == nil ? 0.4 : 0.85)))
                }
                // The pale core hugging the edge.
                let a = 2 * .pi * t / 17
                let cx = w * (0.5 + 0.18 * sin(a)), rx = w * (0.38 + 0.06 * cos(a * 1.2)), ry = h * 0.22
                l.fill(Path(ellipseIn: CGRect(x: cx - rx, y: h * 1.02 - ry, width: 2 * rx, height: 2 * ry)), with: .color(heat.color(-0.06, sat: 0.5, b: heat.level == nil ? 0.5 : 1)))
            }
        }
    }
}

struct Card: View {
    let lev: Double?; var onOverview = false; let t: Double; var hover = false
    var body: some View {
        let heat = LeverageHeat(lev)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    BrandGlyph(size: 12)
                    Text(verbatim: "YaaKanban").font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary.opacity(0.6))
                }
                Text("概览").font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary.opacity(0.95))
            }
            Spacer()
            if !onOverview {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(verbatim: lev.map { String(format: "%.1f", $0) } ?? "–").font(.system(size: 20, weight: .semibold).monospacedDigit()).tracking(-0.4)
                        if lev != nil { Text(verbatim: "×").font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary.opacity(0.6)) }
                    }.foregroundStyle(.primary.opacity(0.95))
                    Text("今天的杠杆").font(.system(size: 10, weight: .medium)).foregroundStyle(.primary.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 14).frame(width: 260, height: 72)
        .background { FootGlow(heat: heat, t: t, bright: hover).clipShape(shape) }
        .overlay {
            shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .white.opacity(0.05), location: 0.45),
                                                     .init(color: heat.color(-0.06, sat: 0.5, b: 1).opacity(hover ? 0.75 : 0.5), location: 1)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .environment(\.colorScheme, .dark)
    }
}

struct Sheet: View {
    let scheme: ColorScheme
    var body: some View {
        let rows: [(Double?, Bool, Bool, Double)] = [(1.0, false, false, 0), (2.0, false, false, 6), (3.0, false, false, 12), (5.0, false, false, 18), (8.5, false, false, 24), (nil, false, false, 30)]
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 14) { Card(lev: r.0, t: r.3); Card(lev: r.0, t: r.3 + 9, hover: true); Card(lev: r.0, onOverview: true, t: r.3 + 4) }
            }
        }
        .padding(24)
        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.955))
    }
}

@main struct Main {
    @MainActor static func main() {
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let r = ImageRenderer(content: Sheet(scheme: scheme)); r.scale = 2
            let rep = NSBitmapImageRep(data: r.nsImage!.tiffRepresentation!)!
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/card5/heat-\(name).png"))
        }
    }
}
