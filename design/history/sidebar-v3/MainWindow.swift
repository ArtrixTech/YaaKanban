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

/// The sidebar's way into Overview, dark in both appearances (the sidebar's one accent): today's
/// leverage on a panel lit in its heat, and beside it what makes it up, the change since yesterday
/// and the boards' sessions per state. The light drifts slowly while the window is key; hovered,
/// it brightens; chosen, it stays as it is.
private struct OverviewCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.controlActiveState) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onSelect: () -> Void
    @State private var hover = false

    var body: some View {
        let _ = model.activityVersion
        let p = Periods(.day, back: 0, now: Date(), calendar: model.settings.calendar)
        let r = model.report(p.range, buckets: 1)
        let prev = model.report(p.previousSoFar, buckets: 1)
        let base = prev.lanes.isEmpty && prev.turns == 0 ? nil : prev
        let heat = LeverageHeat(r.leverage)
        let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
        HStack(spacing: 0) {
            leverage(r).frame(width: 104).frame(maxHeight: .infinity)
                .background { moving { HeatField(heat: heat, t: $0, bright: hover) } }
            parts(r, base).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { ZStack { Color(white: 0.07); moving { SeamGlow(heat: heat, t: $0) } } }
        }
        .frame(height: 112)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(hover ? 0.18 : 0.08), lineWidth: 1) }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .environment(\.colorScheme, .dark)
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onSelect)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .help(String(localized: "Today. Click to open Overview in the main window."))
    }

    /// A background redrawn at 30 fps (only it, not the figures over it); still when the window
    /// isn't key or motion is reduced.
    private func moving<V: View>(@ViewBuilder _ draw: @escaping (Double) -> V) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || active == .inactive)) { draw($0.date.timeIntervalSinceReferenceDate) }
    }

    private func leverage(_ r: ActivityReport) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Text(verbatim: r.leverage.map { String(format: "%.1f", $0) } ?? "–")
                    .font(.figure(30)).tracking(-0.6).foregroundStyle(.white)
                if r.leverage != nil {
                    Text(verbatim: "×").font(.ui(.headline, .semibold)).foregroundStyle(.white.opacity(0.75)).baselineOffset(10)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            Text("Today's leverage").font(.ui(.footnote, .medium)).foregroundStyle(.white.opacity(0.72)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(Space.l + Space.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parts(_ r: ActivityReport, _ base: ActivityReport?) -> some View {
        let counts = statusCounts(model.activeSessions)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("Overview").font(.ui(.body, .semibold)).foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: Space.xs)
                if let now = r.leverage, let then = base?.leverage, String(format: "%.1f", abs(now - then)) != "0.0" {
                    Text(verbatim: (now > then ? "↑" : "↓") + String(format: "%.1f×", abs(now - then)))
                        .font(.figure(TextSize.caption.rawValue)).foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 5).padding(.vertical, Space.xxs)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.18)))
                        .help(String(localized: "vs \(Period.day.previous(soFar: true))"))
                }
            }
            Text(String(localized: "Agents \(duration(r.agentTime)) ÷ you \(duration(r.activeTime))"))
                .font(.ui(.footnote, .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            HStack(spacing: Space.m) {
                ForEach(counts, id: \.0.rank) { st, n in
                    HStack(spacing: 3) {
                        Circle().fill(st.tint).frame(width: 6, height: 6)
                        Text(verbatim: "\(n)").font(.figure(11)).foregroundStyle(.white.opacity(0.85)).contentTransition(.numericText())
                    }
                    .help("\(n) \(st.label)")
                }
                Spacer(minLength: Space.xs)
                Image(systemName: "chart.line.uptrend.xyaxis").font(.ui(.footnote, .semibold)).foregroundStyle(.white.opacity(hover ? 1 : 0.8))
                    .frame(width: 30, height: 20).background(Capsule().fill(.white.opacity(hover ? 0.2 : 0.12)))
            }
            .animation(.snappy, value: counts.map(\.1))
        }
        .padding(Space.l)
    }
}

/// Leverage on a cool-to-hot scale, by doublings: 1× and under blue, about 3× violet, 8× and over
/// red. No figure yet: a dim gray.
private struct LeverageHeat {
    let level: Double?
    init(_ leverage: Double?) { level = leverage.map { min(max(log2(max($0, 1)) / 3, 0), 1) } }
    private var hue: Double { 0.6 + 0.4 * (level ?? 0) }
    private var saturation: Double { level == nil ? 0.08 : 0.82 }
    var deep: Color { color(0, brightness: level == nil ? 0.16 : 0.32) }
    var main: Color { color(0, brightness: level == nil ? 0.36 : 0.86) }
    func glow(_ shift: Double) -> Color { color(shift, saturation: saturation * 0.75, brightness: level == nil ? 0.5 : 1) }

    private func color(_ shift: Double, saturation: Double? = nil, brightness: Double) -> Color {
        Color(hue: (hue + shift + 1).truncatingRemainder(dividingBy: 1), saturation: saturation ?? self.saturation, brightness: brightness)
    }
}

/// The leverage panel's light: deep at the top, bright at the foot, three soft lights drifting on
/// slow, unrelated loops, and a faint sheen crossing once every 12 s.
private struct HeatField: View {
    let heat: LeverageHeat
    let t: Double
    var bright = false
    private static let lights: [(period: Double, phase: Double, shift: Double, x: Double, y: Double)] = [
        (13, 0, 0.04, 0.2, 0.85), (19, 2.1, -0.05, 0.85, 0.7), (29, 4.2, 0, 0.5, 1)]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, all = Path(CGRect(origin: .zero, size: size))
            ctx.fill(all, with: .linearGradient(Gradient(colors: [heat.deep, heat.main]), startPoint: .zero, endPoint: CGPoint(x: w * 0.3, y: h)))
            ctx.drawLayer { l in
                l.blendMode = .screen
                for (i, s) in Self.lights.enumerated() {
                    let a = 2 * .pi * t / s.period + s.phase
                    let c = CGPoint(x: w * (s.x + 0.32 * sin(a)), y: h * (s.y + 0.16 * cos(a * 1.3)))
                    let r = h * (0.62 + 0.08 * sin(a * 0.7 + Double(i)))
                    l.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .radialGradient(Gradient(colors: [heat.glow(s.shift).opacity(bright ? 0.6 : 0.45), .clear]),
                                                 center: c, startRadius: 0, endRadius: r))
                }
            }
            let sweep = (t / 12).truncatingRemainder(dividingBy: 1) * 3 - 1
            ctx.drawLayer { l in
                l.translateBy(x: w * sweep, y: 0)
                l.rotate(by: .degrees(24))
                l.fill(Path(CGRect(x: 0, y: -h, width: w * 0.35, height: h * 3)),
                       with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.09), .clear]),
                                             startPoint: .zero, endPoint: CGPoint(x: w * 0.35, y: 0)))
            }
            // Keeps the top deep, so the panel reads as lit from below.
            ctx.fill(all, with: .linearGradient(Gradient(colors: [.black.opacity(0.32), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.6)))
        }
    }
}

/// The black side: the panel's hue bleeding faintly in from the seam, breathing slowly.
private struct SeamGlow: View {
    let heat: LeverageHeat
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: 0, y: size.height * (0.55 + 0.1 * sin(2 * .pi * t / 17)))
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [heat.main.opacity(0.16 + 0.05 * sin(2 * .pi * t / 9)), .clear]),
                                           center: c, startRadius: 0, endRadius: size.height * 1.1))
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
