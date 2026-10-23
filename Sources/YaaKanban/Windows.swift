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
            if named { Text(verbatim: "YaaKanban").font(.system(size: 13, weight: .bold)).lineLimit(1).fixedSize() }
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
        .accessibilityLabel(Text(verbatim: "YaaKanban"))
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
            if !model.integrationIssues.isEmpty {
                let names = model.integrationIssues.keys.map(\.displayName).sorted().formatted(.list(type: .and))
                MenuRow(symbol: "exclamationmark.triangle.fill", title: String(localized: "\(names) hooks need approval")) { done { AppWindows.open(.settings) } }
            }
            Divider().padding(.vertical, 3)
            MenuRow(symbol: "rectangle.on.rectangle", title: model.settings.showPanel ? String(localized: "Hide floating panel") : String(localized: "Show floating panel"),
                    shortcut: "⌥⌘K") { panel.toggle() }
            MenuRow(symbol: "macwindow", title: String(localized: "Main window")) { done { AppWindows.open(.main) } }
            MenuRow(symbol: "gearshape", title: String(localized: "Settings…")) { done { AppWindows.open(.settings) } }
            MenuRow(symbol: "bubble.left", title: String(localized: "Feedback…")) { done { FeedbackPrompt.present(model) } }
            Divider().padding(.vertical, 3)
            MenuRow(symbol: "power", title: String(localized: "Quit YaaKanban")) { NSApp.terminate(nil) }
        }
        .padding(6)
        .frame(width: 230)
    }

    private var summary: String {
        let parts = [(String(localized: "Running"), model.runningCount), (String(localized: "To review"), model.reviewCount),
                     (String(localized: "Needs you"), model.attentionCount)].filter { $0.1 > 0 }.map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? String(localized: "No active sessions") : parts.joined(separator: " · ")
    }

    /// Closes the popover, then acts (a window opened behind it would be hidden by it). Not a GCD
    /// block: a modal alert run inside one stalls every main-actor Task until it is closed.
    private func done(_ action: @escaping () -> Void) {
        NSApp.keyWindow?.close()
        nonisolated(unsafe) let action = action
        RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { action() } }
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
                    Text(verbatim: "YaaKanban").font(.system(size: 12.5, weight: .bold))
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
        .help("Open main window")
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
            Text("No active tasks").font(.system(size: 12)).foregroundStyle(.secondary)
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
                        IconButton(symbol: "pin", help: String(localized: "Pin open")) {
                            settings.sidebarExpanded = true
                            room?.peek = false
                        }
                    } else {
                        IconButton(symbol: edge == .right ? "chevron.right.2" : "chevron.left.2", help: String(localized: "Fold into sidebar")) {
                            settings.sidebarExpanded = false
                        }
                    }
                }
                IconButton(symbol: "macwindow", help: String(localized: "Main window")) { AppWindows.open(.main) }
                IconButton(symbol: "gearshape", help: String(localized: "Settings")) { AppWindows.open(.settings) }
                IconButton(symbol: settings.panelCollapsed ? "chevron.down" : "chevron.up",
                           help: settings.panelCollapsed ? String(localized: "Expand") : String(localized: "Collapse")) {
                    room?.holdTop()
                    withAnimation(.snappy) { settings.panelCollapsed.toggle() }
                }
                IconButton(symbol: "xmark", help: String(localized: "Hide (⌥⌘K)"), action: onHide)
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
            .help("Drag to resize height")
    }
}

/// Invisible strip along the panel's side edge that sets its width.
struct EdgeGrip: View {
    let axis: Axis
    /// Drag distance (right is positive); nil when the drag ends.
    var onDrag: (CGFloat?) -> Void

    var body: some View {
        GripTracker(axis: axis, onDrag: onDrag).help("Drag to resize width")
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
                Label("Overview", systemImage: "chart.xyaxis.line").tag(AppModel.overview)
                section(String(localized: "Active"), model.board)
                section(String(localized: "History"), model.allSessions.filter { s in !model.activeSessions.contains { $0.id == s.id } })
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Project / prompt")
            .toolbar {
                Picker("Agent", selection: $filter) {
                    Text("All").tag(AgentKind?.none)
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
                        if s.display == .review { Button("Mark as reviewed") { model.markRead(s.id) } }
                        if s.dismissedAt != nil { Button("Restore to floating panel") { model.undismiss(s.id) } }
                        Button("Rename…") { model.rename(s.id) }
                        Button("Delete from history", role: .destructive) { model.remove(s.id) }
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
    @State private var language = AppLanguage.override

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
                            if status == .needsAuthorization {
                                Button("Recheck") { recheck() }
                            }
                            if status == .outdated {
                                Button("Update") { apply(i, install: true) }.buttonStyle(.borderedProminent)
                            }
                            if status == .installed || status == .outdated || status == .needsAuthorization {
                                Button("Uninstall") { apply(i, install: false) }
                            } else if status == .notInstalled {
                                Button("Install") { apply(i, install: true) }.buttonStyle(.borderedProminent)
                            }
                        }
                        .controlSize(.small)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                AgentLogo(agent: i.agent, size: 16)
                                    .frame(width: 22, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                                Text(i.agent.displayName)
                            }
                            if status == .needsAuthorization {
                                AuthorizationSteps(steps: i.pendingSteps(home: Paths.home()))
                            } else if status != .notDetected, let note = i.postInstallNote {
                                Text(note).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 30)
                            }
                        }
                    }
                }
                .id(refresh)
            } header: {
                Text("Agent integrations")
            } footer: {
                Text(integrationMessage ?? String(localized: "Once installed, the agent sends session status and approval requests to YaaKanban through hooks."))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Alerts") {
                LabeledContent {
                    Stepper("\(Int(settings.stuckMinutes)) min", value: $settings.stuckMinutes, in: 1...60)
                } label: { SettingLabel(String(localized: "Stuck threshold"), symbol: "hourglass", tint: .orange) }
                LabeledContent {
                    Stepper("\(Int(settings.approvalTimeout)) s", value: $settings.approvalTimeout, in: 5...25)
                } label: { SettingLabel(String(localized: "Approval wait"), symbol: "hand.raised.fill", tint: .red) }
                Toggle(isOn: $settings.suppressWhenWaveFrontmost) {
                    SettingLabel(String(localized: "No system notifications while Wave is in front"), symbol: "bell.slash.fill", tint: .gray)
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
                } label: { SettingLabel(String(localized: "Keep reviewed sessions"), symbol: "checkmark.circle.fill", tint: .green) }
                Toggle(isOn: $settings.flashEnabled) {
                    SettingLabel(String(localized: "Flash when input is needed"), symbol: "light.beacon.max.fill", tint: .red)
                }
                if settings.flashEnabled {
                    LabeledContent {
                        Stepper("After \(Int(settings.flashAfterSeconds)) s without a click", value: $settings.flashAfterSeconds, in: 5...600, step: 5)
                    } label: { Text("Start flashing").padding(.leading, 30) }
                }
                Toggle(isOn: $settings.reviewFlashEnabled) {
                    SettingLabel(String(localized: "Flash when a review waits too long"), symbol: "light.beacon.max.fill", tint: .green)
                }
                if settings.reviewFlashEnabled {
                    LabeledContent {
                        Stepper("After \(Int(settings.reviewFlashMinutes)) min at the computer unviewed", value: $settings.reviewFlashMinutes, in: 1...60)
                    } label: { Text("Start flashing").padding(.leading, 30) }
                }
                Toggle(isOn: $settings.staleTintEnabled) {
                    SettingLabel(String(localized: "Tint seen but idle sessions blue"), symbol: "drop.fill", tint: .blue)
                }
                if settings.staleTintEnabled {
                    LabeledContent {
                        Stepper("\(Self.duration(settings.staleAfterMinutes)) after it ends", value: $settings.staleAfterMinutes,
                                in: 1...max(1, settings.idleVisibleMinutes - 1), step: settings.staleAfterMinutes < 60 ? 5 : 15)
                    } label: { Text("Start tinting").padding(.leading, 30) }
                    LabeledContent("Bluest") {
                        Text("\(Self.duration(settings.stalePeakMinutes)) after it ends").foregroundStyle(.secondary)
                    }
                    .padding(.leading, 30)
                }
            } header: {
                Text("Session reminders")
            } footer: {
                Text("Review flashing counts only time you're at the computer (2 minutes without keyboard or mouse, or sleep, counts as away). A reviewed session that hasn't run since turns gradually blue from \u{201C}Start tinting\u{201D}, is bluest halfway between that and \u{201C}Keep reviewed sessions\u{201D}, and fades back to gray and leaves the floating panel when the retention ends. Time counts from when the session ended or you last opened it; opening it again restarts the clock.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Floating panel") {
                LabeledContent {
                    HStack(spacing: 8) {
                        Slider(value: $settings.panelOpacity, in: 0.4...1).frame(width: 150)
                            .onChange(of: settings.panelOpacity) { panel.applyOpacity() }
                        Text("\(Int(settings.panelOpacity * 100))%").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                } label: { SettingLabel(String(localized: "Opacity"), symbol: "circle.lefthalf.filled", tint: .indigo) }
                LabeledContent {
                    Text(verbatim: "⌥⌘K").font(.system(size: 12, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
                } label: { SettingLabel(String(localized: "Show / hide"), symbol: "command", tint: .blue) }
                Toggle(isOn: $settings.showRecentStats) {
                    SettingLabel(String(localized: "Show leverage and today's work time on top"), symbol: "chart.bar.fill", tint: .orange)
                }
                if settings.showRecentStats {
                    Picker(selection: $settings.recentMinutes) {
                        ForEach(Preferences.recentChoices, id: \.self) { Text(Self.duration($0)).tag($0) }
                    } label: { Text("Leverage over the last").padding(.leading, 30) }
                }
                Toggle(isOn: $settings.slimRail) {
                    VStack(alignment: .leading, spacing: 2) {
                        SettingLabel(String(localized: "Slim sidebar (experimental)"), symbol: "sidebar.right", tint: .teal)
                        Text("When snapped to the left or right edge and folded, the panel becomes a thin strip: each session shows only its status, agent and time, running ones shimmer, and the height stays the same. Hover it (or push the pointer to the screen edge) to expand.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 30)
                    }
                }
            }
            Section {
                Toggle(isOn: $settings.claudeBackgroundAgents) {
                    SettingLabel(String(localized: "Wait for background agents (beta)"), symbol: "person.2.wave.2.fill", tint: .orange)
                }
                .onChange(of: settings.claudeBackgroundAgents) { _, on in if !on { model.forgetBackgroundTasks() } }
            } header: {
                Text("Claude Code compatibility")
            } footer: {
                Text("When the main agent has replied but background agents haven't returned, the session stays running; it moves to review only after the last background agent returns and the main agent has handled its result. When off, every reply from the main agent counts as ready for review.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(isOn: $settings.waveTabSwitching) {
                    SettingLabel(String(localized: "Switch to the matching tab when jumping"), symbol: "rectangle.stack.fill", tint: .teal)
                }
            } header: {
                Text(verbatim: "Wave Terminal")
            } footer: {
                Text("Allow YaaKanban in System Settings › Privacy & Security › Accessibility. You'll be asked on the first jump.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(isOn: $settings.piAutoTitle) {
                    SettingLabel(String(localized: "Generate session titles"), symbol: "character.cursor.ibeam", tint: .purple)
                }
            } header: {
                Text("pi compatibility")
            } footer: {
                Text("pi names a session only through /name. When on, an unnamed session gets a short title from the current model on its first message (one small extra model call per session), saved as pi's session name so /resume shows it too. Takes effect after you install or update the pi integration.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("General") {
                Toggle(isOn: $launchAtLogin) { SettingLabel(String(localized: "Launch at login"), symbol: "power", tint: .gray) }
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { integrationMessage = String(localized: "Couldn't change the login item: \(error.localizedDescription)") }
                    }
                Picker(selection: Binding(get: { language ?? "" }, set: { language = $0.isEmpty ? nil : $0; AppLanguage.override = language })) {
                    Text("Follow system").tag("")
                    ForEach(AppLanguage.all, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                } label: { SettingLabel(String(localized: "Language"), symbol: "globe", tint: .blue) }
                if language != AppLanguage.atLaunch {
                    LabeledContent {
                        Button("Restart Now") { AppLanguage.relaunch() }.controlSize(.small)
                    } label: {
                        Text("Takes effect after YaaKanban restarts.").padding(.leading, 30).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Toggle(isOn: Binding(get: { model.telemetry.isOn }, set: { model.telemetry.set(enabled: $0) })) {
                    SettingLabel(String(localized: "Send anonymous usage statistics"), symbol: "chart.line.uptrend.xyaxis", tint: .blue)
                }
                .disabled(!model.telemetry.available)
                if model.telemetry.isOn {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Button("View") { FeedbackPrompt.show(title: String(localized: "Today's statistics (sent tomorrow)"), text: model.telemetry.preview()) }
                            Button("Reset") { model.telemetry.resetId() }
                        }
                        .controlSize(.small)
                    } label: {
                        Text("Anonymous ID \(model.telemetry.installId?.prefix(8) ?? "")…").padding(.leading, 30)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
                    Button("Feedback…") { FeedbackPrompt.present(model) }.controlSize(.small)
                } label: { SettingLabel(String(localized: "Issues and ideas"), symbol: "bubble.left.fill", tint: .green) }
            } header: {
                Text("Privacy and feedback")
            } footer: {
                Text(model.telemetry.doNotTrack ? "DO_NOT_TRACK is set, so no statistics are sent."
                     : !model.telemetry.available ? "This build has no statistics service configured and sends no data."
                     : "Off by default. When on, sends Aptabase one anonymous report a day: version, system, integration status, and rough ranges of feature use and session counts. No prompts, code, paths, project or session names. Command line: yaak telemetry status|on|off.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("About") {
                LabeledContent("Version", value: AboutHeader.version)
                LabeledContent("License", value: "GPL-3.0")
                LabeledContent("Source code") { Link(destination: AboutHeader.repo) { Text(verbatim: "github.com/ArtrixTech/YaaKanban") } }
                Text("© 2026 Artrix · Open source under GPL-3.0").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m < 60 { return String(localized: "\(m) min") }
        return m % 60 == 0 ? String(localized: "\(m / 60) h") : String(localized: "\(m / 60) h \(m % 60) min")
    }

    static var yaak: String { AppModel.yaakPath }

    private func apply(_ i: any Integration, install: Bool) {
        do {
            try Installer.apply(try i.plan(install: install, home: Paths.home(), yaak: Self.yaak))
            model.telemetry.count(install ? .integrationInstall : .integrationUninstall)
            let name = i.agent.displayName
            integrationMessage = !install ? String(localized: "\(name) uninstalled.")
                : i.pendingSteps(home: Paths.home()).isEmpty ? String(localized: "\(name) installed.")
                : String(localized: "\(name) installed. You still need to approve it in \(name); the steps are above.")
        } catch {
            model.telemetry.count(.integrationFail)
            integrationMessage = "\(i.agent.displayName): \(error)"
        }
        recheck()
    }

    private func recheck() {
        model.checkIntegrations()
        refresh += 1
    }
}

/// Top of the settings window: logo, name, version, one-line pitch.
struct AboutHeader: View {
    static let repo = Feedback.repo
    static var version: String {
        let info = Bundle.main.infoDictionary
        guard let v = info?["CFBundleShortVersionString"] as? String else { return String(localized: "Development build") }
        return "\(v) (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(spacing: 6) {
            BrandMark(size: 64).shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            Text(verbatim: "YaaKanban").font(.system(size: 20, weight: .bold))
            Text("Version \(Self.version)").font(.caption).foregroundStyle(.secondary)
            Text("Keeps an eye on your coding agents: know the moment one finishes, gets stuck, or needs you.")
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

/// Numbered steps for authorizing hooks in the agent, under its row in Settings.
struct AuthorizationSteps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(steps.enumerated()), id: \.offset) { n, step in
                Text("\(n + 1). \(step)").font(.system(size: 11)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 30)
    }
}

/// Integration status as a small colored capsule.
struct StatusBadge: View {
    let status: IntegrationStatus

    var body: some View {
        let (text, color): (String, Color) = switch status {
        case .installed: (String(localized: "Installed"), .green)
        case .outdated: (String(localized: "Update available"), .orange)
        case .needsAuthorization: (String(localized: "Needs approval"), .yellow)
        case .notInstalled: (String(localized: "Not installed"), .secondary)
        case .notDetected: (String(localized: "Not detected"), .secondary)
        }
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}
