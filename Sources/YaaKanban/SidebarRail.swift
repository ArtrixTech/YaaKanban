import SwiftUI
import YaaCore

/// Side of the screen the floating panel is snapped to.
enum DockEdge { case left, right }

/// Docked to a side, the floating panel folds to a narrow rail: the same view, list and cards,
/// each card showing less but keeping the height it has in the full panel, so unfolding only
/// widens it. Width of the folded panel:
enum Rail {
    static let width: CGFloat = 120
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
/// now (the tool running, what it needs, its last reply) on one line, and its numbers at the bottom. Its height is the full
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
        FitStack(spacing: 3) {
            HStack(spacing: 4) {
                StatusGlyph(status: st, size: 18)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { AgentLogo(agent: session.agent, size: 11); Spacer(minLength: 2); clock }
                    HStack(spacing: 0) { Spacer(minLength: 2); clock }
                }
            }
            .padding(.bottom, 1)
            Text(session.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            live(st)
            // The full card is taller (agent row, reply, tool), so the rest goes to the project and
            // numbers, right under the status, as many lines as fit.
            projectLabel
            numbers
        }
        // The full card's padding, so both have the same border.
        .padding(10)
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
            HStack(spacing: 3) {
                ToolGlyph(tool: t)
                Text(t.name).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(t.isRunning ? Color.blue : Color.secondary).lineLimit(1)
            }
        } else if let d = SubagentSlots.detail(session) {
            Text(d).font(.system(size: 10)).lineLimit(1).foregroundStyle(st.isLoud ? AnyShapeStyle(st.tint) : AnyShapeStyle(.secondary))
        } else {
            Text(st.label).font(.system(size: 10, weight: .medium)).lineLimit(1).foregroundStyle(st.tint)
        }
    }

    private var project: String? { grouped ? nil : session.projectName }

    /// Empty (and left out by `FitStack`) when the group header names the project.
    @ViewBuilder private var projectLabel: some View {
        if let p = project {
            Text(p).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).lineLimit(1)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    /// Tool calls and tokens, or just the tokens if both do not fit.
    private var numbers: some View {
        ViewThatFits(in: .horizontal) {
            UsageBadge(session: session)
            UsageBadge(session: session, toolCalls: false)
            Color.clear.frame(height: 0)
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

/// A leading-aligned column that shows its rows top down while they fit in the height it is
/// offered and leaves out the rest, so nothing is cut in half and no gap opens between rows.
struct FitStack: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width
        let rows = fitting(subviews, width: width, height: proposal.height ?? .infinity)
        let h = rows.enumerated().map { i, r in r.height + (i == 0 || r.height < 0.5 ? 0 : spacing) }.reduce(0, +)
        return CGSize(width: width ?? rows.map(\.width).max() ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = fitting(subviews, width: bounds.width, height: bounds.height)
        var y = bounds.minY
        for (i, v) in subviews.enumerated() {
            guard i < rows.count else {
                // Left out: parked out of sight with no size.
                v.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), proposal: .zero)
                continue
            }
            if i > 0 && rows[i].height >= 0.5 { y += spacing }
            v.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: rows[i].height))
            y += rows[i].height
        }
    }

    /// Sizes of the leading rows that fit.
    private func fitting(_ subviews: Subviews, width: CGFloat?, height: CGFloat) -> [CGSize] {
        var rows: [CGSize] = []
        var used: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let gap = rows.isEmpty || size.height < 0.5 ? 0 : spacing
            let next = used + gap + size.height
            // The first rows (status, title) always show; the rest only if whole.
            if next > height + 0.5 && rows.count >= 2 { break }
            rows.append(size)
            used = next
        }
        return rows
    }
}
