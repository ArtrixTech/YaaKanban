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

struct GlassLight: View {
    let t: Double
    var bright = false
    @Environment(\.colorScheme) private var scheme
    private static let lights: [(color: Color, x: Double, y: Double, period: Double, phase: Double)] = [
        (Color(red: 0.72, green: 1, blue: 0.18), 0.18, 0.7, 17, 0),
        (Color(red: 0.1, green: 0.9, blue: 1), 0.55, 0.2, 23, 1.7),
        (Color(red: 0.55, green: 0.36, blue: 1), 0.86, 0.75, 29, 3.4),
        (Color(red: 1, green: 0.35, blue: 0.75), 0.4, 1.1, 37, 5.1),
    ]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, dark = scheme == .dark
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: h * 0.32))
                if dark { l.blendMode = .screen }
                l.opacity = (dark ? 0.55 : 0.7) * (bright ? 1.25 : 1)
                for s in Self.lights {
                    let a = 2 * .pi * t / s.period + s.phase
                    let c = CGPoint(x: w * (s.x + 0.14 * sin(a)), y: h * (s.y + 0.3 * cos(a * 1.4)))
                    let rx = h * (0.9 + 0.35 * sin(a * 0.8)), ry = h * (0.55 + 0.2 * cos(a * 1.1))
                    l.fill(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)), with: .color(s.color))
                }
            }
        }
    }
}

struct Pane<Content: View>: View {
    let t: Double; var hover = false; var height: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content.padding(.horizontal, 14).frame(width: 260, height: height)
        .background { ZStack {
            shape.fill(dark ? Color(white: 0.1) : Color(white: 0.97))
            GlassLight(t: t, bright: hover)
            LinearGradient(colors: [.white.opacity(dark ? 0.1 : 0.45), .white.opacity(dark ? 0.02 : 0.15)], startPoint: .top, endPoint: .bottom)
        }.clipShape(shape) }
        .overlay { shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.35 : 0.9), .white.opacity(dark ? 0.04 : 0.2), .white.opacity(dark ? 0.12 : 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1) }
        .shadow(color: .black.opacity(dark ? 0.3 : 0.08), radius: 10, y: 4)
    }
}

struct Lev: View {
    let v: Double?
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: v.map { String(format: "%.1f", $0) } ?? "–").font(.system(size: 20, weight: .semibold).monospacedDigit()).tracking(-0.4)
                if v != nil { Text(verbatim: "×").font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary.opacity(0.6)) }
            }.foregroundStyle(.primary.opacity(0.9))
            Text("今天的杠杆").font(.system(size: 10, weight: .medium)).foregroundStyle(.primary.opacity(0.5))
        }
    }
}

// A: one row, glyph + 概览, leverage on the right.
struct A: View {
    let t: Double; let v: Double?; let onOverview: Bool
    var body: some View {
        Pane(t: t, height: 64) {
            HStack(spacing: 8) {
                BrandGlyph(size: 18)
                Text("概览").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary.opacity(0.9))
                Spacer()
                if !onOverview { Lev(v: v) }
            }
        }
    }
}

// B: the name as a small caption over 概览, leverage on the right.
struct B: View {
    let t: Double; let v: Double?; let onOverview: Bool
    var body: some View {
        Pane(t: t, height: 72) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        BrandGlyph(size: 12)
                        Text(verbatim: "YaaKanban").font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary.opacity(0.6))
                    }
                    Text("概览").font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary.opacity(0.9))
                }
                Spacer()
                if !onOverview { Lev(v: v) }
            }
        }
    }
}

struct Sheet: View {
    let scheme: ColorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([(3.2, false, 0.0), (nil, false, 8.0), (3.2, true, 16.0)] as [(Double?, Bool, Double)], id: \.2) { v, on, t in
                HStack(spacing: 14) { A(t: t, v: v, onOverview: on); B(t: t, v: v, onOverview: on) }
            }
        }
        .padding(24)
        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.955))
        .environment(\.colorScheme, scheme)
    }
}

@main struct Main {
    @MainActor static func main() {
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let r = ImageRenderer(content: Sheet(scheme: scheme)); r.scale = 2
            let rep = NSBitmapImageRep(data: r.nsImage!.tiffRepresentation!)!
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/card5/\(name).png"))
        }
    }
}
