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
        }
    }
}

func relative(_ d: Date, now: Date = Date()) -> String {
    let s = Int(now.timeIntervalSince(d))
    if s < 60 { return "\(max(s, 0))秒" }
    if s < 3600 { return "\(s / 60)分" }
    if s < 86400 { return "\(s / 3600)时\(s % 3600 / 60)分" }
    return "\(s / 86400)天"
}

extension SessionState {
    /// The prompt of the turn in progress or just finished.
    var currentPrompt: String? {
        if let p = currentTurn?.prompt, !p.isEmpty { return p }
        return peek?.lastPrompt
    }

    /// Running: how long the turn has run. Otherwise: how long ago it last changed.
    func clock(now: Date) -> String {
        status == .running ? relative(clockStart, now: now) : relative(lastEventAt, now: now) + "前"
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
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                HStack(spacing: 6) {
                    Button { model.decide(session.id, .allow) } label: { Label("允许一次", systemImage: "checkmark") }
                        .buttonStyle(PillButtonStyle(tint: .green, prominent: true))
                    Button { model.decide(session.id, .deny) } label: { Label("拒绝", systemImage: "xmark") }
                        .buttonStyle(PillButtonStyle(tint: .red))
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
    /// Inside a project group, whose header already names the project.
    var grouped = false
    var onExpand: () -> Void = {}
    @State private var hover = false

    var body: some View {
        let st = session.display
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                StatusGlyph(status: st, size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    // 1: title, clock, expand.
                    HStack(spacing: 6) {
                        Text(session.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(session.clock(now: ctx.date))
                                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ExpandButton(expanded: expanded, action: onExpand)
                        CardIconButton(symbol: "xmark", help: "结束：移出悬浮窗（保留在历史，需要你时会回来）") {
                            model.dismiss(session.id)
                        }
                    }
                    // 2: agent, project, status, stats.
                    HStack(spacing: 5) {
                        AgentLogo(agent: session.agent, size: 12)
                        if !grouped, let p = session.projectName {
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
            }
            SubagentSlots(session: session)
            PermissionButtons(session: session)
            if expanded { expandedBody(st) }
        }
        .padding(10)
        .card(st, hover: hover)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .onTapGesture { model.jump(session.id) }
        .help("点击跳转到 \(session.agent.displayName)")
        .contextMenu {
            Button("跳转到终端") { model.jump(session.id) }
            Button(expanded ? "收起详情" : "展开详情", action: onExpand)
            if st == .review { Button("标记已验收") { model.markRead(session.id) } }
            Button("复制 cwd / session") { model.jumper.copyContext(session) }
            Divider()
            MoveMenu(ids: [session.id])
            Divider()
            Button("结束（移出悬浮窗）") { model.dismiss(session.id) }
            Button("从列表删除", role: .destructive) { model.remove(session.id) }
        }
    }

    /// The agent's latest words this turn; for blocked sessions, what it is waiting for.
    @ViewBuilder private func replyLine(_ st: DisplayStatus) -> some View {
        switch st {
        case .needsInput, .stuck:
            Text(session.needsInputMessage ?? session.stuckReason ?? "需要你处理")
                .font(.system(size: 11.5)).foregroundStyle(st.tint).lineLimit(expanded ? 6 : 2)
        default:
            if let r = session.lastReply {
                Text(r).font(.system(size: 11.5)).foregroundStyle(.primary.opacity(0.8)).lineLimit(expanded ? 12 : 2)
            } else if st == .running {
                Text("思考中…").font(.system(size: 11.5)).foregroundStyle(.tertiary)
            } else if !session.hooked {
                Text("此会话在安装 hook 前启动，只能看到粗略状态").font(.system(size: 11)).foregroundStyle(.tertiary)
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
                if !session.subagents.isEmpty { Text("· \(session.subagents.count) 个子 agent") }
                if session.terminal?.isWave == true { Text("· Wave") }
                if !session.hooked { Text("· 未挂 hook").foregroundStyle(.orange) }
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
                    SubagentRow(status: .running, title: a.type ?? "子 agent",
                                detail: tool.map { "\($0.name) \($0.summary)" }, since: a.startedAt)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.leading, 36)
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
            Text(text.isEmpty ? "（已清理）" : text)
                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// Up / down / top for a card or a whole group.
struct MoveMenu: View {
    @Environment(AppModel.self) private var model
    let ids: [String]
    var body: some View {
        Button("上移") { withAnimation(.snappy) { model.step(ids, by: -1) } }
        Button("下移") { withAnimation(.snappy) { model.step(ids, by: 1) } }
        Button("置顶") { withAnimation(.snappy) { model.step(ids, by: nil) } }
    }
}

/// Session ids being dragged, as one line of text.
enum DragIds {
    static func encode(_ ids: [String]) -> String { "yaak:" + ids.joined(separator: "\n") }
    static func decode(_ s: String) -> [String]? {
        s.hasPrefix("yaak:") ? s.dropFirst(5).split(separator: "\n").map(String.init) : nil
    }
}

/// The board: project groups of session cards, reorderable by drag or context menu.
struct BoardList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railExtra) private var railExtra
    var expanded: String?
    var onExpand: (SessionState) -> Void = { _ in }
    /// Each card's height in the full panel, which it keeps when the panel folds. Kept here, across
    /// folding, so a folded card has its height from the first frame.
    @State private var heights: [String: CGFloat] = [:]
    @State private var dropTarget: String?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.board) { g in
                if g.sessions.count == 1, let s = g.sessions.first {
                    card(s, grouped: false)
                } else {
                    VStack(spacing: 5) {
                        GroupHeader(group: g)
                            .draggable(DragIds.encode(g.sessions.map(\.id)))
                            .dropDestination(for: String.self) { items, _ in drop(items, before: g.sessions.first?.id) }
                                isTargeted: { dropTarget = $0 ? g.id : (dropTarget == g.id ? nil : dropTarget) }
                            .overlay(alignment: .top) { dropLine(g.id) }
                        ForEach(g.sessions) { card($0, grouped: true) }
                    }
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.primary.opacity(0.03)))
                    .transition(.opacity)
                }
            }
        }
        .animation(.snappy, value: model.board.map { $0.sessions.map(\.id) })
    }

    private func card(_ s: SessionState, grouped: Bool) -> some View {
        Group {
            if let extra = railExtra {
                NarrowSessionCard(session: s, expanded: expanded == s.id, grouped: grouped, extra: extra,
                                  height: heights[s.id]) { h in if heights[s.id] != h { heights[s.id] = h } }
            } else {
                SessionCard(session: s, expanded: expanded == s.id, grouped: grouped) { onExpand(s) }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        if heights[s.id] != h { heights[s.id] = h }
                    }
            }
        }
            .draggable(DragIds.encode([s.id])) {
                Text(s.title).font(.system(size: 12, weight: .semibold)).padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .dropDestination(for: String.self) { items, _ in drop(items, before: s.id) }
                isTargeted: { dropTarget = $0 ? s.id : (dropTarget == s.id ? nil : dropTarget) }
            .overlay(alignment: .top) { dropLine(s.id) }
            .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
    }

    private func drop(_ items: [String], before target: String?) -> Bool {
        guard let ids = items.first.flatMap(DragIds.decode), !ids.isEmpty else { return false }
        withAnimation(.snappy) { model.move(ids, before: target) }
        return true
    }

    /// Insertion marker above the hovered drop target.
    @ViewBuilder private func dropLine(_ id: String) -> some View {
        if dropTarget == id {
            Capsule().fill(Color.accentColor).frame(height: 3).offset(y: -5).padding(.horizontal, 6)
                .transition(.opacity)
        }
    }
}

struct GroupHeader: View {
    @Environment(\.railExtra) private var railExtra
    let group: BoardGroup
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(group.name).font(.system(size: 11.5, weight: .bold)).lineLimit(1)
            Text("\(group.sessions.count)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.primary.opacity(0.08), in: Capsule()).foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 0)
            if railExtra == nil { trailing }
        }
        .padding(.horizontal, 6).padding(.top, 3)
        .contentShape(Rectangle())
        .contextMenu { MoveMenu(ids: group.sessions.map(\.id)) }
        .help(railExtra == nil ? "拖动整组排序" : group.name)
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 6) {
            HStack(spacing: -4) {
                ForEach(Array(Set(group.sessions.map(\.agent))).sorted { $0.rawValue < $1.rawValue }, id: \.self) {
                    AgentLogo(agent: $0, size: 11)
                }
            }
            Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
    }
}

/// Chevron that rotates open; separate from the card tap, which jumps to the agent.
struct ExpandButton: View {
    let expanded: Bool
    var action: () -> Void

    var body: some View {
        CardIconButton(symbol: "chevron.down", help: expanded ? "收起详情" : "展开详情", action: action)
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
                .background(Circle().fill(.primary.opacity(hover ? 0.12 : 0.06)))
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
                Label(compactCount(tools), systemImage: "wrench.and.screwdriver").help("工具调用 \(tools) 次")
            }
            if let u = session.usage, u.total > 0 {
                Label(compactCount(u.total), systemImage: "circle.hexagongrid").help(usageHelp(u))
            }
        }
        .labelStyle(TightLabel())
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.tertiary)
    }

    private func usageHelp(_ u: Usage) -> String {
        "Token 合计 \(u.total)：输入 \(u.input)，输出 \(u.output)，缓存读 \(u.cacheRead)，缓存写 \(u.cacheWrite)"
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
                cell("输入", usage.input)
                cell("输出", usage.output)
                cell("缓存读", usage.cacheRead)
                cell("缓存写", usage.cacheWrite)
            }
            if usage.context > 0 {
                HStack(spacing: 6) {
                    Text("上下文").foregroundStyle(.secondary)
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
                    Text("\(usage.toolCalls) 次工具").foregroundStyle(.secondary)
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
