import AppKit
import SwiftUI
import YaaCore

/// The main window: the app's own card sidebar, and the overview, a session or settings beside it.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    /// Shows this page instead of the selection (snapshots), leaving the user's selection alone.
    var page: String?
    var tab: SettingsView.Tab?

    var body: some View {
        HStack(spacing: 0) {
            MainSidebar(shown: page).frame(width: 280)
                .background(Color(nsColor: .underPageBackgroundColor))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Fill.canvas)
        }
        // The title bar is hidden; the sidebar and pages run up under the window buttons.
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder private var content: some View {
        let shown = page ?? model.selection
        if shown == AppModel.settingsPage {
            SettingsView(tab: tab.map { .constant($0) } ?? Bindable(model).settingsTab)
        } else if let shown, let s = model.sessions[shown] {
            SessionDetail(session: s)
        } else {
            DashboardView()
        }
    }
}

/// The sidebar: the logo under the window buttons, the Overview card, the list's head with its
/// search button, the boards' sessions as cards, history as rows, and Settings at the foot. Arrow
/// keys move the selection once the list has been clicked.
private struct MainSidebar: View {
    @Environment(AppModel.self) private var model
    var shown: String?
    @State private var filter: AgentKind?
    @State private var query = ""
    @State private var searching = false
    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool

    private var selection: String? { shown ?? model.selection }

    var body: some View {
        let active = model.board.filter(matches)
        let history = self.history.filter(matches)
        // The list's first section heads it, with the search button; History follows in the list.
        let leadsWithActive = !model.board.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            brand.padding(.horizontal, Space.m).padding(.top, 34)
            OverviewCard { select(AppModel.overview) }
                .padding(.top, Space.l)
            listHead(leadsWithActive ? String(localized: "Active") : String(localized: "History"),
                     leadsWithActive ? active.count : nil)
                .padding(.top, Space.l)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s) {
                        ForEach(active) { s in
                            SidebarCard(session: s, selected: selection == s.id) { select(s.id) }.id(s.id)
                        }
                        if !history.isEmpty {
                            if leadsWithActive { section(String(localized: "History"), nil) }
                            LazyVStack(spacing: Space.xxs) {
                                ForEach(history) { s in
                                    SidebarRow(session: s, selected: selection == s.id) { select(s.id) }.id(s.id)
                                }
                            }
                        }
                        if active.isEmpty && history.isEmpty && (!query.isEmpty || filter != nil) {
                            Text("No matches").font(.ui(.callout)).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity).padding(.top, Space.xxl)
                        }
                    }
                    .padding(.top, Space.m).padding(.bottom, Space.xxl + Space.l)
                }
                .scrollIndicators(.never)
                // The list fades in under its head and out above Settings rather than being cut off.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Space.m)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 40)
                    }
                }
                .focusable()
                .focused($listFocused)
                .focusEffectDisabled()
                .onKeyPress(.upArrow) { step(-1, [AppModel.overview] + (active + history).map(\.id), proxy) }
                .onKeyPress(.downArrow) { step(1, [AppModel.overview] + (active + history).map(\.id), proxy) }
            }
            nav(AppModel.settingsPage, String(localized: "Settings"), "gearshape.fill", .gray,
                badge: settingsBadge > 0 ? settingsBadge : nil)
        }
        .padding(.horizontal, 10).padding(.bottom, Space.l)
    }

    /// Sessions not on the boards; the active set is computed once, not per session.
    private var history: [SessionState] {
        let active = Set(model.activeSessions.map(\.id))
        return model.allSessions.filter { !active.contains($0.id) }
    }

    /// Agents whose hooks wait for approval, and an update ready to install.
    private var settingsBadge: Int {
        let ready = if case .ready = model.updater.phase { 1 } else { 0 }
        return model.integrationIssues.count + ready
    }

    private func select(_ id: String) {
        model.selection = id
        listFocused = true
    }

    private func step(_ by: Int, _ ids: [String], _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !ids.isEmpty else { return .handled }
        // From outside the list (Settings, or a session hidden by the search), enter it at the near end.
        let next = ids.firstIndex { $0 == model.selection }.map { min(max($0 + by, 0), ids.count - 1) } ?? (by > 0 ? 0 : ids.count - 1)
        model.selection = ids[next]
        withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(ids[next]) }
        return .handled
    }

    private func matches(_ s: SessionState) -> Bool {
        if let filter, s.agent != filter { return false }
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return [s.cwd, s.title, s.sessionId, s.peek?.lastPrompt].compactMap { $0?.lowercased() }.contains { $0.contains(q) }
            || s.turns.contains { $0.prompt.lowercased().contains(q) }
    }
}

// MARK: Parts

extension MainSidebar {
    /// The list's first section title and count, with the search button at the end; searching,
    /// the row is the search field and the agent filter.
    @ViewBuilder private func listHead(_ title: String, _ count: Int?) -> some View {
        Group {
            if searching {
                search
            } else {
                HStack(spacing: Space.s) {
                    Text(title).font(.ui(.footnote, .semibold)).foregroundStyle(.secondary)
                    if let count { Text(verbatim: "\(count)").font(.figure(10)).foregroundStyle(.tertiary) }
                    Spacer(minLength: Space.xs)
                    IconButton(symbol: "magnifyingglass", help: String(localized: "Search")) { openSearch() }
                        .keyboardShortcut("f")
                }
                .padding(.leading, Space.m)
            }
        }
        .frame(height: 26)
    }

    private var search: some View {
        HStack(spacing: Space.s) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.ui(.footnote)).foregroundStyle(.secondary)
                TextField("Project / prompt", text: $query).textFieldStyle(.plain).font(.ui(.callout))
                    .focused($searchFocused)
                    .onExitCommand(perform: closeSearch)
                Button(action: closeSearch) {
                    Image(systemName: "xmark.circle.fill").font(.ui(.footnote)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close search")
            }
            .padding(.horizontal, Space.m).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Fill.control))
            Menu {
                Picker("Agent", selection: $filter) {
                    Text("All").tag(AgentKind?.none)
                    ForEach(AgentKind.allCases, id: \.self) { Text($0.displayName).tag(AgentKind?.some($0)) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .font(.ui(.body, .medium))
                    .foregroundStyle(filter == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: 22, height: 22)
            .help(filter?.displayName ?? String(localized: "Agent"))
        }
        .onAppear { searchFocused = true }
    }

    private func openSearch() {
        withAnimation(.snappy(duration: 0.2)) { searching = true }
    }

    /// Esc or the cross: the head comes back and the whole list with it.
    private func closeSearch() {
        withAnimation(.snappy(duration: 0.2)) { searching = false }
        query = ""
        filter = nil
    }

    private var brand: some View {
        HStack(spacing: 6) {
            BrandMark(size: 20)
            Text(verbatim: "YaaKanban").font(.ui(.body, .bold)).lineLimit(1)
        }
    }

    private func section(_ title: String, _ count: Int?) -> some View {
        HStack(spacing: Space.s) {
            Text(title).font(.ui(.footnote, .semibold)).foregroundStyle(.secondary)
            if let count { Text(verbatim: "\(count)").font(.figure(10)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, Space.m).padding(.top, Space.xl).padding(.bottom, Space.xxs)
    }

    private func nav(_ id: String, _ title: String, _ symbol: String, _ tint: Color, badge: Int? = nil) -> some View {
        Button { select(id) } label: {
            HStack(spacing: Space.m) {
                IconTile(symbol: symbol, tint: tint, size: 22)
                Text(title).font(.ui(.body, .medium)).lineLimit(1)
                Spacer(minLength: Space.xs)
                if let badge { Badge(text: "\(badge)", tint: .orange, compact: true) }
            }
            .padding(.horizontal, Space.m).frame(height: 34)
            .modifier(RowHighlight(selected: selection == id))
        }
        .buttonStyle(Pressable())
        .accessibilityAddTraits(selection == id ? .isSelected : [])
        .id(id)
    }
}

/// The sidebar's way into Overview: a frosted pane with soft lights in acid hues drifting and
/// changing shape under it, and only its name on top. The light moves while the window is key;
/// hovered, it brightens; chosen, it stays as it is.
private struct OverviewCard: View {
    @Environment(\.controlActiveState) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var onSelect: () -> Void
    @State private var hover = false

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
        HStack(spacing: Space.s) {
            Text("Overview").font(.ui(.headline, .semibold)).foregroundStyle(Ink.primary)
            Spacer(minLength: Space.s)
            Image(systemName: "arrow.up.right").font(.ui(.footnote, .semibold)).foregroundStyle(.primary.opacity(hover ? 0.75 : 0.45))
        }
        .padding(.horizontal, Space.l + Space.xxs)
        .frame(height: 62)
        .background {
            ZStack {
                shape.fill(dark ? Color(white: 0.1) : Color(white: 0.97))
                // Only the light is redrawn at 30 fps; still when the window isn't key or motion is reduced.
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || active == .inactive)) {
                    GlassLight(t: $0.date.timeIntervalSinceReferenceDate, bright: hover)
                }
                // The frost: a pale veil over the light, clearer towards the foot.
                LinearGradient(colors: [.white.opacity(dark ? 0.1 : 0.45), .white.opacity(dark ? 0.02 : 0.15)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(shape)
        }
        // The pane's edge: lit at the top left, fading round to the foot.
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.35 : 0.9), .white.opacity(dark ? 0.04 : 0.2), .white.opacity(dark ? 0.12 : 0.5)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: .black.opacity(dark ? 0.3 : 0.08), radius: 10, y: 4)
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onSelect)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// Four soft lights, acid lime, cyan, violet and a touch of pink, each drifting and stretching one
/// way then the other on its own slow loop, so the pane's light keeps changing shape.
private struct GlassLight: View {
    let t: Double
    var bright = false
    @Environment(\.colorScheme) private var scheme
    private static let lights: [(color: Color, x: Double, y: Double, period: Double, phase: Double)] = [
        (Color(red: 0.72, green: 1, blue: 0.18), 0.18, 0.7, 17, 0),
        (Color(red: 0.1, green: 0.9, blue: 1), 0.55, 0.2, 23, 1.7),
        (Color(red: 0.55, green: 0.36, blue: 1), 0.86, 0.75, 29, 3.4),
        (Color(red: 1, green: 0.35, blue: 0.75), 0.4, 1.1, 37, 5.1),
    ]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, dark = scheme == .dark
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: h * 0.32))
                if dark { l.blendMode = .screen }
                l.opacity = (dark ? 0.55 : 0.7) * (bright ? 1.25 : 1)
                for s in Self.lights {
                    let a = 2 * .pi * t / s.period + s.phase
                    let c = CGPoint(x: w * (s.x + 0.14 * sin(a)), y: h * (s.y + 0.3 * cos(a * 1.4)))
                    let rx = h * (0.9 + 0.35 * sin(a * 0.8)), ry = h * (0.55 + 0.2 * cos(a * 1.1))
                    l.fill(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)), with: .color(s.color))
                }
            }
        }
    }
}

/// An active session in the sidebar: its card, tinted when it wants the user, a pin when pinned.
private struct SidebarCard: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    let selected: Bool
    var onSelect: () -> Void
    @State private var hover = false

    var body: some View {
        let s = session, status = model.display(s)
        // As on the panel's cards: the glyph opens the title row, and the row under it starts at the
        // card's edge, under the glyph.
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                StatusGlyph(status: status, size: 18)
                Text(s.title).font(.ui(.body, .semibold)).lineLimit(1)
                if model.isPinned(s.id) {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Color(red: 1, green: 0.75, blue: 0)).help("Pinned")
                }
                Spacer(minLength: Space.xxs)
                Text(when(s.lastEventAt)).font(.ui(.caption)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 5) {
                AgentLogo(agent: s.agent, size: 11)
                Text(s.projectName ?? s.agent.displayName).font(.ui(.footnote)).foregroundStyle(.secondary).lineLimit(1)
                StatusPill(status: status)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, Space.m)
        .card(status, hover: hover)
        .overlay { if selected { RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Fill.selected) } }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .contextMenu { SessionMenu(session: s) }
    }
}

/// A past session in the sidebar: one plain line.
private struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    let session: SessionState
    let selected: Bool
    var onSelect: () -> Void

    var body: some View {
        let s = session
        HStack(spacing: Space.m) {
            StatusGlyph(status: model.display(s), size: 18)
            Text(s.title).font(.ui(.callout)).lineLimit(1)
            Spacer(minLength: Space.xs)
            AgentLogo(agent: s.agent, size: 11)
            Text(when(s.lastEventAt)).font(.ui(.caption)).foregroundStyle(.tertiary).fixedSize()
        }
        .padding(.horizontal, 10).frame(height: 28)
        .modifier(RowHighlight(selected: selected))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .help(s.projectName ?? s.agent.displayName)
        .contextMenu { SessionMenu(session: s) }
    }
}

/// The neutral fill behind the chosen sidebar row, and a fainter one on hover.
private struct RowHighlight: ViewModifier {
    let selected: Bool
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(selected ? Fill.selected : hover ? Fill.control.opacity(0.6) : .clear)
            }
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

private struct SessionMenu: View {
    @Environment(AppModel.self) private var model
    let session: SessionState

    var body: some View {
        let s = session
        if s.display == .review { Button("Mark as reviewed") { model.markRead(s.id) } }
        if s.dismissedAt != nil { Button("Restore to floating panel") { model.undismiss(s.id) } }
        Button("Rename…") { model.rename(s.id) }
        Button("Delete from history", role: .destructive) { model.remove(s.id) }
    }
}

/// When a session last moved: the time today, else the day.
private func when(_ date: Date) -> String {
    Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened)
        : date.formatted(.dateTime.month(.abbreviated).day())
}
