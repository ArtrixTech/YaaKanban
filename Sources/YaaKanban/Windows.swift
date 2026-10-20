import AppKit
import ServiceManagement
import SwiftUI
import YaaCore
import YaaIntegrations

/// Header shared by the panel and the menu: mark, title, and counts of what wants the user.
struct BoardHeader<Trailing: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            BrandMark(size: 20)
            Text("YaaKanban").font(.system(size: 13, weight: .bold))
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                let counts = self.counts
                ForEach(counts, id: \.0.rank) { st, n in CountChip(count: n, status: st).transition(.scale.combined(with: .opacity)) }
            }
            .animation(.snappy, value: counts.map(\.1))
            trailing
        }
    }

    private var counts: [(DisplayStatus, Int)] {
        let all = model.activeSessions.map(\.display)
        return [DisplayStatus.needsInput, .stuck, .review, .running].compactMap { st in
            let n = all.filter { $0 == st }.count
            return n > 0 ? (st, n) : nil
        }
    }
}

/// App logo from the bundle, with a symbol fallback when running unbundled.
struct BrandMark: View {
    var size: CGFloat
    private static let image = Bundle.main.url(forResource: "logo", withExtension: "svg").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if let img = Self.image {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: size * 0.6)).frame(width: size, height: size)
        }
    }
}

/// Menu-bar popover: active sessions plus shortcuts.
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let panel: FloatingPanelController
    @State private var expanded: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BoardHeader { EmptyView() }
            if let err = model.serverError { Text(err).font(.caption).foregroundStyle(.red) }
            if model.activeSessions.isEmpty {
                EmptyBoard()
            } else {
                ScrollView {
                    BoardList(expanded: expanded) { s in
                        withAnimation(.spring(duration: 0.3, bounce: 0.15)) { expanded = expanded == s.id ? nil : s.id }
                    }
                }
                .frame(maxHeight: 460)
                .scrollIndicators(.never)
            }
            HStack(spacing: 6) {
                Button { open(nil) } label: { Label("主界面", systemImage: "macwindow") }
                    .buttonStyle(PillButtonStyle())
                Button { panel.toggle() } label: {
                    Label(panel.isVisible ? "隐藏悬浮窗" : "显示悬浮窗", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(PillButtonStyle()).help("⌥⌘K")
                Spacer()
                SettingsLink { Image(systemName: "gearshape").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("设置")
                IconButton(symbol: "power", help: "退出") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 380)
    }

    private func open(_ s: SessionState?) {
        if let s { model.selection = s.id }
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct EmptyBoard: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 22)).foregroundStyle(.tertiary)
            Text("没有进行中的任务").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
    }
}

/// Floating panel content, at its natural height; the borderless window resizes to fit it.
struct FloatingPanelView: View {
    @Environment(AppModel.self) private var model
    var onHide: () -> Void = {}
    /// Natural content height, reported on every layout change so the window can follow it.
    var onHeight: (CGFloat) -> Void = { _ in }
    /// Room the window has on its screen; the list gives way so the panel never runs off it.
    var room: PanelRoom?
    @State private var expanded: String?
    @State private var listHeight: CGFloat = 0
    /// Everything but the list (header, grip, padding), so the list knows what is left for it.
    @State private var chrome: CGFloat = 0
    /// List height when a resize drag began.
    @State private var dragStart: CGFloat?

    static let minList: CGFloat = 120
    static let maxList: CGFloat = 1400

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 10) {
            BoardHeader {
                IconButton(symbol: "macwindow", help: "主界面") { AppWindows.open(.main) }
                IconButton(symbol: "gearshape", help: "设置") { AppWindows.open(.settings) }
                IconButton(symbol: settings.panelCollapsed ? "chevron.down" : "chevron.up",
                           help: settings.panelCollapsed ? "展开" : "收起") {
                    withAnimation(.snappy) { settings.panelCollapsed.toggle() }
                }
                IconButton(symbol: "xmark", help: "隐藏（⌥⌘K）", action: onHide)
            }
            if !settings.panelCollapsed {
                if model.activeSessions.isEmpty {
                    EmptyBoard().transition(.opacity)
                } else {
                    ScrollView {
                        BoardList(expanded: expanded) { s in
                            withAnimation(.spring(duration: 0.3, bounce: 0.15)) { expanded = expanded == s.id ? nil : s.id }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                    }
                    .scrollIndicators(.never)
                    .frame(height: shownList)
                    .transition(.opacity)
                    ResizeGrip { delta in
                        if delta == nil { dragStart = nil; return }
                        let start = dragStart ?? shownList
                        dragStart = start
                        settings.panelListHeight = min(Self.maxList, max(Self.minList, start + delta!))
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 10)
        .padding(.bottom, settings.panelCollapsed || model.activeSessions.isEmpty ? 10 : 0)
        .frame(width: 340, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
            chrome = h - (listShown ? shownList : 0)
            onHeight(h)
        }
        // Top-aligned however tall the window is at the moment: while it catches up with the
        // content, the default (centering) would shift the top edge up and down.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var listShown: Bool { !model.settings.panelCollapsed && !model.activeSessions.isEmpty }

    private var shownList: CGFloat {
        let fits = room.map { max(Self.minList, $0.height - chrome) } ?? .infinity
        return min(listHeight, model.settings.panelListHeight, fits)
    }
}

/// Usable height on the floating panel's screen, kept current by the panel controller.
@MainActor @Observable
final class PanelRoom {
    var height: CGFloat = .infinity
}

/// Bottom handle that sets the list height. AppKit-backed so the drag does not move the
/// (movable-by-background) window, and so it shows the resize cursor.
struct ResizeGrip: View {
    /// Vertical drag distance (down is positive); nil when the drag ends.
    var onDrag: (CGFloat?) -> Void
    @State private var hover = false

    var body: some View {
        Capsule().fill(.primary.opacity(hover ? 0.35 : 0.15)).frame(width: 36, height: 4)
            .frame(maxWidth: .infinity).frame(height: 14)
            .overlay(GripTracker(onDrag: onDrag))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
            .help("拖动调整高度")
    }
}

private struct GripTracker: NSViewRepresentable {
    var onDrag: (CGFloat?) -> Void

    func makeNSView(context: Context) -> TrackerView { TrackerView() }
    func updateNSView(_ v: TrackerView, context: Context) { v.onDrag = onDrag }

    final class TrackerView: NSView {
        var onDrag: (CGFloat?) -> Void = { _ in }
        private var startY: CGFloat?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
        override func mouseDown(with e: NSEvent) { startY = NSEvent.mouseLocation.y }
        override func mouseDragged(with e: NSEvent) {
            guard let startY else { return }
            onDrag(startY - NSEvent.mouseLocation.y)
        }
        override func mouseUp(with e: NSEvent) { startY = nil; onDrag(nil) }
    }
}

/// Opens the SwiftUI windows from AppKit code (the floating panel is outside any scene, so it has
/// no `openWindow`). `WindowOpener`, living in the menu-bar label, does the opening.
enum AppWindows {
    enum Kind: String { case main, settings }
    static let request = Notification.Name("YaaOpenWindow")
    static func open(_ k: Kind) { NotificationCenter.default.post(name: request, object: k.rawValue) }
}

struct WindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: AppWindows.request)) { n in
            NSApp.activate()
            switch AppWindows.Kind(rawValue: n.object as? String ?? "") {
            case .main: openWindow(id: "main")
            case .settings: openSettings()
            case nil: break
            }
        }
    }
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var filter: AgentKind?
    @State private var query = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                section("活跃", model.board.flatMap(\.sessions))
                section("历史", model.allSessions.filter { s in !model.activeSessions.contains { $0.id == s.id } })
            }
            .searchable(text: $query, placement: .sidebar, prompt: "项目 / prompt")
            .toolbar {
                Picker("Agent", selection: $filter) {
                    Text("全部").tag(AgentKind?.none)
                    ForEach(AgentKind.allCases, id: \.self) { Text($0.displayName).tag(AgentKind?.some($0)) }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let id = model.selection, let s = model.sessions[id] {
                SessionDetail(session: s)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 34)).foregroundStyle(.tertiary)
                    Text("选择一个会话").foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [SessionState]) -> some View {
        let shown = list.filter(matches)
        if !shown.isEmpty {
            Section(title) {
                ForEach(shown) { s in
                    HStack(spacing: 10) {
                        StatusGlyph(status: s.display, size: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(s.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 2)
                                Text(s.lastEventAt, format: .dateTime.month().day().hour().minute())
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 4) {
                                AgentLogo(agent: s.agent, size: 11)
                                Text(s.projectName ?? s.agent.displayName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(s.id)
                    .contextMenu {
                        if s.display == .review { Button("标记已验收") { model.markRead(s.id) } }
                        if s.dismissedAt != nil { Button("恢复到悬浮窗") { model.undismiss(s.id) } }
                        Button("从历史删除", role: .destructive) { model.remove(s.id) }
                    }
                }
            }
        }
    }

    private func matches(_ s: SessionState) -> Bool {
        if let filter, s.agent != filter { return false }
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return [s.cwd, s.title, s.sessionId, s.peek?.lastPrompt].compactMap { $0?.lowercased() }.contains { $0.contains(q) }
            || s.turns.contains { $0.prompt.lowercased().contains(q) }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    let panel: FloatingPanelController
    @State private var integrationMessage: String?
    @State private var refresh = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Agent 接入") {
                ForEach(Integrations.all, id: \.agent) { i in
                    let status = i.status(home: Paths.home(), yaak: Self.yaak)
                    HStack {
                        Text(i.agent.displayName)
                        Spacer()
                        Text(statusLabel(status)).foregroundStyle(status == .installed ? .green : .secondary).font(.caption)
                        if status == .outdated {
                            Button("更新") { apply(i, install: true) }
                        }
                        if status == .installed || status == .outdated {
                            Button("卸载") { apply(i, install: false) }
                        } else if status == .notInstalled {
                            Button("安装") { apply(i, install: true) }
                        }
                    }
                }
                .id(refresh)
                if let m = integrationMessage { Text(m).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Section("提醒") {
                LabeledContent("卡住阈值") { Stepper("\(Int(settings.stuckMinutes)) 分钟", value: $settings.stuckMinutes, in: 1...60) }
                LabeledContent("审批等待") { Stepper("\(Int(settings.approvalTimeout)) 秒", value: $settings.approvalTimeout, in: 5...25) }
                Toggle("Wave 在前台时不发系统通知", isOn: $settings.suppressWhenWaveFrontmost)
            }
            Section("悬浮窗") {
                LabeledContent("已完成会话显示") { Stepper("\(Int(settings.idleVisibleMinutes)) 分钟", value: $settings.idleVisibleMinutes, in: 0...240, step: 5) }
                Slider(value: $settings.panelOpacity, in: 0.4...1) { Text("透明度") }
                    .onChange(of: settings.panelOpacity) { panel.applyOpacity() }
                Text("⌥⌘K 显示 / 隐藏").font(.caption).foregroundStyle(.secondary)
            }
            Section("Wave Terminal") {
                Toggle("跳转时切换到对应标签页", isOn: $settings.waveTabSwitching)
                Text("需要在 系统设置 › 隐私与安全性 › 辅助功能 里允许 YaaKanban。第一次跳转时会弹出请求。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { integrationMessage = "登录项设置失败：\(error.localizedDescription)" }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
    }

    private func statusLabel(_ s: IntegrationStatus) -> String {
        switch s { case .installed: "已安装"; case .outdated: "需更新"; case .notInstalled: "未安装"; case .notDetected: "未检测到" }
    }

    static var yaak: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/yaak").path }

    private func apply(_ i: any Integration, install: Bool) {
        do {
            try Installer.apply(try i.plan(install: install, home: Paths.home(), yaak: Self.yaak))
            integrationMessage = "\(i.agent.displayName) 已\(install ? "安装" : "卸载")。" + (install ? (i.postInstallNote ?? "") : "")
        } catch {
            integrationMessage = "\(i.agent.displayName)：\(error)"
        }
        refresh += 1
    }
}
