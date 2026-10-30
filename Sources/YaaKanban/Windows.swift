import AppKit
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
            if named { Text(verbatim: "YaaKanban").font(.ui(.body, .bold)).lineLimit(1).fixedSize() }
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
                Text(err).font(.ui(.footnote)).foregroundStyle(.red).padding(.horizontal, Space.m)
            }
            if model.noIntegrations {
                MenuRow(symbol: "powerplug.fill", title: String(localized: "Connect agents…")) { done { AppWindows.open(.setup) } }
            }
            if !model.integrationIssues.isEmpty {
                let names = model.integrationIssues.keys.map(\.displayName).sorted().formatted(.list(type: .and))
                MenuRow(symbol: "exclamationmark.triangle.fill", title: String(localized: "\(names) hooks need approval")) {
                    done { model.settingsTab = .agents; AppWindows.open(.settings) }
                }
            }
            Spacer().frame(height: Space.s)
            MenuRow(symbol: "rectangle.on.rectangle", title: model.settings.showPanel ? String(localized: "Hide floating panel") : String(localized: "Show floating panel"),
                    shortcut: "⌥⌘K") { panel.toggle() }
            MenuRow(symbol: "arrow.counterclockwise", title: String(localized: "Reset floating panel position")) { done { panel.resetPosition() } }
            MenuRow(symbol: "macwindow", title: String(localized: "Main window")) { done { AppWindows.open(.main) } }
            MenuRow(symbol: "gearshape", title: String(localized: "Settings…")) { done { AppWindows.open(.settings) } }
            MenuRow(symbol: "bubble.left", title: String(localized: "Feedback…")) { done { FeedbackPrompt.present(model) } }
            if case .ready(let p) = model.updater.phase {
                MenuRow(symbol: "arrow.down.circle.fill", title: String(localized: "Update to \(p.version)…")) { model.updater.installReady() }
            }
            Spacer().frame(height: Space.s)
            MenuRow(symbol: "power", title: String(localized: "Quit YaaKanban")) { NSApp.terminate(nil) }
        }
        .padding(Space.s)
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

/// One line on the floating panel about an update: ready to install, or just installed. Closing
/// it hides it; the menu and settings still offer a ready update.
struct UpdateNotice: View {
    @Environment(AppModel.self) private var model
    let notice: Updater.Notice

    var body: some View {
        Banner(text: text, symbol: icon, tint: .blue, compact: true) {
            Button(actionTitle, action: act).buttonStyle(.action(.ghost, tint: .blue, size: .small))
            IconButton(symbol: "xmark", help: String(localized: "Close")) { withAnimation(.snappy) { model.updater.dismiss() } }
        }
    }

    private var icon: String {
        if case .ready = notice { "arrow.down.circle.fill" } else { "checkmark.circle.fill" }
    }

    private var text: String {
        switch notice {
        case .ready(let p): String(localized: "Version \(p.version) is downloaded")
        case .updated(let v): String(localized: "Updated to \(v.description)")
        }
    }

    private var actionTitle: String {
        if case .ready = notice { String(localized: "Restart to Update") } else { String(localized: "What's New") }
    }

    private func act() {
        switch notice {
        case .ready(let p): model.updater.install(p)
        case .updated(let v):
            NSWorkspace.shared.open(Updater.notes(for: v))
            model.updater.dismiss()
        }
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
                    Text(verbatim: "YaaKanban").font(.ui(.body, .bold))
                    Image(systemName: "chevron.right").font(.ui(.micro, .bold)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text(summary).font(.ui(.footnote)).foregroundStyle(.secondary)
                TodayFigures()
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(hover ? Fill.selected : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help("Open main window")
    }
}

/// A menu-like row: icon, title, optional shortcut; the neutral selection fill on hover.
struct MenuRow: View {
    let symbol: String
    let title: String
    var shortcut: String?
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.ui(.callout)).foregroundStyle(.secondary).frame(width: 16)
                Text(title).font(.ui(.callout))
                Spacer(minLength: Space.m)
                if let shortcut { Text(shortcut).font(.ui(.footnote)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, Space.m).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(hover ? Fill.selected : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct EmptyBoard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            if model.noIntegrations {
                // First run: nothing reports until an integration is installed.
                Image(systemName: "powerplug.fill").font(.system(size: 22)).foregroundStyle(.tertiary)
                Text("No agents connected yet").font(.ui(.callout, .semibold))
                Text("Install the integration for the agents you use; sessions you start afterwards show up here.")
                    .font(.ui(.footnote)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, Space.xl)
                Button("Connect agents…") { AppWindows.open(.setup) }
                    .buttonStyle(.action(.primary, size: .small)).padding(.top, Space.xs)
            } else {
                Image(systemName: "moon.zzz.fill").font(.system(size: 22)).foregroundStyle(.tertiary)
                Text("No active tasks").font(.ui(.callout)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
    }
}

/// Sessions of the last two weeks matching the panel's search, most recent first.
struct SearchResults: View {
    @Environment(AppModel.self) private var model
    let query: String
    var onPick: () -> Void

    var body: some View {
        let found = model.search(query)
        let onBoard = Set(model.activeSessions.map(\.id))
        if found.isEmpty {
            Text("No matches").font(.ui(.callout)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(found) { PickRow(session: $0, onBoard: onBoard.contains($0.id), onPick: onPick) }
            }
        }
    }
}

/// One session in the search. Clicking it goes to it like a card, first putting it back on the
/// panel when it is not there.
struct PickRow: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    let onBoard: Bool
    var onPick: () -> Void
    @State private var hover = false

    var body: some View {
        let s = session
        HStack(spacing: 8) {
            AgentLogo(agent: s.agent, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.ui(.callout, .semibold)).lineLimit(1)
                Text(s.projectName ?? s.agent.displayName).font(.ui(.footnote)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.xs)
            if onBoard { StatusGlyph(status: model.display(s), size: 14) }
            Text(relative(s.lastEventAt)).font(.ui(.caption).monospacedDigit()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Space.m).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(hover ? Fill.selected : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: pick)
        .help(AppModel.isGone(s) ? "Click to resume \(s.agent.displayName) in its original terminal" : "Click to jump to \(s.agent.displayName)")
        .contextMenu {
            Button(AppModel.isGone(s) ? "Resume in original terminal" : "Jump to terminal", action: pick)
            if !onBoard {
                Button("Restore to floating panel") { onPick(); restore() }
            }
            Button("Copy resume command") { model.jumper.copyResume(s) }
            Button("Delete from history", role: .destructive) { model.remove(s.id) }
        }
    }

    private func pick() {
        onPick()
        if !onBoard { restore() }
        model.jump(session.id)
    }

    private func restore() { withAnimation(.snappy) { model.restore(session.id) } }
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
    /// Where the list's top and bottom are in the scroll view, to fade an edge while more is past it.
    @State private var listTop: CGFloat = 0
    @State private var listBottom: CGFloat = 0
    /// The search replaces the list with sessions of the last two weeks.
    @State private var searching = false
    @State private var query = ""

    static let minList: CGFloat = 120
    private static let listTopId = "listTop"
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
            .onChange(of: searching && room?.isKey == true, initial: true) { room?.holdOpen = $1 }
            // Folded back (the user clicked elsewhere, then left): the rail shows cards again.
            .onChange(of: folded) { if $1 { closeSearch() } }
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
            if folded {
                RailHeader()
            } else {
                header
            }
            // Folded too (narrower), so the cards keep their place when the rail unfolds.
            if settings.showRecentStats { RecentFigures(folded: folded) }
            if !folded, let n = model.updater.notice { UpdateNotice(notice: n).transition(.opacity) }
            list
            if !folded { bottomBar }
        }
        // Folded, the sides match the gap between cards.
        .padding(.horizontal, folded ? Rail.inset : 10).padding(.top, 10)
        .padding(.bottom, folded ? Rail.inset : 4)
        // Folded cards are measured as wide as their full cards, so they keep their height.
        .environment(\.railExtra, folded ? settings.panelWidth - 16 - (Rail.width - 2 * Rail.inset) : nil)
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
            if searchShown {
                scrolling {
                    SearchResults(query: query) { closeSearch() }
                }
                .id("search")
            } else if !settings.panelCollapsed {
                if model.activeSessions.isEmpty {
                    EmptyBoard().transition(.opacity)
                } else {
                    scrolling {
                        BoardList(expanded: expanded) { s in
                            withAnimation(.spring(duration: 0.3, bounce: 0.15)) { expanded = expanded == s.id ? nil : s.id }
                        }
                    }
                    .transition(.opacity)
                }
            }
    }

    /// The list area: as tall as `shownList`, scrolling, each edge fading out instead of being cut
    /// while more is past it. Folding scrolls it back to the top.
    private func scrolling(@ViewBuilder _ content: () -> some View) -> some View {
        let content = content()
        return ScrollViewReader { proxy in
            ScrollView {
                content
                    .id(Self.listTopId)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { grow(to: $0) }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: {
                        listTop = $0.minY
                        listBottom = $0.maxY
                    }
            }
            .onChange(of: folded) { if $1 { proxy.scrollTo(Self.listTopId, anchor: .top) } }
        }
        .scrollIndicators(.never)
        .frame(height: shownList)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(moreAbove ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                Color.black
                LinearGradient(colors: [.black, .black.opacity(moreBelow ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
            }
            .animation(.easeOut(duration: 0.15), value: moreAbove)
            .animation(.easeOut(duration: 0.15), value: moreBelow)
        }
    }

    /// One row under the list: the height grip centred, the search on the right. Searching, the
    /// row is the search field.
    @ViewBuilder private var bottomBar: some View {
        if searchShown {
            SearchField(query: $query, onClose: closeSearch).frame(height: 22).padding(.bottom, 2)
        } else {
            HStack(spacing: 0) {
                Color.clear.frame(maxWidth: .infinity)
                if listShown { heightGrip.frame(width: 80) }
                IconButton(symbol: "magnifyingglass", help: String(localized: "Search the last \(AppModel.searchDays) days"), action: openSearch)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 22)
        }
    }

    private var searchShown: Bool { searching && !folded }

    private func openSearch() {
        room?.holdTop()
        room?.makeKey()
        withAnimation(.snappy) { searching = true }
    }

    private func closeSearch() {
        guard searching else { return }
        room?.holdTop()
        withAnimation(.snappy) { searching = false }
        query = ""
    }

    private var heightGrip: some View {
        @Bindable var settings = model.settings
        return ResizeGrip { delta in
            room?.holdTop()
            guard let delta else {
                // Let go at the minimum: back to following the content.
                dragStart = nil
                if (settings.panelListHeight ?? .infinity) <= Self.minList { settings.panelListHeight = nil }
                return
            }
            let start = dragStart ?? shownList
            dragStart = start
            // No taller than the list itself, so dragging back up moves the edge at once.
            let most = max(Self.minList, min(Self.maxList, listHeight))
            settings.panelListHeight = min(most, max(Self.minList, start + delta))
        }
        .frame(height: 22)
    }

    private var moreAbove: Bool { listTop < -1 }
    private var moreBelow: Bool { listBottom > shownList + 1 }

    /// The list's natural height changed. Without a height set by hand the panel follows it both
    /// ways; with one, the panel grows no further than it and the list scrolls, but still shrinks
    /// to a shorter list.
    private func grow(to h: CGFloat) { listHeight = h }

    private var listShown: Bool { searchShown || (!model.settings.panelCollapsed && !model.activeSessions.isEmpty) }

    private var shownList: CGFloat {
        let fits = room.map { max(Self.minList, $0.height - chrome) } ?? .infinity
        return min(listHeight, model.settings.panelListHeight ?? Self.maxList, fits)
    }
}

/// The panel's search field, focused when it appears; Esc or the cross closes the search.
struct SearchField: View {
    @Binding var query: String
    var onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.ui(.footnote, .semibold)).foregroundStyle(.secondary)
            TextField("Search the last \(AppModel.searchDays) days", text: $query)
                .textFieldStyle(.plain).font(.ui(.callout))
                .focused($focused)
                .onExitCommand(perform: onClose)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.ui(.footnote)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close search")
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(Capsule().fill(Fill.control))
        .onAppear { focused = true }
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
    /// The panel is the key window (the search field has the keyboard).
    var isKey = false
    /// The width grip is being dragged: resize at once instead of sliding.
    var resizing = false
    /// Snapshots render the rail folded whatever the user pinned.
    var snapshotFolded = false
    /// The search is open and needs the panel to stay unfolded while the pointer is elsewhere: a
    /// peeking rail would fold and take it away.
    var holdOpen = false
    /// Makes the panel the key window, so the search field takes typing without a click.
    @ObservationIgnored var makeKey: () -> Void = {}
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
    enum Kind: String { case main, settings, setup }
    static let request = Notification.Name("YaaOpenWindow")
    static func open(_ k: Kind) { NotificationCenter.default.post(name: request, object: k.rawValue) }
}

extension NSAlert {
    /// Brings the app forward and runs the alert once the current action has returned, then hands
    /// back the answer. Run inside a SwiftUI action, the modal holds back every view's geometry
    /// callbacks until it closes: a rail that folds under it draws narrow in a window left wide.
    /// Not a GCD block: one stalls every main-actor Task until the alert is closed.
    @MainActor func runLater(_ then: @escaping @MainActor (NSApplication.ModalResponse) -> Void = { _ in }) {
        nonisolated(unsafe) let alert = self
        nonisolated(unsafe) let then = then
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
                then(alert.runModal())
            }
        }
    }
}

struct WindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: AppWindows.request)) { n in
            NSApp.activate()
            switch AppWindows.Kind(rawValue: n.object as? String ?? "") {
            case .main: openWindow(id: "main")
            // Settings is a page of the main window.
            case .settings: model.selection = AppModel.settingsPage; openWindow(id: "main")
            case .setup: openWindow(id: SetupGuide.id)
            case nil: break
            }
        }
    }
}

extension View {
    /// Runs `action` when the user comes back to the app or to one of its windows: the moment to
    /// re-read what they may have changed elsewhere (an agent's hooks, System Settings), instead
    /// of polling.
    func onComeBack(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in action() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in action() }
    }
}
