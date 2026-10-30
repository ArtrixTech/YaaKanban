import AppKit
import SwiftUI

// Leverage bars: ways to show the period before behind each bar at the same width and centre.
// Build: swiftc -o /tmp/lev-study Sources/YaaKanban/DesignSystem.swift design/history/leverage-v1/main.swift
// Run:   /tmp/lev-study <out-dir>

let out = CommandLine.arguments.dropFirst().first ?? "/tmp/lev-study"

enum Variant: String, CaseIterable {
    case wide = "现状：宽虚影"
    case notch = "A 切口"
    case cap = "B 顶线"
    case gain = "C 增量"
    case hatch = "D 斜纹"

    var note: String {
        switch self {
        case .wide: "上周更宽，在后"
        case .notch: "同宽虚影在后；被盖住时在柱上切一道缝"
        case .cap: "同宽虚影在后；上周高度画一条横线"
        case .gain: "与上周重合的部分变淡，超出的部分亮"
        case .hatch: "上周是斜纹，盖在柱上也看得见"
        }
    }
}

/// One chart's days: this period, the one before, which are lit, and where today falls.
struct Days {
    let values: [Double?]
    let before: [Double?]
    let lit: Set<Int>
    let today: Int
    let labels: [String?]
    var monthly: Bool { values.count > 7 }

    static let week = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    /// The day view: Friday lit; up, down, up, level, a big rise, then two days still to come.
    static let day = Days(values: [3.8, 1.8, 3.5, 4.0, 6.6, nil, nil], before: [2.0, 2.6, 1.6, 4.1, 2.2, 1.2, 2.4],
                          lit: [4], today: 4, labels: week.enumerated().map { $0.offset == 4 ? "今天" : $0.element })
    /// The week view of a past week: all lit; a day with no last week, a day with nothing this
    /// week, an exact tie, below 1×, and a rise far above last week.
    static let pastWeek = Days(values: [2.0, 0.6, nil, 5.2, 3.0, 1.1, 4.4], before: [3.5, nil, 2.8, 5.0, 3.0, 0.4, 1.0],
                               lit: Set(0..<7), today: 99, labels: week)
    /// The month view: 31 thin bars, today the 30th.
    static let month: Days = {
        let v: [Double?] = (0..<31).map { i in i >= 29 ? nil : i < 20 ? nil : [2.1, 2.0, 1.8, 2.4, 1.2, 2.2, 3.0, 1.6, 2.8, 3.2, 4.6][i - 20] }
        let b: [Double?] = (0..<31).map { i in [1.4, 2.2, 3.1, 1.9, 0.8, 2.6, 2.0, 1.5, 2.9, 3.4, 2.1][i % 11] }
        return Days(values: v.enumerated().map { $0.offset == 29 ? 2.7 : $0.element }, before: b, lit: Set(0..<31), today: 29,
                    labels: (0..<31).map { $0 == 29 ? "今天" : $0 % 7 == 0 && $0 < 28 ? "\($0 + 1)日" : nil })
    }()
}

func tick(_ t: String, _ c: Color) -> Text { Text(verbatim: t).font(.figure(10.5, .medium)).foregroundStyle(c) }

/// Diagonal lines across `r`, clipped to each of `clips`.
func hatch(_ ctx: GraphicsContext, _ r: CGRect, _ clips: [Path], _ color: Color, step: CGFloat) {
    ctx.drawLayer { l in
        for c in clips { l.clip(to: c) }
        var p = Path(), x = r.minX - r.height
        while x < r.maxX { p.move(to: CGPoint(x: x, y: r.maxY)); p.addLine(to: CGPoint(x: x + r.height, y: r.minY)); x += step }
        l.stroke(p, with: .color(color), lineWidth: 1)
    }
}

struct Bars: View {
    let days: Days
    let variant: Variant
    let ramp = Ramp.work

    var body: some View {
        Canvas { ctx, size in
            let n = days.values.count, monthly = days.monthly
            let axis: CGFloat = 16, right: CGFloat = 22, top: CGFloat = monthly ? 4 : 16
            let base = size.height - axis, pitch = (size.width - right) / CGFloat(n)
            let ceiling = max(((days.values + days.before).compactMap { $0 }.max() ?? 0) * 1.1, 1.5)
            let ghostWidth = min(pitch * (monthly ? 0.8 : 0.7), 36)
            let w = variant == .wide ? ghostWidth * 0.64 : min(pitch * (monthly ? 0.62 : 0.5), 26)
            func y(_ v: Double) -> CGFloat { base - CGFloat(v / ceiling) * (base - top) }
            func rect(_ cx: CGFloat, _ w: CGFloat, _ v: Double) -> CGRect { CGRect(x: cx - w / 2, y: y(v), width: w, height: max(base - y(v), 2)) }
            func shape(_ r: CGRect) -> Path { Path(roundedRect: r, cornerRadius: min(r.width / 2, 4), style: .continuous) }
            let one = y(1)
            var even = Path(); even.move(to: CGPoint(x: 0, y: one)); even.addLine(to: CGPoint(x: size.width - right, y: one))
            ctx.stroke(even, with: .color(ramp.mid.opacity(0.6)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 4]))
            ctx.draw(tick("1×", Ink.tertiary), at: CGPoint(x: size.width, y: one), anchor: .trailing)
            for i in 0..<n {
                let cx = pitch * (CGFloat(i) + 0.5), lit = days.lit.contains(i)
                let v = days.values[i], b = days.before[i], fill = lit ? ramp.hue : ramp.mid
                let bar = v.map { shape(rect(cx, w, $0)) }, ghost = b.map { shape(rect(cx, variant == .wide ? ghostWidth : w, $0)) }
                switch variant {
                case .wide, .notch, .cap:
                    if let ghost { ctx.fill(ghost, with: .color(ramp.dim)) }
                    if let bar { ctx.fill(bar, with: .color(fill)) }
                    if let b, let v, variant == .notch, b < v {
                        var cut = Path(); cut.move(to: CGPoint(x: cx - w / 2, y: y(b))); cut.addLine(to: CGPoint(x: cx + w / 2, y: y(b)))
                        ctx.stroke(cut, with: .color(Fill.widget), lineWidth: monthly ? 1 : 1.5)
                    }
                    if let b, variant == .cap {
                        var cap = Path(); cap.move(to: CGPoint(x: cx - w / 2, y: y(b))); cap.addLine(to: CGPoint(x: cx + w / 2, y: y(b)))
                        ctx.stroke(cap, with: .color(Ink.primary), style: StrokeStyle(lineWidth: monthly ? 1.5 : 2, lineCap: .butt))
                    }
                case .gain:
                    if let ghost { ctx.fill(ghost, with: .color(ramp.dim)) }
                    if let bar, let v {
                        ctx.fill(bar, with: .color(fill))
                        if let b {
                            let shared = rect(cx, w, min(v, b))
                            ctx.drawLayer { l in l.clip(to: bar); l.fill(Path(CGRect(x: shared.minX, y: shared.minY, width: w, height: base - shared.minY)), with: .color(Fill.widget.opacity(0.55))) }
                        }
                    }
                case .hatch:
                    let step: CGFloat = monthly ? 3 : 4
                    if let ghost { ctx.fill(ghost, with: .color(ramp.faint)); hatch(ctx, ghost.boundingRect, [ghost], ramp.hue.opacity(0.5), step: step) }
                    if let bar { ctx.fill(bar, with: .color(fill)) }
                    if let bar, let ghost { hatch(ctx, ghost.boundingRect, [bar, ghost], Fill.widget.opacity(0.6), step: step) }
                }
                if v == nil, i > days.today {
                    let stub = CGRect(x: cx - w / 2, y: base - 4, width: w, height: 4)
                    ctx.stroke(Path(roundedRect: stub.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2, style: .continuous), with: .color(ramp.faint), lineWidth: 1)
                }
                if !monthly, let v {
                    ctx.draw(tick(String(format: "%.1f", v), lit ? Ink.primary : Ink.tertiary), at: CGPoint(x: cx, y: min(y(v), b.map(y) ?? .infinity) - 2), anchor: .bottom)
                }
                if let label = days.labels[i] {
                    let text = ctx.resolve(tick(label, i == days.today || (lit && !monthly) ? Ink.primary : Ink.tertiary))
                    let half = text.measure(in: size).width / 2
                    ctx.draw(text, at: CGPoint(x: min(max(cx, half), size.width - right - half), y: size.height), anchor: .bottom)
                }
            }
        }
    }
}

struct Card: View {
    let title: String
    let days: Days
    let variant: Variant
    var body: some View {
        Widget {
            WidgetHead(title: "杠杆", ramp: .work, context: title)
            Bars(days: days, variant: variant).frame(height: 96).padding(.top, Space.l)
        }
    }
}

struct Sheet: View {
    let columns: [(String, Days, CGFloat)] = [("日 · 330", .day, 330), ("周 · 过去一周", .pastWeek, 330), ("月 · 330", .month, 330), ("日 · 整宽 600", .day, 600)]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            ForEach(Variant.allCases, id: \.self) { v in
                HStack(alignment: .top, spacing: Space.l) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(v.rawValue).font(.ui(.body, .semibold)).foregroundStyle(Ink.primary)
                        Text(v.note).font(.ui(.footnote)).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: 130, alignment: .leading).padding(.top, Space.widget)
                    ForEach(columns, id: \.0) { c in Card(title: c.0, days: c.1, variant: v).frame(width: c.2) }
                }
            }
        }
        .padding(24)
    }
}

@MainActor func render(_ view: some View, size: NSSize, dark: Bool, to path: String) {
    let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor)))
    w.contentView = host
    w.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    w.orderOut(nil)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
MainActor.assumeIsolated {
    for dark in [true, false] {
        render(Sheet(), size: NSSize(width: 1830, height: 860), dark: dark, to: "\(out)/study-\(dark ? "dark" : "light").png")
    }
}
