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
    static let image = Bundle.main.url(forResource: "logo", withExtension: "svg").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if let img = Self.image {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: size * 0.6)).frame(width: size, height: size)
        }
    }
}

/// The logo's mark without its tile, drawn in the text color so it reads on either appearance:
/// three falling columns and the green dot under the last (`logo.svg`, its 38 × 36 content box).
struct BrandGlyph: View {
    var size: CGFloat

    var body: some View {
        let u = size / 38
        HStack(alignment: .top, spacing: 4 * u) {
            column(36, 0.95, u)
            column(24, 0.75, u)
            ZStack(alignment: .top) {
                column(14, 0.55, u)
                Circle().fill(LinearGradient(colors: [Color(red: 0.06, green: 0.73, blue: 0.51), Color(red: 0.29, green: 0.87, blue: 0.5)],
                                             startPoint: .top, endPoint: .bottom))
                    .frame(width: 10 * u, height: 10 * u)
                    .offset(y: 26 * u)
            }
        }
        .frame(width: 38 * u, height: 36 * u, alignment: .topLeading)
        .accessibilityLabel("YaaKanban")
    }

    private func column(_ h: CGFloat, _ opacity: Double, _ u: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4 * u, style: .continuous).fill(Color.primary.opacity(opacity))
            .frame(width: 10 * u, height: h * u)
    }
}

/// Menu-bar popover: a few controls. The sessions live in the floating panel and the main window.
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    let panel: FloatingPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuHeader(summary: summary) { done { AppWindows.open(.main) } }
            if let err = model.serverError {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal, 8)
            }
            Divider().padding(.vertical, 3)
            MenuRow(symbol: "rectangle.on.rectangle", title: model.settings.showPanel ? "隐藏悬浮窗" : "显示悬浮窗",
                    shortcut: "⌥⌘K") { panel.toggle() }
            MenuRow(symbol: "macwindow", title: "主界面") { done { AppWindows.open(.main) } }
            MenuRow(symbol: "gearshape", title: "设置…") { done { AppWindows.open(.settings) } }
            MenuRow(symbol: "bubble.left", title: "反馈…") { done { FeedbackPrompt.present(model) } }
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

/// Top of the menu popover: mark, name, counts and today's figures, all one button to the main window.
struct MenuHeader: View {
    let summary: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    BrandMark(size: 18)
                    Text("YaaKanban").font(.system(size: 12.5, weight: .bold))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text(summary).font(.system(size: 11)).foregroundStyle(.secondary)
                TodayFigures()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hover ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("打开主界面")
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
    /// Where the list's bottom is in the scroll view, to fade the bottom edge while more is below.
    @State private var listBottom: CGFloat = 0

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
        let slim = folded && (settings.slimRail || room?.snapshotSlim == true)
        let railWidth = Rail.width(slim: slim), inset = Rail.inset(slim: slim)
        return VStack(alignment: .leading, spacing: 10) {
            if folded, let edge = room?.dock {
                RailHeader(edge: edge) { settings.sidebarExpanded = true }
            } else {
                header
            }
            // Folded too (narrower), so the cards keep their place when the rail unfolds.
            if settings.showRecentStats { RecentFigures(folded: folded, slim: slim) }
            list
        }
        // Folded, the sides match the gap between cards.
        .padding(.horizontal, folded ? inset : 10).padding(.top, 10)
        .padding(.bottom, folded ? inset : settings.panelCollapsed || model.activeSessions.isEmpty ? 10 : 0)
        // Cards are measured as wide as in the normal rail plus its extra, so either rail keeps their height.
        .environment(\.railExtra, folded ? settings.panelWidth - 2 * Rail.inset - (railWidth - 2 * inset) : nil)
        .environment(\.railSlim, slim)
        .frame(width: folded ? railWidth : settings.panelWidth, alignment: .top)
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
                    room?.holdTop()
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
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { grow(to: $0) }
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).maxY } action: { listBottom = $0 }
                    }
                    .scrollIndicators(.never)
                    .frame(height: shownList)
                    // More below the bottom edge: it fades out instead of being cut.
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .black.opacity(moreBelow ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 28)
                        }
                        .animation(.easeOut(duration: 0.15), value: moreBelow)
                    }
                    .transition(.opacity)
                    // Folded, the bottom is an edge like the sides; the height is set unfolded.
                    if !folded {
                        ResizeGrip { delta in
                            room?.holdTop()
                            guard let delta else {
                                // Let go at the minimum: back to following the content.
                                dragStart = nil
                                if (settings.panelListHeight ?? .infinity) <= Self.minList { settings.panelListHeight = nil }
                                return
                            }
                            let start = dragStart ?? shownList
                            dragStart = start
                            settings.panelListHeight = min(Self.maxList, max(Self.minList, start + delta))
                        }
                    }
                }
            }
    }

    private var moreBelow: Bool { listBottom > shownList + 1 }

    /// The list's natural height changed. Without a height set by hand the panel follows it both
    /// ways; with one, the panel keeps it and the list scrolls.
    private func grow(to h: CGFloat) { listHeight = h }

    private var listShown: Bool { !model.settings.panelCollapsed && !model.activeSessions.isEmpty }

    private var shownList: CGFloat {
        let fits = room.map { max(Self.minList, $0.height - chrome) } ?? .infinity
        return min(model.settings.panelListHeight ?? min(listHeight, Self.maxList), fits)
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
    /// Snapshots render the rail folded whatever the user pinned, and slim if asked.
    var snapshotFolded = false
    var snapshotSlim = false
    /// Until when a height change keeps the top edge still: the user is resizing or folding the
    /// list by hand. Otherwise the panel grows and shrinks about its middle.
    @ObservationIgnored var topHeldUntil: CFTimeInterval = 0

    func holdTop() { topHeldUntil = CACurrentMediaTime() + 0.6 }

    init(dock: DockEdge? = nil, peek: Bool = false) { self.dock = dock; self.peek = peek }
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
                Label("概览", systemImage: "chart.xyaxis.line").tag(AppModel.overview)
                section("活跃", model.board)
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
                DashboardView()
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
                        StatusGlyph(status: model.display(s), size: 22)
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
                        Button("重命名…") { model.rename(s.id) }
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
            Section {
                LabeledContent {
                    Picker("", selection: $settings.idleVisibleMinutes) {
                        ForEach(Preferences.retentionChoices, id: \.self) { Text(Self.duration($0)).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .onChange(of: settings.idleVisibleMinutes) {
                        settings.staleAfterMinutes = min(settings.staleAfterMinutes, settings.idleVisibleMinutes - 1)
                    }
                } label: { SettingLabel("已验收会话保留", symbol: "checkmark.circle.fill", tint: .green) }
                Toggle(isOn: $settings.flashEnabled) {
                    SettingLabel("需要输入时闪烁", symbol: "light.beacon.max.fill", tint: .red)
                }
                if settings.flashEnabled {
                    LabeledContent {
                        Stepper("\(Int(settings.flashAfterSeconds)) 秒未点击", value: $settings.flashAfterSeconds, in: 5...600, step: 5)
                    } label: { Text("开始闪烁").padding(.leading, 30) }
                }
                Toggle(isOn: $settings.reviewFlashEnabled) {
                    SettingLabel("待验收久未查看时闪烁", symbol: "light.beacon.max.fill", tint: .green)
                }
                if settings.reviewFlashEnabled {
                    LabeledContent {
                        Stepper("在电脑前 \(Int(settings.reviewFlashMinutes)) 分钟未查看", value: $settings.reviewFlashMinutes, in: 1...60)
                    } label: { Text("开始闪烁").padding(.leading, 30) }
                }
                Toggle(isOn: $settings.staleTintEnabled) {
                    SettingLabel("看过未跟进的会话变蓝", symbol: "drop.fill", tint: .blue)
                }
                if settings.staleTintEnabled {
                    LabeledContent {
                        Stepper("结束 \(Self.duration(settings.staleAfterMinutes)) 后", value: $settings.staleAfterMinutes,
                                in: 1...max(1, settings.idleVisibleMinutes - 1), step: settings.staleAfterMinutes < 60 ? 5 : 15)
                    } label: { Text("开始变蓝").padding(.leading, 30) }
                    LabeledContent("最蓝") {
                        Text("结束 \(Self.duration(settings.stalePeakMinutes)) 后").foregroundStyle(.secondary)
                    }
                    .padding(.leading, 30)
                }
            } header: {
                Text("会话提醒")
            } footer: {
                Text("待验收闪烁只计你在电脑前的时间（2 分钟无键鼠操作或睡眠算离开）。已验收、之后没再运行的会话：从「开始变蓝」起逐渐变蓝，在它与「已验收会话保留」的正中最蓝，到保留时长结束时褪回灰色并离开悬浮窗。时间从会话结束或你最后一次点开它算起，再点开一次就重新计时。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("悬浮窗") {
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
                Toggle(isOn: $settings.showRecentStats) {
                    SettingLabel("顶部显示杠杆和今日工时", symbol: "chart.bar.fill", tint: .orange)
                }
                if settings.showRecentStats {
                    Picker(selection: $settings.recentMinutes) {
                        ForEach(Preferences.recentChoices, id: \.self) { Text(Self.duration($0)).tag($0) }
                    } label: { Text("杠杆统计最近").padding(.leading, 30) }
                }
                Toggle(isOn: $settings.slimRail) {
                    VStack(alignment: .leading, spacing: 2) {
                        SettingLabel("超窄侧边栏（实验性）", symbol: "sidebar.right", tint: .teal)
                        Text("吸附到屏幕左右边并收起后，变成一条细条，每个会话只显示状态、agent 和时间，运行中的有流光，高度不变。鼠标移上去（推到屏幕边也行）展开。")
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 30)
                    }
                }
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
            Section {
                Toggle(isOn: $settings.piAutoTitle) {
                    SettingLabel("自动生成会话标题", symbol: "character.cursor.ibeam", tint: .purple)
                }
            } header: {
                Text("pi 兼容性")
            } footer: {
                Text("pi 只有 /name 才会给会话起名。开启后，未命名的会话会在第一条消息时用当前模型生成一个短标题（每个会话多一次很小的模型调用），并写入 pi 的会话名，/resume 里也能看到。需要安装或更新 pi 接入后生效。")
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
            Section {
                Toggle(isOn: Binding(get: { model.telemetry.isOn }, set: { model.telemetry.set(enabled: $0) })) {
                    SettingLabel("发送匿名使用统计", symbol: "chart.line.uptrend.xyaxis", tint: .blue)
                }
                .disabled(!model.telemetry.available)
                if model.telemetry.isOn {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Button("查看") { FeedbackPrompt.show(title: "今天的统计（明天发送）", text: model.telemetry.preview()) }
                            Button("重置") { model.telemetry.resetId() }
                        }
                        .controlSize(.small)
                    } label: {
                        Text("匿名 ID \(model.telemetry.installId?.prefix(8) ?? "")…").padding(.leading, 30)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
                    Button("反馈…") { FeedbackPrompt.present(model) }.controlSize(.small)
                } label: { SettingLabel("问题与建议", symbol: "bubble.left.fill", tint: .green) }
            } header: {
                Text("隐私与反馈")
            } footer: {
                Text(model.telemetry.doNotTrack ? "已设置 DO_NOT_TRACK，不会发送统计。"
                     : model.telemetry.endpoint == nil ? "这个版本没有配置统计服务器，不会发送任何数据。"
                     : "默认关闭。开启后每天发送一份匿名统计：版本、系统、接入状态、功能使用次数和粗略区间的会话数；不含 prompt、代码、路径、项目或会话名。命令行：yaak telemetry status|on|off。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("关于") {
                LabeledContent("版本", value: AboutHeader.version)
                LabeledContent("许可证", value: "GPL-3.0")
                LabeledContent("源代码") { Link("github.com/ArtrixTech/YaaKanban", destination: AboutHeader.repo) }
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
            model.telemetry.count(install ? .integrationInstall : .integrationUninstall)
            integrationMessage = "\(i.agent.displayName) 已\(install ? "安装" : "卸载")。" + (install ? (i.postInstallNote ?? "") : "")
        } catch {
            model.telemetry.count(.integrationFail)
            integrationMessage = "\(i.agent.displayName)：\(error)"
        }
        refresh += 1
    }
}

/// Top of the settings window: logo, name, version, one-line pitch.
struct AboutHeader: View {
    static let repo = Feedback.repo
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
