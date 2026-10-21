import SwiftUI
import YaaCore

/// Full detail: header, what needs the user, turns, and the tool timeline.
struct SessionDetail: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    @State private var openTool: String?

    var body: some View {
        let st = model.display(session)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(st)
                if st == .review { reviewBanner }
                if st == .needsInput || st == .stuck {
                    Section(title: st.label, symbol: st.symbol, tint: st.tint) {
                        Text(session.needsInputMessage ?? session.stuckReason ?? "").textSelection(.enabled)
                            .font(.system(size: 13))
                        PermissionButtons(session: session)
                    }
                }
                if st != .review, let last = session.lastReply {
                    Section(title: "最后回复", symbol: "text.bubble") {
                        Text(last).textSelection(.enabled).font(.system(size: 12.5))
                    }
                }
                if let recap = session.peek?.recap {
                    Section(title: "会话概要", symbol: "text.quote") {
                        Text(recap).textSelection(.enabled).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    }
                }
                if let u = session.usage {
                    Section(title: "用量", symbol: "chart.bar", trailing: "合计 \(compactCount(u.total)) token") {
                        UsageGrid(usage: u)
                    }
                }
                if !session.subagents.isEmpty {
                    Section(title: "子 agent", symbol: "person.2") {
                        ForEach(session.subagents, id: \.id) { a in
                            HStack { Text(a.type ?? "agent"); Spacer(); Text(relative(a.startedAt)).foregroundStyle(.secondary) }
                                .font(.system(size: 12))
                        }
                    }
                }
                turns
                tools
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .animation(.snappy, value: st)
    }

    private func header(_ st: DisplayStatus) -> some View {
        HStack(alignment: .top, spacing: 14) {
            StatusGlyph(status: st, size: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(session.title).font(.system(size: 20, weight: .bold)).lineLimit(2)
                    StatusPill(status: st)
                }
                if let p = session.currentPrompt {
                    Text(p).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                }
                HStack(spacing: 6) {
                    HStack(spacing: 4) { AgentLogo(agent: session.agent, size: 11); Text(session.agent.displayName) }
                        .font(.system(size: 11)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.primary.opacity(0.06), in: Capsule()).foregroundStyle(.secondary)
                    if let p = session.projectName { meta("folder.fill", p) }
                    if let cwd = session.cwd { meta("arrow.turn.down.right", (cwd as NSString).abbreviatingWithTildeInPath) }
                    if let pid = session.agentPid { meta("number", "pid \(pid)") }
                    if session.terminal?.isWave == true { meta("terminal", "Wave") }
                    if !session.hooked { meta("exclamationmark.circle", "未挂 hook").foregroundStyle(.orange) }
                }
                HStack(spacing: 6) {
                    Button { model.jump(session.id) } label: {
                        Label(AppModel.isGone(session) ? "在原终端恢复" : "跳转到终端", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(PillButtonStyle(tint: .accentColor, prominent: true))
                    Button { model.jumper.copyContext(session) } label: { Label("复制 cwd / session", systemImage: "doc.on.doc") }
                        .buttonStyle(PillButtonStyle())
                    Spacer()
                    Button(role: .destructive) { model.remove(session.id) } label: { Label("删除", systemImage: "trash") }
                        .buttonStyle(PillButtonStyle(tint: .red))
                }
                .padding(.top, 2)
            }
        }
    }

    private func meta(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11)).lineLimit(1).truncationMode(.head)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.primary.opacity(0.06), in: Capsule())
            .foregroundStyle(.secondary)
    }

    /// The result of a finished turn, with the one action that matters: accept it.
    private var reviewBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("这一轮跑完了，等你验收", systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
            if let last = session.lastReply {
                Text(last).font(.system(size: 12.5)).textSelection(.enabled)
            }
            HStack(spacing: 6) {
                Button { model.jump(session.id) } label: { Label("去查看", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(PillButtonStyle(tint: .green, prominent: true))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(.review, radius: 14)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var turns: some View {
        Section(title: "轮次", symbol: "arrow.triangle.2.circlepath") {
            if session.turns.isEmpty { Text("暂无").foregroundStyle(.secondary).font(.system(size: 12)) }
            ForEach(session.turns.reversed()) { t in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("#\(t.id)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.tertiary)
                        .frame(width: 28, alignment: .trailing)
                    Text(t.prompt.isEmpty ? "（无 prompt）" : t.prompt).font(.system(size: 12.5)).lineLimit(2)
                    Spacer()
                    Text("\(t.toolCount) 工具 · \(relative(t.startedAt, now: t.endedAt ?? Date()))")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var tools: some View {
        Section(title: "工具调用", symbol: "wrench.and.screwdriver", trailing: "最近 \(session.tools.count) 次") {
            if session.tools.isEmpty { Text("暂无").foregroundStyle(.secondary).font(.system(size: 12)) }
            ForEach(session.tools.reversed()) { t in
                VStack(alignment: .leading, spacing: 6) {
                    Button { withAnimation(.snappy) { openTool = openTool == t.id ? nil : t.id } } label: {
                        HStack {
                            ToolLine(tool: t)
                            Spacer()
                            if t.subagentId != nil { Text("子 agent").font(.system(size: 10)).foregroundStyle(.purple) }
                            Text(t.startedAt, style: .time).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(openTool == t.id ? 90 : 0))
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if openTool == t.id {
                        CodeBlock(title: "输入", text: t.input)
                        if let o = t.output { CodeBlock(title: "输出", text: o) }
                    }
                }
            }
        }
    }
}

/// Titled rounded section used by the detail page.
private struct Section<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    var trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(tint)
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(.tertiary) }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(.done, radius: 14)
    }
}
