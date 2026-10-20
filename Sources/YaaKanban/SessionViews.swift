import SwiftUI
import YaaCore

extension SessionStatus {
    var label: String {
        switch self {
        case .running: "运行中"
        case .needsInput: "需要输入"
        case .stuck: "可能卡住"
        case .idle: "已完成"
        case .ended: "已结束"
        }
    }

    var color: Color {
        switch self {
        case .running: .blue
        case .needsInput: .red
        case .stuck: .orange
        case .idle: .gray
        case .ended: .secondary
        }
    }
}

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

struct StatusBadge: View {
    let status: SessionStatus
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(status.label).font(.caption2).foregroundStyle(status.color)
        }
    }
}

/// Allow / Deny buttons, only while the hook is waiting for the app.
struct PermissionButtons: View {
    @Environment(AppModel.self) private var model
    let session: SessionState

    var body: some View {
        if let p = session.pendingPermission, p.awaitingDecision, model.canDecide(session.id) {
            if let detail = p.detail {
                Text(detail).font(.caption.monospaced()).lineLimit(8).textSelection(.enabled)
                    .padding(4).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            HStack(spacing: 6) {
                Button("允许一次") { model.decide(session.id, .allow) }
                    .buttonStyle(.borderedProminent).tint(.green)
                Button("拒绝") { model.decide(session.id, .deny) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }
}

/// Compact row used by the menu popover and the floating panel.
struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: session.agent.symbol).frame(width: 14).foregroundStyle(.secondary)
                Text(session.projectName ?? session.agent.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                StatusBadge(status: session.status)
                Spacer(minLength: 4)
                if !session.subagents.isEmpty {
                    Text("\(session.subagents.count) 子 agent").font(.caption2).foregroundStyle(.secondary)
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(relative(session.lastEventAt, now: ctx.date)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button { model.jumper.jump(to: session) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.borderless).help("跳转到终端")
            }
            if let msg = attentionText {
                Text(msg).font(.caption).foregroundStyle(session.status.color).lineLimit(expanded ? 6 : 2)
            } else if let t = session.latestTool {
                ToolLine(tool: t)
            }
            PermissionButtons(session: session)
            if expanded {
                Divider()
                ForEach(session.tools.suffix(8).reversed()) { ToolLine(tool: $0) }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var attentionText: String? {
        switch session.status {
        case .needsInput: session.needsInputMessage ?? "需要你的输入"
        case .stuck: session.stuckReason
        default: nil
        }
    }
}

struct ToolLine: View {
    let tool: ToolCall
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tool.isRunning ? "circle.dotted" : (tool.isError ? "xmark.circle" : "checkmark.circle"))
                .foregroundStyle(tool.isRunning ? Color.blue : (tool.isError ? Color.red : Color.secondary))
                .font(.caption2)
            Text(tool.name).font(.caption.weight(.medium))
            Text(tool.summary).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// Full detail: header, attention, turns, and the tool timeline.
struct SessionDetail: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    @State private var openTool: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if session.status.needsAttention {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.needsInputMessage ?? session.stuckReason ?? "").textSelection(.enabled)
                            PermissionButtons(session: session)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } label: { Label(session.status.label, systemImage: "exclamationmark.bubble").foregroundStyle(session.status.color) }
                }
                if let last = session.currentTurn?.lastMessage, session.status == .idle {
                    GroupBox("最后回复") { Text(last).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
                if !session.subagents.isEmpty {
                    GroupBox("子 agent") {
                        ForEach(session.subagents, id: \.id) { a in
                            HStack { Text(a.type ?? "agent"); Spacer(); Text(relative(a.startedAt)).foregroundStyle(.secondary) }
                        }
                    }
                }
                GroupBox("轮次") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(session.turns.reversed()) { t in
                            HStack(alignment: .top) {
                                Text("#\(t.id)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Text(t.prompt.isEmpty ? "（无 prompt）" : t.prompt).lineLimit(2)
                                Spacer()
                                Text("\(t.toolCount) 工具 · \(duration(t))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if session.turns.isEmpty { Text("暂无").foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("工具调用（最近 \(session.tools.count) 次）") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(session.tools.reversed()) { t in
                            VStack(alignment: .leading, spacing: 4) {
                                Button { openTool = openTool == t.id ? nil : t.id } label: {
                                    HStack {
                                        ToolLine(tool: t)
                                        Spacer()
                                        if t.subagentId != nil { Text("子 agent").font(.caption2).foregroundStyle(.purple) }
                                        Text(t.startedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if openTool == t.id {
                                    CodeBlock(title: "输入", text: t.input)
                                    if let o = t.output { CodeBlock(title: "输出", text: o) }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: session.agent.symbol)
                Text(session.title).font(.title3.weight(.semibold)).lineLimit(2)
                Spacer()
                StatusBadge(status: session.status)
            }
            HStack(spacing: 12) {
                Text(session.agent.displayName)
                if let cwd = session.cwd { Text(cwd).truncationMode(.head) }
                if let pid = session.agentPid { Text("pid \(pid)") }
                if session.terminal?.isWave == true { Text("Wave") }
                if !session.hooked { Text("未挂 hook，仅粗略状态").foregroundStyle(.orange) }
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Button("跳转到终端") { model.jumper.jump(to: session) }
                Button("复制 cwd / session") { model.jumper.copyContext(session) }
                Spacer()
                Button("从历史删除", role: .destructive) { model.remove(session.id) }
            }.controlSize(.small)
        }
    }

    private func duration(_ t: Turn) -> String {
        relative(t.startedAt, now: t.endedAt ?? Date())
    }
}

struct CodeBlock: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(text.isEmpty ? "（已清理）" : text)
                .font(.caption.monospaced()).textSelection(.enabled)
                .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
