import SwiftUI
import AppKit

/// Soft lights in acid hues that drift and change shape under a frosted pane.
struct GlassLight: View {
    let t: Double
    var bright = false
    @Environment(\.colorScheme) private var scheme
    // Each light: hue, centre, loop (s), phase.
    private static let lights: [(color: Color, x: Double, y: Double, period: Double, phase: Double)] = [
        (Color(red: 0.72, green: 1, blue: 0.18), 0.18, 0.7, 17, 0),      // acid lime
        (Color(red: 0.1, green: 0.9, blue: 1), 0.55, 0.2, 23, 1.7),      // cyan
        (Color(red: 0.55, green: 0.36, blue: 1), 0.86, 0.75, 29, 3.4),   // violet
        (Color(red: 1, green: 0.35, blue: 0.75), 0.4, 1.1, 37, 5.1),     // a touch of pink
    ]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let dark = scheme == .dark
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: h * 0.32))
                if dark { l.blendMode = .screen }
                for s in Self.lights {
                    let a = 2 * .pi * t / s.period + s.phase
                    // Drift, and stretch one way then the other: the morph.
                    let c = CGPoint(x: w * (s.x + 0.14 * sin(a)), y: h * (s.y + 0.3 * cos(a * 1.4)))
                    let rx = h * (0.9 + 0.35 * sin(a * 0.8)), ry = h * (0.55 + 0.2 * cos(a * 1.1))
                    l.opacity = (dark ? 0.55 : 0.7) * (bright ? 1.25 : 1)
                    l.fill(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)), with: .color(s.color))
                }
            }
        }
    }
}

struct GlassCard: View {
    let t: Double
    var hover = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 6) {
            Text("概览").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary.opacity(0.9))
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary.opacity(hover ? 0.75 : 0.45))
        }
        .padding(.horizontal, 14)
        .frame(width: 260, height: 62)
        .background {
            ZStack {
                shape.fill(dark ? Color(white: 0.1) : Color(white: 0.97))
                GlassLight(t: t, bright: hover)
                // The frost: a pale veil over the light, clearer towards the foot.
                LinearGradient(colors: [.white.opacity(dark ? 0.1 : 0.45), .white.opacity(dark ? 0.02 : 0.15)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(shape)
        }
        // The pane's edge: lit at the top left, fading round to the foot.
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.35 : 0.9), .white.opacity(dark ? 0.04 : 0.2), .white.opacity(dark ? 0.12 : 0.5)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: .black.opacity(dark ? 0.3 : 0.08), radius: 10, y: 4)
    }
}

struct Sheet: View {
    let scheme: ColorScheme
    var body: some View {
        VStack(spacing: 14) {
            ForEach([0.0, 5, 10, 15, 20], id: \.self) { t in
                HStack(spacing: 14) { GlassCard(t: t); GlassCard(t: t, hover: true) }
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
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/card/glass-\(name).png"))
        }
    }
}
