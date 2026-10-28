import SwiftUI
import YaaCore

extension DisplayStatus {
    var label: String {
        switch self {
        case .needsInput: String(localized: "Needs input")
        case .stuck: String(localized: "Maybe stuck")
        case .review: String(localized: "To review")
        case .running: String(localized: "Running")
        case .done: String(localized: "Reviewed")
        case .ended: String(localized: "Ended")
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
    var compact = true
    var body: some View {
        Badge(text: status.label, tint: status.tint, compact: compact).contentTransition(.interpolate)
    }
}

/// Count chip used in headers ("2 待验收").
struct CountChip: View {
    let count: Int
    let status: DisplayStatus
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(status.tint).frame(width: 6, height: 6)
            Text("\(count)").font(.figure(11)).contentTransition(.numericText())
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(status.tint.soft(), in: Capsule())
        .help("\(count) \(status.label)")
    }
}

extension View {
    /// A card's surface: a status wash for the states that want the user, else the neutral card.
    func card(_ status: DisplayStatus, hover: Bool = false, radius: CGFloat = Radius.card) -> some View {
        modifier(CardSurface(loud: status.isLoud, tint: status.tint, hover: hover, radius: radius))
    }
}

private struct CardSurface: ViewModifier {
    let loud: Bool
    let tint: Color
    let hover: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if loud {
            content.tinted(shape, tint, strength: hover ? 1.4 : 1)
        } else {
            content.surface(shape, fill: hover ? Fill.cardHover : Fill.card)
        }
    }
}

extension View {
    /// A session's card surface: `card`, plus a flash while it has waited on the user for a while
    /// unclicked or sat unreviewed while the user is at the Mac, and (unless `stale` is false) a blue
    /// tint that comes and goes on a reviewed turn nobody followed up.
    func sessionCard(_ session: SessionState, hover: Bool, radius: CGFloat = 12, stale: Bool = true) -> some View {
        modifier(SessionSurface(session: session, hover: hover, radius: radius, stale: stale))
    }
}

private struct SessionSurface: ViewModifier {
    @Environment(AppModel.self) private var model
    let session: SessionState
    let hover: Bool
    let radius: CGFloat
    let stale: Bool

    func body(content: Content) -> some View {
        let st = session.display, p = model.settings
        let stale = stale && p.staleTintEnabled
        content
            .card(st, hover: hover, radius: radius)
            .background {
                // Only the sessions that can need it tick.
                if (st == .needsInput && p.flashEnabled) || (st == .review && p.reviewFlashEnabled)
                    || (st == .done && stale) {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let flash = st == .needsInput ? Attention.flashes(
                            session, acknowledged: model.acknowledged[session.id], now: ctx.date, after: p.flashAfterSeconds)
                            : st == .review && Attention.reviewFlashes(
                                session, presentSince: model.presentSince, now: ctx.date, after: p.reviewFlashMinutes * 60)
                        let blue = st == .done && stale ? Attention.staleness(
                            session, linger: p.idleVisibleSeconds, now: ctx.date, after: p.staleAfterMinutes * 60) : 0
                        Color.clear
                            .overlay { if flash { Flash(tint: st.tint, radius: radius) } }
                            .overlay { if blue > 0 { Stale(amount: blue, radius: radius) } }
                            .allowsHitTesting(false)
                    }
                }
            }
    }
}

/// Pulsing tint, under the content.
private struct Flash: View {
    let tint: Color
    let radius: CGFloat
    @State private var on = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(tint.opacity(on ? 0.34 : 0.04))
            .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = true } }
    }
}

/// Blue wash, from nothing to clearly blue at `amount` 1.
private struct Stale: View {
    let amount: Double
    let radius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(Color.blue.opacity(0.2 * amount))
    }
}

/// The agent's real logo, bundled as SVG in `Resources/AgentIcons` (from @lobehub/icons), drawn
/// as a monochrome template: secondary ink on cards and rows, white on a `LogoTile`.
struct AgentLogo: View {
    let agent: AgentKind
    var size: CGFloat = 13
    var ink: Color = .secondary

    var body: some View {
        if let img = Self.image(agent) {
            Image(nsImage: img).renderingMode(.template).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(ink)
                .help(agent.displayName)
        } else {
            Image(systemName: agent.symbol).font(.system(size: size * 0.8)).frame(width: size, height: size)
                .foregroundStyle(ink)
        }
    }

    @MainActor private static var cache: [AgentKind: NSImage] = [:]

    @MainActor static func image(_ agent: AgentKind) -> NSImage? {
        if let i = cache[agent] { return i }
        let file: String = switch agent {
        case .claudeCode: "claudecode"
        case .codex: "codex"
        case .cursor: "cursor"
        case .opencode: "opencode"
        case .pi: "pi"
        case .hermes: "hermes"
        case .deepseek: "deepseek"
        case .qwen: "qwen"
        case .droid: "droid"
        case .copilot: "copilot"
        case .gemini: "gemini"
        case .zcode: "zcode"
        case .kiro: "kiro"
        case .kimi: "kimi"
        case .cline: "cline"
        case .omp: "omp"
        case .windsurf: "windsurf"
        }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("AgentIcons/\(file).svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        cache[agent] = img
        return img
    }
}

/// An agent's white logo on a dark tile, beside its name in settings and the setup guide.
struct LogoTile: View {
    let agent: AgentKind
    var size: CGFloat = 32

    var body: some View {
        AgentLogo(agent: agent, size: (size * 0.56).rounded(), ink: .white).frame(width: size, height: size)
            .background(Plate(shape: RoundedRectangle(cornerRadius: Radius.tile(size), style: .continuous), tint: Fill.logo))
    }
}
