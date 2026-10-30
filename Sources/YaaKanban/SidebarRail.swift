import SwiftUI
import YaaCore

/// Side of the screen the floating panel is snapped to.
enum DockEdge { case left, right }

/// Docked to a side, the floating panel folds to a thin rail: the same view and list, each card a
/// small strip of status, agent and clock that keeps the height it has in the full panel, so
/// unfolding only widens it. Width of the folded panel:
enum Rail {
    static let width: CGFloat = 28
    /// Side margin of the folded panel: the gap between cards.
    static let inset: CGFloat = 4
}

private struct RailExtraKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }

extension EnvironmentValues {
    /// Set while the panel is folded: how much wider the card would be unfolded.
    var railExtra: CGFloat? {
        get { self[RailExtraKey.self] }
        set { self[RailExtraKey.self] = newValue }
    }
}

/// Folded header: the logo's mark, the height of the full one. Too narrow for a button: hovering
/// unfolds the rail, and its header has the pin.
struct RailHeader: View {
    var body: some View {
        BrandGlyph(size: 17).frame(maxWidth: .infinity).frame(height: BoardHeaderHeight.value)
    }
}

enum BoardHeaderHeight { static let value: CGFloat = 22 }

/// A card folded into the rail: status, agent and clock stacked on a plain card. Its height is the
/// full card's: known from when the panel was unfolded, and re-measured off a hidden copy laid
/// out at the full width.
struct NarrowSessionCard: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    let expanded: Bool
    let extra: CGFloat
    /// Full card height, if known.
    let height: CGFloat?
    var onHeight: (CGFloat) -> Void
    @State private var width: CGFloat = 0
    @State private var hover = false

    var body: some View {
        let st = session.display
        card(st)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(alignment: .topLeading) {
            if width > 0 {
                SessionCard(session: session, expanded: expanded)
                    .environment(\.railExtra, nil)
                    .frame(width: width + extra)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .onTapGesture { model.jump(session.id) }
        .help(help(st))
        .contextMenu {
            Button(AppModel.isGone(session) ? "Resume in original terminal" : "Jump to terminal") { model.jump(session.id) }
            if st == .review { Button("Mark as reviewed") { model.markRead(session.id) } }
            Button("Copy cwd / session") { model.jumper.copyContext(session) }
            Button("Copy resume command") { model.jumper.copyResume(session) }
            Divider()
            MoveMenu(session: session)
            Divider()
            Button("End (remove from floating panel)") { model.dismiss(session.id) }
        }
    }

    /// The status color only in its glyph and a thin track between, which a light runs down while
    /// the agent works.
    private func card(_ st: DisplayStatus) -> some View {
        VStack(spacing: 4) {
            StatusGlyph(status: st, size: 16)
            AgentLogo(agent: session.agent, size: 10).opacity(st == .done || st == .ended ? 0.5 : 0.85)
            StatusTrack(status: st).frame(maxHeight: .infinity)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Self.shortClock(session, now: ctx.date))
                    .font(.system(size: 8, weight: .medium).monospacedDigit())
                    .foregroundStyle(st == .running ? AnyShapeStyle(st.tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 1)
        .frame(maxWidth: .infinity)
        .frame(height: height ?? 60)
        // Flashes like the full card; no blue wash, color stays an accent here.
        .sessionCard(session, hover: hover, radius: 6, stale: false)
    }

    /// The card's clock in at most three characters: 42s, 7m, 2h, 3d.
    static func shortClock(_ s: SessionState, now: Date) -> String {
        let t = Int(now.timeIntervalSince(s.clockStart))
        if t < 60 { return "\(max(t, 0))s" }
        if t < 3600 { return "\(t / 60)m" }
        if t < 86400 { return "\(t / 3600)h" }
        return "\(t / 86400)d"
    }

    private func help(_ st: DisplayStatus) -> String {
        var lines = ["\(session.title) · \(st.label)"]
        if let p = session.projectName { lines.append(p) }
        if let d = SubagentSlots.detail(session) { lines.append(d) }
        lines.append(AppModel.isGone(session) ? String(localized: "Click to resume \(session.agent.displayName) in its original terminal") : String(localized: "Click to jump to \(session.agent.displayName)"))
        return lines.joined(separator: "\n")
    }
}

/// The folded card's thin track: a light running down it while the agent works, the status color
/// while it wants the user, faint once looked at.
private struct StatusTrack: View {
    let status: DisplayStatus

    var body: some View {
        let shape = Capsule()
        ZStack {
            shape.fill(status == .running ? status.tint.opacity(0.22)
                       : status.isLoud ? status.tint.opacity(0.55) : Color.primary.opacity(0.08))
            if status == .running {
                GeometryReader { g in
                    let run = min(24, g.size.height * 0.45)
                    // Only the system tint, as everywhere else, so it follows the light or dark look
                    // the glass picks; opaque through its middle, fading only at the ends.
                    shape.fill(LinearGradient(stops: [.init(color: status.tint.opacity(0), location: 0),
                                                      .init(color: status.tint, location: 0.4),
                                                      .init(color: status.tint, location: 0.8),
                                                      .init(color: status.tint.opacity(0), location: 1)],
                                              startPoint: .top, endPoint: .bottom))
                        .frame(width: g.size.width, height: run)
                        .keyframeAnimator(initialValue: 0.0, repeating: true) { v, t in
                            v.offset(y: -run + t * (g.size.height + run))
                        } keyframes: { _ in
                            CubicKeyframe(1.0, duration: 1.4)
                            LinearKeyframe(1.0, duration: 0.3)
                        }
                }
                .clipShape(shape)
            }
        }
        .frame(width: 2.5)
        .frame(minHeight: 0)
    }
}
