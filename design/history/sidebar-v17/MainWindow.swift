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

/// The sidebar: the state counts beside the window buttons, under them the leverage capsule and the Overview button, the list's head with its
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
            // The running sessions' state counts and the name sit at the sidebar's right edge, midway
            // between the window's top and the card.
            HStack(spacing: Space.m) {
                Spacer()
                let counts = statusCounts(model.activeSessions)
                HStack(spacing: Space.xs) {
                    ForEach(counts, id: \.0.rank) { st, n in CountChip(count: n, status: st).transition(.scale.combined(with: .opacity)) }
                }
                .animation(.snappy, value: counts.map(\.1))
                Text(verbatim: "YaaKanban").font(.ui(.footnote, .semibold)).foregroundStyle(Ink.secondary).lineLimit(1)
            }
            .frame(height: 38).padding(.trailing, Space.xs)
            head
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

    @ViewBuilder private var head: some View {
        let on = selection == AppModel.overview, open = { select(AppModel.overview) }
        switch SidebarHeadStyle(rawValue: model.settings.sidebarStyle) ?? .glass {
        case .glass: OverviewCard(onOverview: on, onSelect: open)
        case .row: OverviewRow(onOverview: on, onSelect: open)
        case .card: OverviewTile(onOverview: on, onSelect: open)
        case .pill: OverviewPill(onOverview: on, onSelect: open)
        }
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

/// The sidebar's brand and its way into Overview, side by side: a capsule of dark glass lit from the
/// foot in the hue of today's leverage (blue when low, violet, red when high) with the logo and today's
/// figure, its light drifting and changing shape while the window is key; and a round button with the
/// house that opens 概览, bare until 概览 is open, then a shade darker.
private struct OverviewCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.controlActiveState) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// Overview is open beside it.
    var onOverview: Bool
    var onSelect: () -> Void
    @State private var hover = false
    private static let height: CGFloat = 66

    var body: some View {
        let _ = model.activityVersion
        let leverage = model.report(Periods(.day, back: 0, now: Date(), calendar: model.settings.calendar).range, buckets: 1).leverage
        let heat = LeverageHeat(leverage)
        HStack(spacing: Space.s) {
            HStack(spacing: Space.m) {
                BrandGlyph(size: 16)
                Spacer(minLength: Space.s)
                figure(leverage)
            }
            .padding(.leading, Space.xl).padding(.trailing, Space.xl + Space.xxs)
            .frame(maxWidth: .infinity).frame(height: Self.height)
            .background {
                // Only the light is redrawn at 30 fps; still when the window isn't key or motion is reduced.
                ZStack {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || active == .inactive)) {
                        FootGlow(heat: heat, t: $0.date.timeIntervalSinceReferenceDate)
                    }
                    heat.base.opacity(0.15)
                }
                .clipShape(Capsule())
            }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .combine)
            .help(String(localized: "Today's leverage"))

            Button(action: onSelect) {
                HomeMark(size: 22).opacity(onOverview || hover ? 1 : 0.8)
                    .frame(width: Self.height, height: Self.height)
                    .background(Circle().fill(.black.opacity(onOverview ? (scheme == .dark ? 0.22 : 0.08) : 0)))
                    .contentShape(Circle())
            }
            .buttonStyle(Pressable())
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
            .animation(.easeOut(duration: 0.15), value: onOverview)
            .accessibilityLabel(Text("Overview"))
            .accessibilityAddTraits(onOverview ? .isSelected : [])
            .help(onOverview ? "" : String(localized: "Overview"))
        }
    }

    private func figure(_ leverage: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: leverage.map { String(format: "%.1f", $0) } ?? "–").font(.figure(20)).tracking(-0.4)
                    .contentTransition(.numericText())
                if leverage != nil { Text(verbatim: "×").font(.ui(.body, .semibold)).foregroundStyle(Ink.secondary) }
            }
            .foregroundStyle(.primary.opacity(0.95))
            Text("Today's leverage").font(.ui(.caption, .medium)).foregroundStyle(Ink.secondary)
        }
        .lineLimit(1)
    }
}

/// Overview's mark, a low house leaning on a tall one (`home.svg`, 220 × 160), in the text color;
/// a symbol when running unbundled.
private struct HomeMark: View {
    var size: CGFloat
    private static let image: NSImage? = Bundle.main.url(forResource: "home", withExtension: "svg").flatMap(NSImage.init(contentsOf:)).map {
        $0.isTemplate = true; return $0
    }

    var body: some View {
        if let img = Self.image {
            Image(nsImage: img).renderingMode(.template).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size).foregroundStyle(.primary)
        } else {
            Image(systemName: "house.fill").font(.system(size: size * 0.75)).frame(width: size, height: size)
        }
    }
}

/// Trial, to go once one is chosen: the sidebar's ways into Overview the user switches between in
/// Settings › General.
enum SidebarHeadStyle: String, CaseIterable {
    case glass, row, card, pill

    var name: String {
        switch self {
        case .glass: "A 玻璃胶囊（当前）"
        case .row: "B 列表行"
        case .card: "C 卡片"
        case .pill: "D 细胶囊"
        }
    }
}

/// Today's leverage, as the sidebar heads show it.
@MainActor private func todayLeverage(_ model: AppModel) -> Double? {
    let _ = model.activityVersion
    return model.report(Periods(.day, back: 0, now: Date(), calendar: model.settings.calendar).range, buckets: 1).leverage
}

/// Trial B: Overview as the list's first row, like Settings at the foot: its tile, its name, and
/// today's figure at the trailing edge in the heat's ink.
private struct OverviewRow: View {
    @Environment(AppModel.self) private var model
    var onOverview: Bool
    var onSelect: () -> Void

    var body: some View {
        let leverage = todayLeverage(model)
        Button(action: onSelect) {
            HStack(spacing: Space.m) {
                HomeMark(size: 13).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Plate(shape: RoundedRectangle(cornerRadius: Radius.tile(22), style: .continuous), tint: .indigo))
                Text("Overview").font(.ui(.body, .medium)).lineLimit(1)
                Spacer(minLength: Space.xs)
                LeverageFigure(leverage: leverage, size: 13)
            }
            .padding(.horizontal, Space.m).frame(height: 34)
            .modifier(RowHighlight(selected: onOverview))
        }
        .buttonStyle(Pressable())
        .accessibilityAddTraits(onOverview ? .isSelected : [])
    }
}

/// Trial C: Overview as a card among the session cards, on their surface: the house and 概览 over
/// a line saying what the figure is, today's figure at the right, a trace of the heat at its foot.
private struct OverviewTile: View {
    @Environment(AppModel.self) private var model
    var onOverview: Bool
    var onSelect: () -> Void
    @State private var hover = false

    var body: some View {
        let leverage = todayLeverage(model)
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.s) {
                    HomeMark(size: 14)
                    Text("Overview").font(.ui(.body, .semibold))
                }
                Text("Today's leverage").font(.ui(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.s)
            LeverageFigure(leverage: leverage, size: 20)
        }
        .lineLimit(1)
        .padding(.horizontal, Space.l).padding(.vertical, Space.m + Space.xxs)
        .background {
            ZStack {
                shape.fill(hover ? Fill.cardHover : Fill.card)
                LinearGradient(colors: [LeverageHeat(leverage).ink.opacity(0), LeverageHeat(leverage).ink.opacity(0.12)],
                               startPoint: .top, endPoint: .bottom).clipShape(shape)
            }
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .overlay { if onOverview { shape.fill(Fill.selected) } }
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onOverview ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// Trial D: v16's two parts made small and plain: a slim capsule on the cards' surface with the
/// logo and today's figure in the heat's ink, and the bare house button beside it.
private struct OverviewPill: View {
    @Environment(AppModel.self) private var model
    var onOverview: Bool
    var onSelect: () -> Void
    @State private var hover = false
    private static let height: CGFloat = 40

    var body: some View {
        let leverage = todayLeverage(model)
        HStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                BrandGlyph(size: 13)
                Text("Today's leverage").font(.ui(.footnote)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: Space.xs)
                LeverageFigure(leverage: leverage, size: 15)
            }
            .padding(.horizontal, Space.l + Space.xxs)
            .frame(maxWidth: .infinity).frame(height: Self.height)
            .surface(Capsule())
            .accessibilityElement(children: .combine)

            Button(action: onSelect) {
                HomeMark(size: 18).opacity(onOverview || hover ? 1 : 0.75)
                    .frame(width: Self.height, height: Self.height)
                    .background(Circle().fill(onOverview ? Fill.selected : hover ? Fill.control.opacity(0.6) : .clear))
                    .contentShape(Circle())
            }
            .buttonStyle(Pressable())
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
            .accessibilityLabel(Text("Overview"))
            .accessibilityAddTraits(onOverview ? .isSelected : [])
            .help(onOverview ? "" : String(localized: "Overview"))
        }
    }
}

/// Today's figure and its ×, the figure in the heat's ink.
private struct LeverageFigure: View {
    let leverage: Double?
    var size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(verbatim: leverage.map { String(format: "%.1f", $0) } ?? "–").font(.figure(size))
                .foregroundStyle(LeverageHeat(leverage).ink)
                .contentTransition(.numericText())
            if leverage != nil { Text(verbatim: "×").font(.ui(.caption, .semibold)).foregroundStyle(.secondary) }
        }
        .lineLimit(1).fixedSize()
        .help(String(localized: "Today's leverage"))
    }
}

/// Leverage on a cool-to-hot scale, by doublings: 1× and under blue, about 3× violet, 8× and over
/// red. No figure yet: a dim gray.
private struct LeverageHeat {
    let level: Double?
    init(_ leverage: Double?) { level = leverage.map { min(max(log2(max($0, 1)) / 3, 0), 1) } }
    /// The pane, almost black with a trace of the hue.
    var base: Color { color(b: 0.07) }
    /// The broad glow, a shade either way along the scale.
    func glow(_ shift: Double) -> Color { color(shift, b: level == nil ? 0.4 : 0.85) }
    /// Text in the hue, legible on either appearance; secondary ink with no figure yet.
    var ink: Color {
        guard let level else { return .secondary }
        let hue = (0.6 + 0.4 * level + 1).truncatingRemainder(dividingBy: 1)
        return Color(light: NSColor(hue: hue, saturation: 0.75, brightness: 0.7, alpha: 1),
                     dark: NSColor(hue: hue, saturation: 0.45, brightness: 1, alpha: 1))
    }
    /// The pale light along the foot, a step cooler.
    var core: Color { color(-0.06, saturation: 0.5, b: level == nil ? 0.5 : 1) }

    private func color(_ shift: Double = 0, saturation: Double = 1, b: Double) -> Color {
        Color(hue: (0.6 + 0.4 * (level ?? 0) + shift + 1).truncatingRemainder(dividingBy: 1),
              saturation: (level == nil ? 0.12 : 0.85) * saturation, brightness: b)
    }
}

/// Light rising from the pane's foot: three broad lobes in the heat's hue, each drifting and changing
/// shape on its own slow loop, and a paler core sliding along the edge.
private struct FootGlow: View {
    let heat: LeverageHeat
    let t: Double
    private static let lobes: [(x: Double, period: Double, phase: Double, shift: Double)] = [
        (0.25, 19, 0, 0.035), (0.75, 23, 2.2, -0.035), (0.5, 29, 4.1, 0)]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(heat.base))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: h * 0.3))
                l.blendMode = .screen
                for s in Self.lobes {
                    let a = 2 * .pi * t / s.period + s.phase
                    let c = CGPoint(x: w * (s.x + 0.12 * sin(a)), y: h * (1.05 + 0.08 * cos(a * 1.3)))
                    let rx = w * (0.32 + 0.08 * sin(a * 0.7)), ry = h * (0.5 + 0.12 * cos(a * 0.9))
                    l.fill(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)), with: .color(heat.glow(s.shift)))
                }
                let a = 2 * .pi * t / 17
                let cx = w * (0.5 + 0.18 * sin(a)), rx = w * (0.38 + 0.06 * cos(a * 1.2)), ry = h * 0.22
                l.fill(Path(ellipseIn: CGRect(x: cx - rx, y: h * 1.02 - ry, width: 2 * rx, height: 2 * ry)), with: .color(heat.core))
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
