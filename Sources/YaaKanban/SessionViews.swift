import SwiftUI
import YaaCore

extension AgentKind {
    var symbol: String {
        switch self {
        case .claudeCode: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow"
        case .opencode: "curlybraces"
        case .pi: "p.circle"
        case .hermes: "h.circle"
        case .deepseek: "fish"
        case .qwen: "q.circle"
        case .droid: "d.circle"
        case .copilot: "airplane"
        case .gemini: "sparkle"
        case .zcode: "z.circle"
        case .kiro: "k.circle"
        case .kimi: "moon"
        case .cline: "c.circle"
        case .omp: "o.circle"
        case .windsurf: "wind"
        }
    }
}

func relative(_ d: Date, now: Date = Date()) -> String {
    let s = Int(now.timeIntervalSince(d))
    if s < 60 { return String(localized: "\(max(s, 0))s") }
    if s < 3600 { return String(localized: "\(s / 60)m") }
    if s < 86400 { return String(localized: "\(s / 3600)h \(s % 3600 / 60)m") }
    return String(localized: "\(s / 86400)d")
}

extension SessionState {
    /// The prompt of the turn in progress or just finished.
    var currentPrompt: String? {
        if let p = currentTurn?.prompt, !p.isEmpty { return p }
        return peek?.lastPrompt
    }

    /// Running: how long the turn has run. Otherwise: how long ago it last changed.
    func clock(now: Date) -> String {
        status == .running ? relative(clockStart, now: now) : String(localized: "\(relative(lastEventAt, now: now)) ago")
    }

    /// Start of the running turn, else the last change.
    var clockStart: Date {
        guard status == .running else { return lastEventAt }
        return currentTurn.flatMap { $0.endedAt == nil ? $0.startedAt : nil } ?? lastEventAt
    }
}

/// Allow / Deny, only while the hook is waiting for the app.
struct PermissionButtons: View {
    @Environment(AppModel.self) private var model
    let session: SessionState

    var body: some View {
        if let p = session.pendingPermission, p.awaitingDecision, model.canDecide(session.id) {
            VStack(alignment: .leading, spacing: 6) {
                if let detail = p.detail {
                    ScrollView {
                        Text(detail).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(Fill.control, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                }
                HStack(spacing: 6) {
                    Button { model.decide(session.id, .allow, requestId: p.id) } label: { Label("Allow once", systemImage: "checkmark") }
                        .buttonStyle(.action(.primary, tint: .green, size: .small))
                    Button { model.decide(session.id, .deny, requestId: p.id) } label: { Label("Deny", systemImage: "xmark") }
                        .buttonStyle(.action(.secondary, tint: .red, size: .small))
                    Spacer()
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// One session in the floating panel and the menu popover.
struct SessionCard: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    var expanded = false
    var onExpand: () -> Void = {}
    @State private var hover = false

    var body: some View {
        let st = session.display
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                // 1: status, title, clock, expand. The glyph sits in the title row, so the rows
                // under it use the card's full width.
                HStack(spacing: 7) {
                    StatusGlyph(status: st, size: 20)
                    Text(session.title).font(.ui(.body, .semibold)).lineLimit(1)
                    if model.isPinned(session.id) {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Color(red: 1, green: 0.75, blue: 0)).help("Pinned")
                    }
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(session.clock(now: ctx.date))
                            .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ExpandButton(expanded: expanded, action: onExpand)
                    CardIconButton(symbol: "xmark", help: String(localized: "End: remove from the floating panel (kept in History; it comes back when it needs you)")) {
                        model.dismiss(session.id)
                    }
                }
                // 2: agent, project, status, stats.
                HStack(spacing: 5) {
                    AgentLogo(agent: session.agent, size: 12)
                    if model.unhookedAgents.contains(session.agent) {
                        Image(systemName: "powerplug").font(.system(size: 9)).foregroundStyle(.secondary)
                            .help("\(session.agent.displayName) integration isn't installed: the status is approximate, with no approvals or done alerts. Install it in Settings.")
                    } else if model.integrationIssues[session.agent] != nil {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                            .help("Some \(session.agent.displayName) hooks aren't approved, so the status may be incomplete. See Settings for the steps.")
                    }
                    if let p = session.projectName {
                        Text(p).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    StatusPill(status: st)
                    Spacer(minLength: 0)
                    UsageBadge(session: session)
                }
                // 3: what the agent said, or what it needs.
                replyLine(st)
                // 4: the tool call in progress.
                if st == .running, let t = session.latestTool { ToolLine(tool: t) }
            }
            SubagentSlots(session: session)
            PermissionButtons(session: session)
            if expanded { expandedBody(st) }
        }
        .padding(10)
        .sessionCard(session, hover: hover)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .onTapGesture { model.jump(session.id) }
        .help(AppModel.isGone(session) ? "Click to resume \(session.agent.displayName) in its original terminal" : "Click to jump to \(session.agent.displayName)")
        .contextMenu {
            Button(AppModel.isGone(session) ? "Resume in original terminal" : "Jump to terminal") { model.jump(session.id) }
            Button(expanded ? "Hide details" : "Show details", action: onExpand)
            if st == .review { Button("Mark as reviewed") { model.markRead(session.id) } }
            Button("Copy cwd / session") { model.jumper.copyContext(session) }
            Button("Copy resume command") { model.jumper.copyResume(session) }
            Divider()
            MoveMenu(session: session)
            Divider()
            Button("End (remove from floating panel)") { model.dismiss(session.id) }
            Button("Delete from list", role: .destructive) { model.remove(session.id) }
        }
    }

    /// The agent's latest words this turn; for blocked sessions, what it is waiting for.
    @ViewBuilder private func replyLine(_ st: DisplayStatus) -> some View {
        switch st {
        case .needsInput, .stuck:
            Text(session.needsInputMessage ?? session.stuckReason ?? String(localized: "Needs your attention"))
                .font(.system(size: 11.5)).foregroundStyle(st.tint).lineLimit(expanded ? 6 : 2)
        default:
            if let r = session.lastReply {
                Text(r).font(.system(size: 11.5)).foregroundStyle(.primary.opacity(0.8)).lineLimit(expanded ? 12 : 2)
            } else if st == .running {
                Text("Thinking…").font(.system(size: 11.5)).foregroundStyle(.tertiary)
            } else if !session.hooked {
                Text("This session started before the hooks were installed; only a rough status is available").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder private func expandedBody(_ st: DisplayStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = session.currentPrompt {
                Label { Text(p).lineLimit(6) } icon: { Image(systemName: "person.fill") }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let r = session.peek?.recap {
                Label { Text(r) } icon: { Image(systemName: "text.quote") }
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(6)
            }
            let recent = session.tools.suffix(6).reversed()
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(recent)) { ToolLine(tool: $0) }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if let u = session.usage { UsageGrid(usage: u) }
            HStack(spacing: 4) {
                Text(session.agent.displayName)
                if !session.subagents.isEmpty { Text("· subagents: \(session.subagents.count)") }
                if session.terminal?.isWave == true { Text(verbatim: "· Wave") }
                if !session.hooked { Text("· no hooks").foregroundStyle(.orange) }
            }
            .font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Sub-agents under their parent's card, one line each: sessions of their own (pi) and
/// in-process ones reported by hooks (Claude Code).
struct SubagentSlots: View {
    @Environment(AppModel.self) private var model
    let session: SessionState

    var body: some View {
        let children = model.subagents(of: session.id)
        let inline = session.subagents
        if !children.isEmpty || !inline.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(children) { c in
                    SubagentRow(status: c.display, title: c.title, detail: Self.detail(c), since: c.clockStart)
                    PermissionButtons(session: c)
                }
                ForEach(inline, id: \.id) { a in
                    // Hook-reported sub-agents share the parent's tool stream, tagged with their id.
                    let tool = session.tools.last { $0.subagentId == a.id }
                    SubagentRow(status: .running, title: a.type ?? String(localized: "subagent"),
                                detail: tool.map { "\($0.name) \($0.summary)" }, since: a.startedAt)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// What it is doing now, else what it last said or needs.
    static func detail(_ s: SessionState) -> String? {
        if let m = s.needsInputMessage, s.status == .needsInput { return m }
        if let r = s.stuckReason, s.status == .stuck { return r }
        if s.status == .running, let t = s.latestTool { return "\(t.name) \(t.summary)" }
        return s.lastReply.flatMap(SessionState.firstLine)
    }
}

/// One sub-agent: status, name, what it is doing, how long.
struct SubagentRow: View {
    let status: DisplayStatus
    let title: String
    let detail: String?
    let since: Date

    var body: some View {
        HStack(spacing: 5) {
            StatusGlyph(status: status, size: 13)
            // The name gets at most about half the row; what it is doing takes the rest.
            Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(relative(since, now: ctx.date))
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .fixedSize()
        }
        .frame(height: 16)
    }
}

struct ToolLine: View {
    let tool: ToolCall
    var body: some View {
        HStack(spacing: 5) {
            ToolGlyph(tool: tool)
            Text(tool.name).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tool.isRunning ? Color.blue : Color.primary.opacity(0.8))
            Text(tool.summary).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }
}

/// A tool call's state: spinning while it runs, then done or failed.
struct ToolGlyph: View {
    let tool: ToolCall
    var body: some View {
        Group {
            if tool.isRunning {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            } else {
                Image(systemName: tool.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(tool.isError ? Color.red : Color.secondary.opacity(0.6))
            }
        }
        .font(.system(size: 10)).frame(width: 12, height: 12)
    }
}

struct CodeBlock: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(text.isEmpty ? String(localized: "(cleared)") : text)
                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// Pin, rename, and up / down for a card, within its group on the board.
struct MoveMenu: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    var body: some View {
        let id = session.id, pinned = model.isPinned(id)
        let lane = model.lane(of: id), at = lane.firstIndex(of: id) ?? 0
        Button(pinned ? "Unpin" : "Pin to top") { withAnimation(.snappy) { model.togglePin(id) } }
        if at > 0 {
            Button("Move up") { withAnimation(.snappy) { model.reorder(id, to: at - 1, in: lane) } }
        }
        if at + 1 < lane.count {
            Button("Move down") { withAnimation(.snappy) { model.reorder(id, to: at + 1, in: lane) } }
        }
        Button("Rename…") { model.rename(id) }
    }
}

/// The board: one list of full-width cards, most urgent first. A card is dragged by itself: it
/// follows the pointer, lifted, and the cards it passes make room. It moves within its group (the
/// pinned cards, or those of its status) and resists past the group's ends.
struct BoardList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railExtra) private var railExtra
    var expanded: String?
    var onExpand: (SessionState) -> Void = { _ in }
    /// Each card's height in the full panel, which it keeps when the panel folds. Kept here, across
    /// folding, so a folded card has its height from the first frame.
    @State private var heights: [String: CGFloat] = [:]
    /// Each card's laid-out frame in the list, where a drag measures what it passes.
    @State private var frames: [String: CGRect] = [:]
    @State private var drag: CardDrag?
    @State private var cursorPushed = false

    private static let gap: CGFloat = 8
    private static let space = "board"

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(model.board) { card($0) }
        }
        .coordinateSpace(.named(Self.space))
        .animation(.snappy, value: model.board.map(\.id))
        // The lifted card left the board, or the list was replaced, mid-drag: the gesture is
        // cancelled without ending, so let go here.
        .onChange(of: model.board.map(\.id)) { _, ids in
            if let d = drag, !ids.contains(d.id) { endDrag() }
        }
        .onDisappear { endDrag() }
    }

    private func card(_ s: SessionState) -> some View {
        let lifted = drag?.id == s.id
        return Group {
            if let extra = railExtra {
                NarrowSessionCard(session: s, expanded: expanded == s.id, extra: extra,
                                  height: heights[s.id]) { h in if heights[s.id] != h { heights[s.id] = h } }
            } else {
                SessionCard(session: s, expanded: expanded == s.id) { onExpand(s) }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        if heights[s.id] != h { heights[s.id] = h }
                    }
            }
        }
            // A press here drags the card, not the panel.
            .background(PanelDragExempt())
            .scaleEffect(lifted ? 1.025 : 1)
            .shadow(color: .black.opacity(lifted ? 0.28 : 0), radius: lifted ? 14 : 0, y: lifted ? 6 : 0)
            .offset(y: offset(s.id))
            // The lifted card follows the pointer at once; the rest glide aside. On the drop,
            // offsets settle with the same curve as the reorder, so nothing swings back first.
            .animation(lifted ? nil : drag == nil ? .snappy : .snappy(duration: 0.22), value: offset(s.id))
            .animation(.snappy(duration: 0.18), value: lifted)
            .zIndex(lifted ? 1 : 0)
            // The laid-out frame, without the offset above.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { f in
                if frames[s.id] != f { frames[s.id] = f }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                    .onChanged { dragged(s, by: $0.translation.height) }
                    .onEnded { _ in dropped() }
            )
            .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
    }

    /// Where a card is drawn: the lifted one under the pointer, the ones it passed a slot over.
    private func offset(_ id: String) -> CGFloat {
        guard let d = drag else { return 0 }
        if id == d.id { return d.dy }
        guard let i = d.lane.firstIndex(of: id), let from = d.lane.firstIndex(of: d.id) else { return 0 }
        let room = (frames[d.id]?.height ?? 0) + Self.gap
        if from < i && i <= d.slot { return -room }
        if d.slot <= i && i < from { return room }
        return 0
    }

    private func dragged(_ s: SessionState, by dy: CGFloat) {
        // A drag of another card that never ended (cancelled) gives way.
        if let d = drag, d.id != s.id { endDrag() }
        if drag == nil {
            guard let f = frames[s.id] else { return }
            let lane = model.lane(of: s.id)
            // Free between the lane's ends, resisting past them.
            let lo = lane.first.flatMap { frames[$0] }.map { $0.minY - f.minY } ?? 0
            let hi = lane.last.flatMap { frames[$0] }.map { $0.maxY - f.maxY } ?? 0
            drag = CardDrag(id: s.id, lane: lane, lo: lo, hi: hi, slot: lane.firstIndex(of: s.id) ?? 0)
            NSCursor.closedHand.push()
            cursorPushed = true
        }
        guard var d = drag, d.id == s.id, let f = frames[s.id] else { return }
        d.dy = Self.rubberBand(dy, lo: d.lo, hi: d.hi)
        d.slot = slot(of: d, frame: f)
        drag = d
    }

    private func dropped() {
        guard let d = drag else { return }
        withAnimation(.snappy) {
            // The board may have changed under the drag (a status moved on): then it stays put.
            if model.lane(of: d.id) == d.lane { model.reorder(d.id, to: d.slot, in: d.lane) }
            endDrag()
        }
    }

    private func endDrag() {
        drag = nil
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
    }

    /// The lane index the lifted card would land at: past every card whose middle its leading
    /// edge has crossed, so a tall card reaches the ends of its lane too.
    private func slot(of d: CardDrag, frame f: CGRect) -> Int {
        guard let from = d.lane.firstIndex(of: d.id) else { return 0 }
        if d.dy > 0 {
            let bottom = f.maxY + d.dy
            return d.lane.indices.last { $0 > from && frames[d.lane[$0]].map { bottom > $0.midY } == true } ?? from
        }
        let top = f.minY + d.dy
        return d.lane.indices.first { $0 < from && frames[d.lane[$0]].map { top < $0.midY } == true } ?? from
    }

    /// Follows `dy` between `lo` and `hi`, and past them gives at most a few points, ever more slowly.
    static func rubberBand(_ dy: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        func give(_ x: CGFloat) -> CGFloat { 18 * (1 - 1 / (x / 50 + 1)) }
        if dy < lo { return lo - give(lo - dy) }
        if dy > hi { return hi + give(dy - hi) }
        return dy
    }
}

/// A card lifted off the board.
private struct CardDrag {
    let id: String
    /// Cards it can trade places with, itself included.
    let lane: [String]
    /// How far it may travel up (negative) and down before resisting.
    let lo: CGFloat
    let hi: CGFloat
    /// The lane index it would land at.
    var slot: Int
    var dy: CGFloat = 0
}

/// Chevron that rotates open; separate from the card tap, which jumps to the agent.
struct ExpandButton: View {
    let expanded: Bool
    var action: () -> Void

    var body: some View {
        CardIconButton(symbol: "chevron.down", help: expanded ? String(localized: "Hide details") : String(localized: "Show details"), action: action)
            .rotationEffect(.degrees(expanded ? 180 : 0))
            .animation(.snappy, value: expanded)
    }
}

/// Small round icon button on a card, so a tap on it does not count as a tap on the card.
struct CardIconButton: View {
    let symbol: String
    let help: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(hover ? Fill.controlHover : Fill.control))
                .foregroundStyle(hover ? .primary : .secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// 12.3k, 4.5M.
func compactCount(_ n: Int) -> String {
    switch n {
    case ..<1000: "\(n)"
    case ..<1_000_000: String(format: n < 10_000 ? "%.1fk" : "%.0fk", Double(n) / 1000)
    default: String(format: n < 10_000_000 ? "%.2fM" : "%.1fM", Double(n) / 1_000_000)
    }
}

extension SessionState {
    /// Tool calls: the transcript's count when known, else what hooks reported.
    var toolCallCount: Int { usage?.toolCalls ?? turns.reduce(0) { $0 + $1.toolCount } }
}

/// Card-sized stats: tool calls and tokens, when there are any.
struct UsageBadge: View {
    let session: SessionState
    var body: some View {
        let tools = session.toolCallCount
        HStack(spacing: 7) {
            if tools > 0 {
                Label(compactCount(tools), systemImage: "wrench.and.screwdriver").help("Tool calls: \(tools)")
            }
            if let u = session.usage, u.total > 0 {
                Label(compactCount(u.total), systemImage: "circle.hexagongrid").help(usageHelp(u))
            }
        }
        .labelStyle(TightLabel())
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .fixedSize()  // the project name beside it truncates instead
    }

    private func usageHelp(_ u: Usage) -> String {
        String(localized: "Tokens \(u.total): input \(u.input), output \(u.output), cache read \(u.cacheRead), cache write \(u.cacheWrite)")
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) { configuration.icon.font(.system(size: 8.5)); configuration.title }
    }
}

/// Expanded stats: token breakdown, context fill, most-used tools.
struct UsageGrid: View {
    let usage: Usage
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                cell(String(localized: "Input"), usage.input)
                cell(String(localized: "Output"), usage.output)
                cell(String(localized: "Cache read"), usage.cacheRead)
                cell(String(localized: "Cache write"), usage.cacheWrite)
            }
            if usage.context > 0 {
                HStack(spacing: 6) {
                    Text("Context").foregroundStyle(.secondary)
                    if let w = usage.contextWindow, w > 0 {
                        ProgressView(value: min(1, Double(usage.context) / Double(w))).controlSize(.mini).tint(.blue)
                        Text("\(compactCount(usage.context)) / \(compactCount(w))").monospacedDigit()
                    } else {
                        Text(compactCount(usage.context)).monospacedDigit()
                        Spacer()
                    }
                }
            }
            if !usage.tools.isEmpty {
                let top = usage.tools.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(5)
                HStack(spacing: 4) {
                    Text("Tools: \(usage.toolCalls)").foregroundStyle(.secondary)
                    ForEach(Array(top), id: \.key) { name, n in
                        Text("\(name) \(n)").padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.primary.opacity(0.06), in: Capsule())
                    }
                }
                .lineLimit(1)
            }
        }
        .font(.system(size: 10.5))
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cell(_ label: String, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            Text(compactCount(n)).font(.system(size: 11.5, weight: .semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
