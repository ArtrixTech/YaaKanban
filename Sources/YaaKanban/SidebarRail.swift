import SwiftUI
import YaaCore

/// Side of the screen the floating panel is snapped to.
enum DockEdge { case left, right }

/// Docked to a side, the floating panel folds to a narrow rail: the same view, list and cards,
/// each card showing less but keeping the height it has in the full panel, so unfolding only
/// widens it. Width of the folded panel:
enum Rail {
    static let width: CGFloat = 120
    /// Side margin of the folded panel: the gap between cards.
    static let inset: CGFloat = 8
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
/// now (the tool running, its sub-agents, what it needs, its last reply), and its numbers at the bottom. Its height is the full
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
        FitStack(spacing: 2) {
            HStack(spacing: 4) {
                StatusGlyph(status: st, size: 18)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { AgentLogo(agent: session.agent, size: 11); Spacer(minLength: 2); clock }
                    HStack(spacing: 0) { Spacer(minLength: 2); clock }
                }
            }
            Text(session.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            live(st)
            NarrowSubagents(session: session)
            // The full card is taller (agent row, reply, tool): its reply takes the room left, in
            // as many lines as fit.
            reply(st)
            projectLabel
            numbers
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        // Until measured, at most this tall, so the first frame is never taller than the card.
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height ?? 60, alignment: .topLeading)
        .clipped()
        .sessionCard(session, hover: hover)
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
        } else if words(st) == nil {
            Text(st.label).font(.system(size: 10, weight: .medium)).lineLimit(1).foregroundStyle(st.tint)
        } else {
            Color.clear.frame(height: 0)  // the reply below says it
        }
    }

    /// Its latest words, or what it needs: at least one line, more as room allows.
    @ViewBuilder private func reply(_ st: DisplayStatus) -> some View {
        if let w = words(st) {
            Text(w).font(.system(size: 10))
                .foregroundStyle(st.isLoud ? AnyShapeStyle(st.tint) : AnyShapeStyle(.secondary))
                .layoutValue(key: FitStackFill.self, value: true)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private func words(_ st: DisplayStatus) -> String? {
        switch st {
        case .needsInput: session.needsInputMessage ?? session.lastReply
        case .stuck: session.stuckReason ?? session.lastReply
        default: session.lastReply
        }
    }

    private var project: String? { grouped ? nil : session.projectName }

    /// Empty (and left out by `FitStack`) when the group header names the project.
    @ViewBuilder private var projectLabel: some View {
        if let p = project {
            Text(p).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.tertiary).lineLimit(1)
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

/// Sub-agents in a folded card: status and name, one line each. Rows, gaps and padding match the
/// full card's `SubagentSlots`, so the block is as tall as the one the card's height comes from.
struct NarrowSubagents: View {
    @Environment(AppModel.self) private var model
    let session: SessionState

    var body: some View {
        let rows = model.subagents(of: session.id).map { (id: $0.id, status: $0.display, name: $0.title) }
            + session.subagents.map { (id: $0.id, status: DisplayStatus.running, name: $0.type ?? "子 agent") }
        if rows.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.id) { r in
                    HStack(spacing: 4) {
                        StatusGlyph(status: r.status, size: 12)
                        Text(r.name).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                    }
                    .frame(height: 16)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// Marks the one row of a `FitStack` that grows into the height left over.
struct FitStackFill: LayoutValueKey { static let defaultValue = false }

/// A leading-aligned column that shows its rows top down while they fit in the height it is
/// offered and leaves out the rest, so nothing is cut in half. The fill row (at least one line)
/// then grows by whole lines into what is left, and the last few points are shared out between
/// the rows, so no gap opens at the bottom. Empty rows (zero height) take no spacing.
struct FitStack: Layout {
    var spacing: CGFloat = 0
    /// Most extra spacing a gap takes when the rows do not fill the height.
    var maxStretch: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = fitting(subviews, width: proposal.width, height: proposal.height ?? .infinity)
        let used = total(rows)
        let h = proposal.height.map { $0.isFinite ? max($0, used) : used } ?? used
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = fitting(subviews, width: bounds.width, height: bounds.height)
        let gaps = rows.dropFirst().filter { $0.height >= 0.5 }.count
        let stretch = gaps == 0 ? 0 : min(maxStretch, max(0, bounds.height - total(rows)) / CGFloat(gaps))
        var y = bounds.minY
        for (i, v) in subviews.enumerated() {
            guard i < rows.count else {
                // Left out: parked out of sight with no size.
                v.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), proposal: .zero)
                continue
            }
            if i > 0 && rows[i].height >= 0.5 { y += spacing + stretch }
            v.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: rows[i].height))
            y += rows[i].height
        }
    }

    private func total(_ rows: [CGSize]) -> CGFloat {
        rows.enumerated().map { i, r in r.height + (i == 0 || r.height < 0.5 ? 0 : spacing) }.reduce(0, +)
    }

    /// Sizes of the leading rows that fit, the fill row grown into what is left.
    private func fitting(_ subviews: Subviews, width: CGFloat?, height: CGFloat) -> [CGSize] {
        var rows: [CGSize] = []
        var used: CGFloat = 0
        var fill: Int?
        for v in subviews {
            let isFill = v[FitStackFill.self]
            // The fill row starts at one line.
            let size = v.sizeThatFits(ProposedViewSize(width: width, height: isFill ? 0 : nil))
            let gap = rows.isEmpty || size.height < 0.5 ? 0 : spacing
            let next = used + gap + size.height
            // The first rows (status, title) always show; the rest only if whole.
            if next > height + 0.5 && rows.count >= 2 { break }
            if isFill { fill = rows.count }
            rows.append(size)
            used = next
        }
        if let f = fill, height.isFinite {
            let room = rows[f].height + max(0, height - used)
            let grown = subviews[f].sizeThatFits(ProposedViewSize(width: width, height: room))
            if grown.height <= room + 0.5 { rows[f] = grown }
        }
        return rows
    }
}
