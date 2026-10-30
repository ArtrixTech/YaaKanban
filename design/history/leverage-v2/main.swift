import AppKit
import SwiftUI

// Leverage bars: ways to show the period before behind each bar at the same width and centre.
// Build: swiftc -o /tmp/lev-study Sources/YaaKanban/DesignSystem.swift design/history/leverage-v2/main.swift
// Run:   /tmp/lev-study <out-dir>

let out = CommandLine.arguments.dropFirst().first ?? "/tmp/lev-study"

enum Variant: String, CaseIterable {
    case cap = "B 原版"
    case deep = "B′ 深 40%"
    case deeper = "B′ 深 55%"
    case gray = "B′ 灰"
    case final = "B′ 深 55% · 柱外 mid"

    var note: String {
        switch self {
        case .cap: "上一版：整宽白线"
        case .deep: "柱宽的 60%，圆头；柱色叠 40% 黑"
        case .deeper: "同上，叠 55% 黑"
        case .gray: "同上，叠 60% 深灰（更灰）"
        case .final: "柱内叠 55% 黑；落在淡柱上（柱外）用 mid"
        }
    }
    /// What darkens the hue for the cap.
    var shade: Color {
        switch self {
        case .cap: .clear
        case .deep: .black.opacity(0.4)
        case .deeper: .black.opacity(0.55)
        case .gray: Color(white: 0.28).opacity(0.6)
        case .final: .black.opacity(0.55)
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
            let w = min(pitch * (monthly ? 0.62 : 0.5), 26)
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
                let bar = v.map { shape(rect(cx, w, $0)) }, ghost = b.map { shape(rect(cx, w, $0)) }
                if let ghost { ctx.fill(ghost, with: .color(ramp.dim)) }
                if let bar { ctx.fill(bar, with: .color(fill)) }
                if let b {
                    if variant == .cap {
                        var cap = Path(); cap.move(to: CGPoint(x: cx - w / 2, y: y(b))); cap.addLine(to: CGPoint(x: cx + w / 2, y: y(b)))
                        ctx.stroke(cap, with: .color(Ink.primary), style: StrokeStyle(lineWidth: monthly ? 1.5 : 2, lineCap: .butt))
                    } else {
                        let t: CGFloat = monthly ? 2 : 3, half = max(w * 0.3 - t / 2, 0)
                        var cap = Path(); cap.move(to: CGPoint(x: cx - half, y: y(b))); cap.addLine(to: CGPoint(x: cx + half, y: y(b)))
                        let style = StrokeStyle(lineWidth: t, lineCap: .round)
                        if variant == .final, v.map({ b > $0 }) ?? true {
                            ctx.stroke(cap, with: .color(ramp.mid), style: style)
                        } else {
                            ctx.stroke(cap, with: .color(ramp.hue), style: style)
                            ctx.stroke(cap, with: .color(variant.shade), style: style)
                        }
                    }
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
