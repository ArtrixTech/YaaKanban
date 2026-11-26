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
        case .needsInput: Ramp.wait.hue
        case .stuck: .orange
        case .review: .green
        case .running: .blue
        case .done, .ended: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .needsInput: "questionmark.bubble.fill"
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
            Circle().fill(status.tint.opacity(status.isLoud ? 0.18 : 0.10))
            if status == .running {
                LoopLayer(kind: .spin(lineWidth: 2, inset: size * 0.22), tint: status.tint)
            } else {
                Image(systemName: status.symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(status.tint)
            }
        }
        .frame(width: size, height: size)
        // Behind, and free to swell past the glyph's frame.
        .background { if status.isLoud { LoopLayer(kind: .halo, tint: status.tint) } }
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
    /// Where a row would otherwise not fit: `tight` pads less, `bare` drops the capsule.
    enum Style { case regular, tight, bare }
    var style: Style = .regular
    var body: some View {
        HStack(spacing: style == .regular ? 3 : Space.xxs) {
            Circle().fill(status.tint).frame(width: 6, height: 6)
            Text("\(count)").font(.figure(11)).contentTransition(.numericText())
        }
        .padding(.horizontal, style == .regular ? 7 : style == .tight ? Space.xs : Space.xxs).padding(.vertical, 3)
        .background(style == .bare ? Color.clear : status.tint.soft(), in: Capsule())
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

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    /// Once a second, on whole seconds shared by every view. `.periodic(from: .now, by: 1)` starts
    /// each view's ticks when that view appears, so N clocks tick at N moments a second and each
    /// tick lays out the whole window again; on a shared phase they update in one pass.
    static var everySecond: PeriodicTimelineSchedule {
        .periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)
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
                    TimelineView(.everySecond) { ctx in
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
    var body: some View { LoopLayer(kind: .flash(radius: radius), tint: tint) }
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

extension CustomAgentColor {
    var swiftUIColor: Color {
        switch self {
        case .auto, .slate: return Fill.logo
        case .blue: return Color(red: 0.16, green: 0.48, blue: 0.96)
        case .indigo: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .purple: return Color(red: 0.62, green: 0.31, blue: 0.87)
        case .pink: return Color(red: 0.89, green: 0.25, blue: 0.56)
        case .red: return Color(red: 0.87, green: 0.24, blue: 0.24)
        case .orange: return Color(red: 0.92, green: 0.45, blue: 0.14)
        case .amber: return Color(red: 0.85, green: 0.60, blue: 0.08)
        case .green: return Color(red: 0.13, green: 0.66, blue: 0.38)
        case .teal: return Color(red: 0.09, green: 0.63, blue: 0.62)
        case .cyan: return Color(red: 0.09, green: 0.59, blue: 0.78)
        }
    }

    func resolvedColor(for id: String) -> Color {
        resolved(for: id).swiftUIColor
    }
}

/// Loads and caches user-imported SVG/PNG custom agent icons from `Paths.customAgentIcons`.
@MainActor
enum CustomIconCache {
    private static var cache: [String: NSImage] = [:]

    static func image(filename: String?, iconsDir: URL = Paths().customAgentIcons) -> NSImage? {
        guard let filename, !filename.isEmpty, !filename.contains("/"), !filename.contains("\\"), !filename.contains("..") else { return nil }
        if let hit = cache[filename] { return hit }
        let url = iconsDir.appendingPathComponent(filename)
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache[filename] = img
        return img
    }

    static func remove(filename: String?) {
        guard let filename else { return }
        cache.removeValue(forKey: filename)
    }

    static func clear() { cache.removeAll() }
}

/// The agent's real logo, bundled as SVG in `Resources/AgentIcons` (from @lobehub/icons), drawn
/// as a monochrome template: secondary ink on cards and rows, white on a `LogoTile`.
/// For `.custom` agents, renders the user's imported image, SF Symbol, or monogram badge.
struct AgentLogo: View {
    let agent: AgentKind
    var customId: String? = nil
    var custom: CustomAgent? = nil
    var size: CGFloat = 13
    var ink: Color = .secondary
    /// True when rendered inside a `LogoTile` (already sits on a colored/dark tile).
    var onTile = false

    private var resolvedLabel: String {
        if agent == .custom {
            return custom?.name ?? CustomAgent.defaultDisplayName(for: customId)
        }
        return agent.displayName
    }

    var body: some View {
        if agent == .custom {
            customBody
                .help(resolvedLabel)
        } else if let img = Self.image(agent) {
            Image(nsImage: img).renderingMode(.template).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(ink)
                .help(agent.displayName)
        } else {
            Image(systemName: agent.symbol).font(.system(size: size * 0.8)).frame(width: size, height: size)
                .foregroundStyle(ink)
        }
    }

    @ViewBuilder private var customBody: some View {
        let icon = custom?.icon ?? CustomAgentIcon()
        let id = custom?.id ?? customId ?? "custom"
        let tint = icon.color.resolvedColor(for: id)
        let monogram = custom?.monogram ?? CustomAgent.monogram(from: CustomAgent.defaultDisplayName(for: customId))

        switch icon.kind {
        case .image:
            if let img = CustomIconCache.image(filename: icon.value) {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.22), style: .continuous))
            } else {
                monogramBadge(monogram, tint: tint)
            }
        case .symbol:
            let sym = (icon.value?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "puzzlepiece.extension.fill"
            Image(systemName: sym).font(.system(size: size * 0.82, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(onTile ? ink : (icon.color == .slate ? ink : tint))
        case .monogram:
            if onTile {
                Text(verbatim: monogram)
                    .font(.system(size: monogram.count > 1 ? size * 0.68 : size * 0.78, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .frame(width: size, height: size)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                monogramBadge(monogram, tint: tint)
            }
        }
    }

    private func monogramBadge(_ text: String, tint: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: text.count > 1 ? max(6.5, size * 0.56) : max(7.5, size * 0.68), weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size + 2, height: size + 2)
            .background(RoundedRectangle(cornerRadius: max(3, (size + 2) * 0.28), style: .continuous).fill(tint))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    @MainActor private static var cache: [AgentKind: NSImage] = [:]

    @MainActor static func image(_ agent: AgentKind) -> NSImage? {
        if let i = cache[agent] { return i }
        let file: String? = switch agent {
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
        case .custom: nil
        }
        guard let file,
              let url = Bundle.main.resourceURL?.appendingPathComponent("AgentIcons/\(file).svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        cache[agent] = img
        return img
    }
}

/// An agent's white logo on a dark tile, beside its name in settings and the setup guide.
struct LogoTile: View {
    let agent: AgentKind
    var customId: String? = nil
    var custom: CustomAgent? = nil
    var size: CGFloat = 32

    private var tileTint: Color {
        guard agent == .custom else { return Fill.logo }
        let icon = custom?.icon ?? CustomAgentIcon()
        if icon.kind == .image, CustomIconCache.image(filename: icon.value) != nil {
            return Fill.control
        }
        return icon.color.resolvedColor(for: custom?.id ?? customId ?? "custom")
    }

    var body: some View {
        let isCustomImage = agent == .custom && custom?.icon.kind == .image && CustomIconCache.image(filename: custom?.icon.value) != nil
        let glyphSize = isCustomImage ? (size * 0.72).rounded() : (size * 0.56).rounded()
        AgentLogo(agent: agent, customId: customId, custom: custom, size: glyphSize, ink: .white, onTile: true)
            .frame(width: size, height: size)
            .background {
                let shape = RoundedRectangle(cornerRadius: Radius.tile(size), style: .continuous)
                if isCustomImage {
                    shape.fill(Fill.control)
                } else {
                    Plate(shape: shape, tint: tileTint)
                }
            }
    }
}
