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
        if status == .running {
            let start = currentTurn.flatMap { $0.endedAt == nil ? $0.startedAt : nil } ?? lastEventAt
            return relative(start, now: now)
        }
        return relative(lastEventAt, now: now) + "前"
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
    var onTap: () -> Void = {}
    @State private var hover = false

    var body: some View {
        let st = session.display
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                StatusGlyph(status: st, size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(session.clock(now: ctx.date))
                                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 5) {
                        AgentLogo(agent: session.agent, size: 12)
                        if !grouped, let p = session.projectName {
                            Text(p).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        StatusPill(status: st)
                    }
                    if let p = session.currentPrompt, Self.differs(p, from: session.title) {
                        Text(p).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(expanded ? 4 : 1)
                    }
                    detailLine(st)
                }
            }
            PermissionButtons(session: session)
            if expanded { expandedBody(st) }
            if st == .review && !expanded { actions(st) }
        }
        .padding(10)
        .card(st, hover: hover)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button("跳转到终端") { model.jump(session.id) }
            if st == .review { Button("标记已验收") { model.markRead(session.id) } }
            Button("复制 cwd / session") { model.jumper.copyContext(session) }
            Divider()
            MoveMenu(ids: [session.id])
            Divider()
            Button("从列表删除", role: .destructive) { model.remove(session.id) }
        }
    }

    /// The prompt adds something beyond the title (not just its first line).
    static func differs(_ prompt: String, from title: String) -> Bool {
        let t = title.hasSuffix("…") ? String(title.dropLast()) : title
        return !prompt.hasPrefix(t)
    }

    /// Second line: what needs the user, what is running, or the last reply.
    @ViewBuilder private func detailLine(_ st: DisplayStatus) -> some View {
        switch st {
        case .needsInput, .stuck:
            Text(session.needsInputMessage ?? session.stuckReason ?? "需要你处理")
                .font(.system(size: 11.5)).foregroundStyle(st.tint).lineLimit(expanded ? 6 : 2)
        case .running:
            // Always one line while running: between tools the last one stays, so the card does
            // not grow and shrink with every tool call.
            if let t = session.latestTool {
                ToolLine(tool: t)
            } else if let r = session.peek?.recap {
                Text(r).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            } else if !session.hooked {
                Text("此会话在安装 hook 前启动，只能看到粗略状态").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        case .review, .done, .ended:
            if let r = session.lastReply {
                Text(r).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(expanded ? 12 : 2)
            }
        }
    }

    @ViewBuilder private func expandedBody(_ st: DisplayStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let r = session.peek?.recap, st != .running {
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
            HStack(spacing: 4) {
                Text(session.agent.displayName)
                if !session.subagents.isEmpty { Text("· \(session.subagents.count) 个子 agent") }
                if session.terminal?.isWave == true { Text("· Wave") }
                if !session.hooked { Text("· 未挂 hook").foregroundStyle(.orange) }
            }
            .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            actions(st)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func actions(_ st: DisplayStatus) -> some View {
        HStack(spacing: 6) {
            if st == .review {
                Button { withAnimation(.snappy) { model.markRead(session.id) } } label: { Label("验收", systemImage: "checkmark") }
                    .buttonStyle(PillButtonStyle(tint: .green, prominent: true))
            }
            Button { model.jump(session.id) } label: { Label("去终端查看", systemImage: "arrow.up.forward.app") }
                .buttonStyle(PillButtonStyle(tint: st == .review ? .green : .accentColor))
            Spacer()
        }
    }
}

struct ToolLine: View {
    let tool: ToolCall
    var body: some View {
        HStack(spacing: 5) {
            Group {
                if tool.isRunning {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                } else {
                    Image(systemName: tool.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(tool.isError ? Color.red : Color.secondary.opacity(0.6))
                }
            }
            .font(.system(size: 10)).frame(width: 12, height: 12)
            Text(tool.name).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tool.isRunning ? Color.blue : Color.primary.opacity(0.8))
            Text(tool.summary).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
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
    var expanded: String?
    var onTap: (SessionState) -> Void
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
        SessionCard(session: s, expanded: expanded == s.id, grouped: grouped) { onTap(s) }
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
    let group: BoardGroup
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(group.name).font(.system(size: 11.5, weight: .bold)).lineLimit(1)
            Text("\(group.sessions.count)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.primary.opacity(0.08), in: Capsule()).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: -4) {
                ForEach(Array(Set(group.sessions.map(\.agent))).sorted { $0.rawValue < $1.rawValue }, id: \.self) {
                    AgentLogo(agent: $0, size: 11)
                }
            }
            Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6).padding(.top, 3)
        .contentShape(Rectangle())
        .contextMenu { MoveMenu(ids: group.sessions.map(\.id)) }
        .help("拖动整组排序")
    }
}
