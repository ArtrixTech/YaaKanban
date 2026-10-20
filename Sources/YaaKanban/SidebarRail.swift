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

/// A card folded into the rail: status, agent, clock, and as much of the title as fits. Its
/// height is the full card's, measured off a hidden copy laid out at the full width.
struct NarrowSessionCard: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    let expanded: Bool
    let grouped: Bool
    let extra: CGFloat
    @State private var width: CGFloat = 0
    @State private var fullHeight: CGFloat?
    @State private var hover = false

    var body: some View {
        let st = session.display
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                StatusGlyph(status: st, size: 18)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { AgentLogo(agent: session.agent, size: 11); Spacer(minLength: 2); clock }
                    HStack(spacing: 0) { Spacer(minLength: 2); clock }
                }
            }
            Text(session.title).font(.system(size: 11, weight: .semibold)).lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: fullHeight, maxHeight: fullHeight ?? .infinity, alignment: .topLeading)
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
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
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
