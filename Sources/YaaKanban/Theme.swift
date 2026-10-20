import SwiftUI
import YaaCore

extension DisplayStatus {
    var label: String {
        switch self {
        case .needsInput: "需要输入"
        case .stuck: "可能卡住"
        case .review: "待验收"
        case .running: "运行中"
        case .done: "已验收"
        case .ended: "已结束"
        }
    }

    var tint: Color {
        switch self {
        case .needsInput: .red
        case .stuck: .orange
        case .review: .green
        case .running: .blue
        case .done, .ended: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .needsInput: "hand.raised.fill"
        case .stuck: "exclamationmark.triangle.fill"
        case .review: "checkmark.seal.fill"
        case .running: "circle.dotted"
        case .done: "checkmark.circle"
        case .ended: "stop.circle"
        }
    }

    /// States that want the user and get a tinted card.
    var isLoud: Bool { self == .needsInput || self == .stuck || self == .review }
}

/// Animated status mark: a spinning ring while running, a breathing halo while waiting on the user.
struct StatusGlyph: View {
    let status: DisplayStatus
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            if status.isLoud {
                Circle().fill(status.tint.opacity(0.25))
                    .keyframeAnimator(initialValue: 0.0, repeating: true) { v, t in
                        v.scaleEffect(1 + t * 0.45).opacity(1 - t)
                    } keyframes: { _ in
                        LinearKeyframe(1.0, duration: 1.6)
                    }
            }
            Circle().fill(status.tint.opacity(status.isLoud ? 0.18 : 0.10))
            if status == .running {
                Circle().trim(from: 0, to: 0.7)
                    .stroke(status.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .padding(size * 0.22)
                    .keyframeAnimator(initialValue: 0.0, repeating: true) { v, deg in
                        v.rotationEffect(.degrees(deg))
                    } keyframes: { _ in
                        LinearKeyframe(360.0, duration: 1.1)
                    }
            } else {
                Image(systemName: status.symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(status.tint)
            }
        }
        .frame(width: size, height: size)
        .animation(.smooth, value: status)
    }
}

/// Small capsule with the status name.
struct StatusPill: View {
    let status: DisplayStatus
    var body: some View {
        Text(status.label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(status.tint)
            .background(status.tint.opacity(0.14), in: Capsule())
            .contentTransition(.interpolate)
    }
}

/// Count chip used in headers ("2 待验收").
struct CountChip: View {
    let count: Int
    let status: DisplayStatus
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(status.tint).frame(width: 6, height: 6)
            Text("\(count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(status.tint.opacity(0.13), in: Capsule())
        .help("\(count) \(status.label)")
    }
}

/// Compact capsule button with hover and press feedback.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = .primary
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, tint: tint, prominent: prominent)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let tint: Color
        let prominent: Bool
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
                .background {
                    Capsule().fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(hover ? 0.16 : 0.08)))
                }
                .brightness(prominent && hover ? 0.06 : 0)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// Round icon button that brightens on hover.
struct IconButton: View {
    let symbol: String
    let help: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.primary.opacity(hover ? 0.12 : 0)))
                .foregroundStyle(hover ? .primary : .secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(help)
    }
}

extension View {
    /// Rounded card surface; loud statuses get a tinted fill and edge.
    func card(_ status: DisplayStatus, hover: Bool = false, radius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(status.isLoud ? status.tint.opacity(hover ? 0.14 : 0.09)
                                                  : Color.primary.opacity(hover ? 0.075 : 0.045)))
            .overlay(shape.strokeBorder(status.isLoud ? status.tint.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1))
    }
}

extension View {
    /// A session's card surface: `card`, plus a flash while it has waited on the user for a while
    /// unclicked, and a blue tint that comes and goes on a reviewed turn nobody followed up.
    func sessionCard(_ session: SessionState, hover: Bool) -> some View {
        modifier(SessionSurface(session: session, hover: hover))
    }
}

private struct SessionSurface: ViewModifier {
    @Environment(AppModel.self) private var model
    let session: SessionState
    let hover: Bool

    func body(content: Content) -> some View {
        let st = session.display
        content
            .card(st, hover: hover)
            .background {
                // Only the sessions that can need it tick.
                if st == .needsInput || st == .done {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let flash = Attention.flashes(session, acknowledged: model.acknowledged[session.id], now: ctx.date)
                        let blue = Attention.staleness(session, linger: model.settings.idleVisibleSeconds, now: ctx.date)
                        Color.clear
                            .overlay { if flash { Flash(tint: st.tint) } }
                            .overlay { if blue > 0 { Stale(amount: blue) } }
                            .allowsHitTesting(false)
                    }
                }
            }
    }
}

/// Pulsing tint and edge, under the content.
private struct Flash: View {
    let tint: Color
    @State private var on = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        shape.fill(tint.opacity(on ? 0.28 : 0.04))
            .overlay(shape.strokeBorder(tint.opacity(on ? 0.9 : 0.3), lineWidth: 1.5))
            .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = true } }
    }
}

/// Blue wash, from nothing to clearly blue at `amount` 1.
private struct Stale: View {
    let amount: Double
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        shape.fill(Color.blue.opacity(0.16 * amount))
            .overlay(shape.strokeBorder(Color.blue.opacity(0.45 * amount), lineWidth: 1))
    }
}

/// The agent's real logo, bundled as SVG in `Resources/AgentIcons` (from @lobehub/icons).
/// Monochrome logos are templates and follow the text color.
struct AgentLogo: View {
    let agent: AgentKind
    var size: CGFloat = 13

    var body: some View {
        if let img = Self.image(agent) {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(.primary.opacity(0.85))
                .help(agent.displayName)
        } else {
            Image(systemName: agent.symbol).font(.system(size: size * 0.8)).frame(width: size, height: size)
        }
    }

    @MainActor private static var cache: [AgentKind: NSImage] = [:]

    @MainActor static func image(_ agent: AgentKind) -> NSImage? {
        if let i = cache[agent] { return i }
        let (file, colored): (String, Bool) = switch agent {
        case .claudeCode: ("claudecode-color", true)
        case .codex: ("codex-color", true)
        case .cursor: ("cursor", false)
        case .opencode: ("opencode", false)
        case .pi: ("pi", false)
        }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("AgentIcons/\(file).svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = !colored
        cache[agent] = img
        return img
    }
}
