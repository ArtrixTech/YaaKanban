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
        // A narrow panel drops the name rather than squeezing the buttons out of the window.
        ViewThatFits(in: .horizontal) {
            row(named: true)
            row(named: false)
        }
        // One line, the same height as the folded header, so cards keep their place.
        .frame(height: BoardHeaderHeight.value)
    }

    private func row(named: Bool) -> some View {
        HStack(spacing: 6) {
            BrandMark(size: 20)
            if named { Text("YaaKanban").font(.system(size: 13, weight: .bold)).lineLimit(1).fixedSize() }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                let counts = self.counts
                ForEach(counts, id: \.0.rank) { st, n in CountChip(count: n, status: st).transition(.scale.combined(with: .opacity)) }
            }
            .fixedSize()
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

/// Menu-bar popover: a few controls. The sessions live in the floating panel and the main window.
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    let panel: FloatingPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                BrandMark(size: 18)
                Text("YaaKanban").font(.system(size: 12.5, weight: .bold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 4)
            Text(summary).font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 4)
            if let err = model.serverError {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal, 8)
            }
            Divider().padding(.vertical, 3)
            MenuRow(symbol: "rectangle.on.rectangle", title: model.settings.showPanel ? "隐藏悬浮窗" : "显示悬浮窗",
                    shortcut: "⌥⌘K") { panel.toggle() }
            MenuRow(symbol: "macwindow", title: "主界面") { done { AppWindows.open(.main) } }
            MenuRow(symbol: "gearshape", title: "设置…") { done { AppWindows.open(.settings) } }
            Divider().padding(.vertical, 3)
            MenuRow(symbol: "power", title: "退出 YaaKanban") { NSApp.terminate(nil) }
        }
        .padding(6)
        .frame(width: 230)
    }

    private var summary: String {
        let parts = [("运行中", model.runningCount), ("待验收", model.reviewCount),
                     ("需要你", model.attentionCount)].filter { $0.1 > 0 }.map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? "没有进行中的会话" : parts.joined(separator: " · ")
    }

    /// Closes the popover, then acts (a window opened behind it would be hidden by it).
    private func done(_ action: @escaping () -> Void) {
        NSApp.keyWindow?.close()
        DispatchQueue.main.async(execute: action)
    }
}

/// A menu-like row: icon, title, optional shortcut; highlighted on hover.
struct MenuRow: View {
    let symbol: String
    let title: String
    var shortcut: String?
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12)).frame(width: 16)
                Text(title).font(.system(size: 12.5))
                Spacer(minLength: 8)
                if let shortcut { Text(shortcut).font(.system(size: 11)).foregroundStyle(hover ? .white.opacity(0.8) : .secondary) }
            }
            .foregroundStyle(hover ? .white : .primary)
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(hover ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
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

/// Floating panel content, at its natural size; the borderless window resizes to fit it. Snapped to
/// a side it is a `SidebarRail` instead, narrow unless hovered or unfolded.
struct FloatingPanelView: View {
    @Environment(AppModel.self) private var model
    var onHide: () -> Void = {}
    /// Natural content size, reported on every layout change so the window can follow it.
    var onSize: (CGSize) -> Void = { _ in }
    /// Room the window has on its screen; the list gives way so the panel never runs off it.
    var room: PanelRoom?
    @State private var expanded: String?
    @State private var listHeight: CGFloat = 0
    /// Everything but the list (header, grip, padding), so the list knows what is left for it.
    @State private var chrome: CGFloat = 0
    /// List height when a resize drag began.
    @State private var dragStart: CGFloat?
    @State private var widthStart: CGFloat?

    static let minList: CGFloat = 120
    static let maxList: CGFloat = 1400
    static let minWidth: CGFloat = 300
    static let maxWidth: CGFloat = 720

    var body: some View {
        panel
            // Pinned to the top and to the docked side however big the window is at the moment:
            // the content is laid out at the width it is heading for, and the window edge slides
            // over it, so it is in place and clickable from the first frame.
            // minHeight 0: content taller than the window (mid-resize) overflows at the bottom
            // instead of growing the frame, which the window would center, pushing the header up.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: anchor)
            .clipped()
    }

    /// Docked to a side and neither hovered nor unfolded.
    private var folded: Bool {
        room?.snapshotFolded == true || (room?.dock != nil && !model.settings.sidebarExpanded && room?.peek != true)
    }

    private var anchor: Alignment {
        switch room?.dock {
        case .left: .topLeading
        case .right: .topTrailing
        case nil: .top
        }
    }

    private var panel: some View {
        @Bindable var settings = model.settings
        let folded = self.folded
        return VStack(alignment: .leading, spacing: 10) {
            if folded, let edge = room?.dock {
                RailHeader(edge: edge) { settings.sidebarExpanded = true }
            } else {
                header
            }
            list
        }
        // Folded, the sides match the gap between cards.
        .padding(.horizontal, folded ? Rail.inset : 10).padding(.top, 10)
        .padding(.bottom, settings.panelCollapsed || model.activeSessions.isEmpty ? 10 : 0)
        .environment(\.railExtra, folded ? settings.panelWidth - Rail.width : nil)
        .frame(width: folded ? Rail.width : settings.panelWidth, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: widthGripSide) { if !folded { widthGrip } }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            chrome = size.height - (listShown ? shownList : 0)
            onSize(size)
        }
    }

    /// The side edge that sets the width: the one away from the docked side.
    private var widthGripSide: Alignment { room?.dock == .right ? .leading : .trailing }

    private var widthGrip: some View {
        @Bindable var settings = model.settings
        let sign: CGFloat = room?.dock == .right ? -1 : 1
        return EdgeGrip(axis: .horizontal) { delta in
            room?.resizing = delta != nil
            guard let delta else { widthStart = nil; return }
            let start = widthStart ?? settings.panelWidth
            widthStart = start
            settings.panelWidth = min(Self.maxWidth, max(Self.minWidth, (start + sign * delta).rounded()))
        }
        .frame(width: 6)
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        @Bindable var settings = model.settings
        return BoardHeader {
                if let edge = room?.dock {
                    if room?.peek == true && !settings.sidebarExpanded {
                        IconButton(symbol: "pin", help: "固定展开") {
                            settings.sidebarExpanded = true
                            room?.peek = false
                        }
                    } else {
                        IconButton(symbol: edge == .right ? "chevron.right.2" : "chevron.left.2", help: "收进侧边栏") {
                            settings.sidebarExpanded = false
                        }
                    }
                }
                IconButton(symbol: "macwindow", help: "主界面") { AppWindows.open(.main) }
                IconButton(symbol: "gearshape", help: "设置") { AppWindows.open(.settings) }
                IconButton(symbol: settings.panelCollapsed ? "chevron.down" : "chevron.up",
                           help: settings.panelCollapsed ? "展开" : "收起") {
                    withAnimation(.snappy) { settings.panelCollapsed.toggle() }
                }
                IconButton(symbol: "xmark", help: "隐藏（⌥⌘K）", action: onHide)
            }
    }

    @ViewBuilder private var list: some View {
        @Bindable var settings = model.settings
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
    /// Screen edge the panel is snapped to, if a side.
    var dock: DockEdge?
    /// The folded rail is shown unfolded while the pointer is over it.
    var peek = false
    /// The width grip is being dragged: resize at once instead of sliding.
    var resizing = false
    /// Snapshots render the rail folded whatever the user pinned.
    var snapshotFolded = false

    init(dock: DockEdge? = nil, peek: Bool = false) { self.dock = dock; self.peek = peek }
}

/// Bottom handle that sets the list height. AppKit-backed so the drag does not move the
/// (movable-by-background) window, and so it shows the resize cursor.
struct ResizeGrip: View {
    @Environment(\.railExtra) private var railExtra
    /// Vertical drag distance (down is positive); nil when the drag ends.
    var onDrag: (CGFloat?) -> Void
    @State private var hover = false

    var body: some View {
        Capsule().fill(.primary.opacity(hover ? 0.35 : 0.15)).frame(width: 36, height: 4)
            .frame(maxWidth: .infinity).frame(height: railExtra == nil ? 14 : 10)
            .overlay(GripTracker(axis: .vertical, onDrag: onDrag))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
            .help("拖动调整高度")
    }
}

/// Invisible strip along the panel's side edge that sets its width.
struct EdgeGrip: View {
    let axis: Axis
    /// Drag distance (right is positive); nil when the drag ends.
    var onDrag: (CGFloat?) -> Void

    var body: some View {
        GripTracker(axis: axis, onDrag: onDrag).help("拖动调整宽度")
    }
}

private struct GripTracker: NSViewRepresentable {
    let axis: Axis
    var onDrag: (CGFloat?) -> Void

    func makeNSView(context: Context) -> TrackerView { TrackerView() }
    func updateNSView(_ v: TrackerView, context: Context) { v.axis = axis; v.onDrag = onDrag }

    final class TrackerView: NSView {
        var axis = Axis.vertical
        var onDrag: (CGFloat?) -> Void = { _ in }
        private var start: NSPoint?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: axis == .vertical ? .resizeUpDown : .resizeLeftRight)
        }
        override func mouseDown(with e: NSEvent) { start = NSEvent.mouseLocation }
        override func mouseDragged(with e: NSEvent) {
            guard let start else { return }
            let p = NSEvent.mouseLocation
            // Down is positive for the vertical grip, right for the horizontal one.
            onDrag(axis == .vertical ? start.y - p.y : p.x - start.x)
        }
        override func mouseUp(with e: NSEvent) { start = nil; onDrag(nil) }
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

    static let size = NSSize(width: 500, height: 640)

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section { AboutHeader() }
            Section {
                ForEach(Integrations.all, id: \.agent) { i in
                    let status = i.status(home: Paths.home(), yaak: Self.yaak)
                    LabeledContent {
                        HStack(spacing: 8) {
                            StatusBadge(status: status)
                            if status == .outdated {
                                Button("更新") { apply(i, install: true) }.buttonStyle(.borderedProminent)
                            }
                            if status == .installed || status == .outdated {
                                Button("卸载") { apply(i, install: false) }
                            } else if status == .notInstalled {
                                Button("安装") { apply(i, install: true) }.buttonStyle(.borderedProminent)
                            }
                        }
                        .controlSize(.small)
                    } label: {
                        HStack(spacing: 8) {
                            AgentLogo(agent: i.agent, size: 16)
                                .frame(width: 22, height: 22)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                            Text(i.agent.displayName)
                        }
                    }
                }
                .id(refresh)
            } header: {
                Text("Agent 接入")
            } footer: {
                Text(integrationMessage ?? "安装后，agent 通过 hook 把会话状态和审批请求发给 YaaKanban。")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("提醒") {
                LabeledContent {
                    Stepper("\(Int(settings.stuckMinutes)) 分钟", value: $settings.stuckMinutes, in: 1...60)
                } label: { SettingLabel("卡住阈值", symbol: "hourglass", tint: .orange) }
                LabeledContent {
                    Stepper("\(Int(settings.approvalTimeout)) 秒", value: $settings.approvalTimeout, in: 5...25)
                } label: { SettingLabel("审批等待", symbol: "hand.raised.fill", tint: .red) }
                Toggle(isOn: $settings.suppressWhenWaveFrontmost) {
                    SettingLabel("Wave 在前台时不发系统通知", symbol: "bell.slash.fill", tint: .gray)
                }
            }
            Section("悬浮窗") {
                LabeledContent {
                    Stepper(Self.duration(settings.idleVisibleMinutes), value: $settings.idleVisibleMinutes, in: 0...1440, step: 30)
                } label: { SettingLabel("已完成会话显示", symbol: "checkmark.circle.fill", tint: .green) }
                LabeledContent {
                    HStack(spacing: 8) {
                        Slider(value: $settings.panelOpacity, in: 0.4...1).frame(width: 150)
                            .onChange(of: settings.panelOpacity) { panel.applyOpacity() }
                        Text("\(Int(settings.panelOpacity * 100))%").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                } label: { SettingLabel("透明度", symbol: "circle.lefthalf.filled", tint: .indigo) }
                LabeledContent {
                    Text("⌥⌘K").font(.system(size: 12, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
                } label: { SettingLabel("显示 / 隐藏", symbol: "command", tint: .blue) }
            }
            Section {
                Toggle(isOn: $settings.waveTabSwitching) {
                    SettingLabel("跳转时切换到对应标签页", symbol: "rectangle.stack.fill", tint: .teal)
                }
            } header: {
                Text("Wave Terminal")
            } footer: {
                Text("需要在 系统设置 › 隐私与安全性 › 辅助功能 里允许 YaaKanban。第一次跳转时会弹出请求。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("通用") {
                Toggle(isOn: $launchAtLogin) { SettingLabel("登录时启动", symbol: "power", tint: .gray) }
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { integrationMessage = "登录项设置失败：\(error.localizedDescription)" }
                    }
            }
            Section("关于") {
                LabeledContent("版本", value: AboutHeader.version)
                LabeledContent("许可证", value: "GPL-3.0")
                LabeledContent("源代码") { Link("github.com/ArtrixTech/YaaKanban", destination: AboutHeader.repo) }
                LabeledContent("问题反馈") { Link("提交 Issue", destination: AboutHeader.repo.appendingPathComponent("issues")) }
                Text("© 2026 Artrix · 以 GPL-3.0 开源发布").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m < 60 { return "\(m) 分钟" }
        return m % 60 == 0 ? "\(m / 60) 小时" : "\(m / 60) 小时 \(m % 60) 分"
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

/// Top of the settings window: logo, name, version, one-line pitch.
struct AboutHeader: View {
    static let repo = URL(string: "https://github.com/ArtrixTech/YaaKanban")!
    static var version: String {
        let info = Bundle.main.infoDictionary
        guard let v = info?["CFBundleShortVersionString"] as? String else { return "开发版" }
        return "\(v) (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(spacing: 6) {
            BrandMark(size: 64).shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            Text("YaaKanban").font(.system(size: 20, weight: .bold))
            Text("版本 \(Self.version)").font(.caption).foregroundStyle(.secondary)
            Text("盯着你的 coding agent：完成、卡住、需要你时第一时间知道。")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Settings row label in the System Settings style: white symbol on a tinted rounded square.
struct SettingLabel: View {
    let title: String
    let symbol: String
    let tint: Color
    init(_ title: String, symbol: String, tint: Color) { self.title = title; self.symbol = symbol; self.tint = tint }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.gradient))
            Text(title)
        }
    }
}

/// Integration status as a small colored capsule.
struct StatusBadge: View {
    let status: IntegrationStatus

    var body: some View {
        let (text, color): (String, Color) = switch status {
        case .installed: ("已安装", .green)
        case .outdated: ("需更新", .orange)
        case .notInstalled: ("未安装", .secondary)
        case .notDetected: ("未检测到", .secondary)
        }
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}
