import AppKit
import SwiftUI

// Shared data and drawing for the style-direction boards. Every board shows the same four tiles
// (leverage with the day's curve, agents waiting on you, reply speed, while you were away) so the
// directions differ only in style.

enum Day {
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
    static let waits: [Range<Int>] = [9..<12, 13..<14, 22..<26, 33..<34]
    static let replies: [Double] = (0..<34).map { (k: Int) -> Double in
        let u = { (m: Double) in (Double(k + 1) * m).truncatingRemainder(dividingBy: 1) }
        return 48 * exp(0.6 * (u(0.618034) + u(0.414214) + u(0.732051) - 1.5) * 2)
    } + [205, 240, 270, 290]
}

/// The status hues, tuned to sit on black as well as on white.
enum Hue {
    static let work = Color(red: 0.19, green: 0.84, blue: 0.47), lime = Color(red: 0.62, green: 0.95, blue: 0.36)
    static let wait = Color(red: 1, green: 0.27, blue: 0.25), reply = Color(red: 1, green: 0.6, blue: 0.04)
    static let away = Color(red: 0.1, green: 0.55, blue: 1), cyan = Color(red: 0.35, green: 0.85, blue: 1)
}

func disc(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }

func smooth(_ pts: [CGPoint]) -> Path {
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
func at(_ c: CGPoint, _ r: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a))) }
func arc(_ c: CGPoint, _ r: CGFloat, _ a: Double, _ b: Double) -> Path {
    var p = Path()
    p.addArc(center: c, radius: r, startAngle: .radians(a - .pi / 2), endAngle: .radians(b - .pi / 2), clockwise: false)
    return p
}

/// The day's curve across a rect, today up to now.
func dayPoints(_ r: CGRect, top: Double = 3.4, upTo: Int = Day.now, _ data: [Double] = Day.running) -> [CGPoint] {
    (0...upTo).map { CGPoint(x: r.minX + r.width * CGFloat($0) / CGFloat(Day.n - 1), y: r.maxY - r.height * CGFloat(data[$0] / top)) }
}

/// Digits in one face, units smaller beside them.
struct Fig: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .semibold
    var design: Font.Design = .default
    var ink: Color = .primary
    var unit: Color = .secondary
    var unitScale: CGFloat = 0.5
    var tracking: CGFloat = 0

    var body: some View { line.lineLimit(1).fixedSize() }

    var line: Text {
        runs.reduce(Text(verbatim: "")) { line, run in
            line + (run.figure
                ? Text(verbatim: run.text).font(.system(size: size, weight: weight, design: design).monospacedDigit())
                    .tracking(tracking).foregroundStyle(ink)
                : Text(verbatim: run.text).font(.system(size: (size * unitScale).rounded(), weight: weight == .regular ? .medium : weight, design: design))
                    .foregroundStyle(unit))
        }
    }

    private var runs: [(text: String, figure: Bool)] {
        var out: [(text: String, figure: Bool)] = []
        for c in text {
            let figure = "0123456789.,:".contains(c)
            if out.last?.figure == figure { out[out.count - 1].text.append(c) } else { out.append((String(c), figure)) }
        }
        return out
    }
}

/// A board: the direction's name, the wide tile, three tiles under it.
struct Board<H: View, A: View, B: View, C: View>: View {
    let tag: String, title: String, note: String
    var dark = false
    @ViewBuilder var hero: H
    @ViewBuilder var a: A
    @ViewBuilder var b: B
    @ViewBuilder var c: C

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tag).font(.system(size: 20, weight: .bold))
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(note).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .foregroundStyle(dark ? .white : .black).padding(.bottom, 6)
            hero.frame(height: 214)
            HStack(spacing: 14) { a; b; c }.frame(height: 206)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
