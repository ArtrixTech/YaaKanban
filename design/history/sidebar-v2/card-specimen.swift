import SwiftUI
import AppKit

struct Arcs: View {
    let tints: [Color]
    let bright: Bool

    var body: some View {
        Canvas { ctx, size in
            let tints = self.tints.isEmpty ? [Color.white.opacity(0.4)] : self.tints
            let outer = size.height * 0.66, cx = size.width - size.height * 0.4, cy = size.height * 1.08
            let step = 0.2
            for (i, tint) in tints.enumerated() {
                let r = outer * (1 - step * CGFloat(i))
                let c = CGPoint(x: cx, y: cy + (outer - r) * 0.55)
                let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                let top = CGPoint(x: c.x, y: c.y - r), down = CGPoint(x: c.x, y: c.y - r * 0.15)
                ctx.drawLayer { halo in
                    halo.addFilter(.blur(radius: 16))
                    halo.opacity = bright ? 0.7 : 0.5
                    halo.fill(disc, with: .linearGradient(Gradient(colors: [tint, tint.opacity(0)]), startPoint: top, endPoint: CGPoint(x: c.x, y: c.y - r * 0.5)))
                }
                ctx.fill(disc, with: .color(Color(white: 0.05)))
                ctx.fill(disc, with: .linearGradient(Gradient(stops: [.init(color: tint.opacity(0.6), location: 0),
                                                                       .init(color: tint.opacity(0.18), location: 0.25),
                                                                       .init(color: tint.opacity(0.04), location: 0.6)]),
                                                     startPoint: top, endPoint: CGPoint(x: c.x, y: c.y + r * 0.2)))
                let rim = GraphicsContext.Shading.linearGradient(Gradient(colors: [tint, tint.opacity(0)]), startPoint: top, endPoint: down)
                ctx.drawLayer { glow in
                    glow.addFilter(.blur(radius: 4))
                    glow.opacity = bright ? 1 : 0.85
                    glow.stroke(disc, with: rim, lineWidth: 4)
                }
                ctx.stroke(disc, with: .linearGradient(Gradient(colors: [.white.opacity(0.9), tint.opacity(0.8), tint.opacity(0)]),
                                                       startPoint: top, endPoint: down), lineWidth: 1)
            }
        }
    }
}

struct Chip: View {
    let n: Int; let tint: Color
    var body: some View {
        HStack(spacing: 3) { Circle().fill(tint).frame(width: 6, height: 6); Text("\(n)").font(.system(size: 11, weight: .semibold)).monospacedDigit() }
            .padding(.horizontal, 7).padding(.vertical, 3).background(tint.opacity(0.13), in: Capsule())
    }
}

struct Card: View {
    let states: [(Color, Int)]
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("概览").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                Spacer()
                ForEach(states.indices, id: \.self) { i in Chip(n: states[i].1, tint: states[i].0) }
            }
            Spacer()
            Text("今天的杠杆").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            (Text("4.2").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
             + Text("\u{2009}×").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(red: 0.3, green: 0.86, blue: 0.5)))
        }
        .padding(14)
        .frame(width: 260, height: 132, alignment: .leading)
        .background { ZStack { Color(white: 0.06); Arcs(tints: states.map(\.0).reversed(), bright: false) } }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 1) }
        .environment(\.colorScheme, .dark)
    }
}

let blue = Color(red: 0.04, green: 0.52, blue: 1), purple = Color(red: 0.75, green: 0.52, blue: 1)
let green = Color(red: 0.19, green: 0.82, blue: 0.35), orange = Color(red: 1, green: 0.62, blue: 0.04)
let view = HStack(spacing: 16) {
    VStack(spacing: 16) { Card(states: [(blue, 6)]); Card(states: [(green, 1), (blue, 5)]) }
    VStack(spacing: 16) { Card(states: [(purple, 1), (orange, 1), (green, 2), (blue, 3)]); Card(states: []) }
}
.padding(24).background(Color(white: 0.955))

MainActor.assumeIsolated {
    let r = ImageRenderer(content: view); r.scale = 2
    let img = r.nsImage!
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/card/cards.png"))
}
