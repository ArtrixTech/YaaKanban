import SwiftUI
import YaaCore

/// Side of the screen the floating panel is snapped to.
enum DockEdge { case left, right }

/// The floating panel folded against a screen edge: one block per session, newest state first,
/// like the board. Hovering it peeks the full panel; a button unfolds it for good.
struct SidebarRail: View {
    @Environment(AppModel.self) private var model
    let edge: DockEdge
    var onHide: () -> Void = {}
    /// Room for the blocks once the header is taken.
    var listRoom: CGFloat

    static let width: CGFloat = 112

    var body: some View {
        let sessions = model.board.flatMap(\.sessions)
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                BrandMark(size: 20)
                Spacer(minLength: 4)
                IconButton(symbol: edge == .right ? "chevron.left.2" : "chevron.right.2", help: "展开为悬浮窗") {
                    model.settings.sidebarExpanded = true
                }
            }
            if sessions.isEmpty {
                Image(systemName: "moon.zzz.fill").font(.system(size: 16)).foregroundStyle(.tertiary)
                    .padding(.vertical, 6).help("没有进行中的任务")
            } else {
                ScrollView {
                    VStack(spacing: 6) { ForEach(sessions) { RailBlock(session: $0) } }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollIndicators(.never)
                .frame(height: min(contentHeight, max(80, listRoom)))
            }
        }
        .padding(8)
        .frame(width: Self.width)
        .contextMenu {
            Button("展开为悬浮窗") { model.settings.sidebarExpanded = true }
            Button("主界面") { AppWindows.open(.main) }
            Button("设置…") { AppWindows.open(.settings) }
            Divider()
            Button("隐藏（⌥⌘K）", action: onHide)
        }
    }

    @State private var contentHeight: CGFloat = 0
}

/// One session in the rail: agent logo with a status mark, title, clock.
struct RailBlock: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    @State private var hover = false

    var body: some View {
        let st = session.display
        let children = model.subagents(of: session.id).count + session.subagents.count
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                StatusGlyph(status: st, size: 18)
                AgentLogo(agent: session.agent, size: 12)
                Spacer(minLength: 0)
                if children > 0 {
                    Text("↳\(children)").font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary).help("\(children) 个子 agent")
                }
            }
            Text(session.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                if let p = session.projectName {
                    Text(p).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(session.clock(now: ctx.date)).font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
            }
        }
        .padding(7)
        .card(st, hover: hover, radius: 10)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .onTapGesture { model.jump(session.id) }
        .help(help(st))
        .contextMenu {
            Button("跳转到终端") { model.jump(session.id) }
            if st == .review { Button("标记已验收") { model.markRead(session.id) } }
            Button("展开为悬浮窗") { model.settings.sidebarExpanded = true }
            Divider()
            Button("结束（移出悬浮窗）") { model.dismiss(session.id) }
        }
    }

    private func help(_ st: DisplayStatus) -> String {
        var lines = ["\(session.title) · \(st.label)"]
        if let d = SubagentSlots.detail(session) { lines.append(d) }
        if st == .needsInput { lines.append("展开悬浮窗可直接允许 / 拒绝") }
        lines.append("点击跳转到 \(session.agent.displayName)")
        return lines.joined(separator: "\n")
    }
}
