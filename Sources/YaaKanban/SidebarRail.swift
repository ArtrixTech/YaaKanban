import SwiftUI
import YaaCore

/// Side of the screen the floating panel is snapped to.
enum DockEdge { case left, right }

/// Docked to a side, the floating panel folds to a narrow rail: the same view, list and cards,
/// each card showing less but keeping the height it has in the full panel, so unfolding only
/// widens it. Width of the folded panel:
enum Rail {
    static let width: CGFloat = 120
    /// How much wider every row is in the full panel.
    static let extra: CGFloat = 340 - width  // FloatingPanelController.width
}

private struct RailExtraKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }

extension EnvironmentValues {
    /// Set while the panel is folded: how much wider the card would be unfolded.
    var railExtra: CGFloat? {
        get { self[RailExtraKey.self] }
        set { self[RailExtraKey.self] = newValue }
    }
}

/// Folded header: the mark and the unfold button, the height of the full one.
struct RailHeader: View {
    let edge: DockEdge
    var onUnfold: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            BrandMark(size: 20)
            Spacer(minLength: 0)
            IconButton(symbol: edge == .right ? "chevron.left.2" : "chevron.right.2", help: "固定展开", action: onUnfold)
        }
        .frame(height: BoardHeaderHeight.value)
    }
}

enum BoardHeaderHeight { static let value: CGFloat = 22 }

/// A card folded into the rail: status, agent, clock, the title, and below it what is going on
/// now (the tool running, what it needs, its last reply), as much as fits. Its height is the full
/// card's: known from when the panel was unfolded, and re-measured off a hidden copy laid out at
/// the full width.
struct NarrowSessionCard: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    let expanded: Bool
    let grouped: Bool
    let extra: CGFloat
    /// Full card height, if known.
    let height: CGFloat?
    var onHeight: (CGFloat) -> Void
    @State private var width: CGFloat = 0
    @State private var hover = false

    var body: some View {
        let st = session.display
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                StatusGlyph(status: st, size: 18)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { AgentLogo(agent: session.agent, size: 11); Spacer(minLength: 2); clock }
                    HStack(spacing: 0) { Spacer(minLength: 2); clock }
                }
            }
            .padding(.bottom, 1)
            Text(session.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                .layoutPriority(1)
            live(st)
        }
        .padding(8)
        // Until measured, at most this tall, so the first frame is never taller than the card.
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height ?? 60, alignment: .topLeading)
        .clipped()
        .card(st, hover: hover)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(alignment: .topLeading) {
            if width > 0 {
                SessionCard(session: session, expanded: expanded, grouped: grouped)
                    .environment(\.railExtra, nil)
                    .frame(width: width + extra)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .onTapGesture { model.jump(session.id) }
        .help(help(st))
        .contextMenu {
            Button("跳转到终端") { model.jump(session.id) }
            if st == .review { Button("标记已验收") { model.markRead(session.id) } }
            Button("复制 cwd / session") { model.jumper.copyContext(session) }
            Divider()
            Button("结束（移出悬浮窗）") { model.dismiss(session.id) }
        }
    }

    /// What it is doing now: the tool in flight, what it needs, why it may be stuck, its reply.
    @ViewBuilder private func live(_ st: DisplayStatus) -> some View {
        if st == .running, let t = session.latestTool {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: "gearshape.2.fill").font(.system(size: 8.5)).foregroundStyle(st.tint)
                Text("\(t.name) \(t.summary)").font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(.secondary)
        } else if let d = SubagentSlots.detail(session) {
            Text(d).font(.system(size: 10)).foregroundStyle(st.isLoud ? AnyShapeStyle(st.tint) : AnyShapeStyle(.secondary))
        } else {
            Text(st.label).font(.system(size: 10, weight: .medium)).foregroundStyle(st.tint)
        }
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(session.clock(now: ctx.date)).font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
    }

    private func help(_ st: DisplayStatus) -> String {
        var lines = ["\(session.title) · \(st.label)"]
        if let p = session.projectName { lines.append(p) }
        if let d = SubagentSlots.detail(session) { lines.append(d) }
        lines.append("点击跳转到 \(session.agent.displayName)")
        return lines.joined(separator: "\n")
    }
}
