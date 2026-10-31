import AppKit
import ServiceManagement
import SwiftUI
import YaaCore
import YaaIntegrations

/// Settings, as a page of the main window: a header, a row of tabs, and the chosen tab's groups.
struct SettingsView: View {
    enum Tab: String, CaseIterable { case agents, alerts, panel, compatibility, general, about }

    @Environment(AppModel.self) private var model
    @Binding var tab: Tab
    @State private var integrationMessage: String?
    @State private var refresh = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var language = AppLanguage.override

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(title: String(localized: "Settings"), symbol: "gearshape.fill", tint: .gray)
                    // Long translations scroll the tabs rather than squeezing them.
                    ScrollView(.horizontal, showsIndicators: false) { PageTabs(tabs: tabs, selection: $tab) }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                }
                VStack(alignment: .leading, spacing: 28) { page }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 40).padding(.top, 44).padding(.bottom, Space.page)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Fill.canvas)
        // Approval happens in the agent; its state is read again when the user comes back.
        .onComeBack(perform: recheck)
    }

    private var tabs: [(tab: Tab, title: String, symbol: String)] {
        [(.agents, String(localized: "Agent integrations"), "powerplug.fill"),
         (.alerts, String(localized: "Alerts"), "bell.badge.fill"),
         (.panel, String(localized: "Floating panel"), "rectangle.on.rectangle"),
         (.compatibility, String(localized: "Compatibility"), "puzzlepiece.extension.fill"),
         (.general, String(localized: "General"), "gearshape.2.fill"),
         (.about, String(localized: "About"), "info.circle.fill")]
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .agents: agents
        case .alerts: alerts
        case .panel: panel
        case .compatibility: compatibility
        case .general: general
        case .about: about
        }
    }
}

// MARK: Tabs

extension SettingsView {
    private var agents: some View {
        GroupSection(footer: Text("Once installed, the agent sends session status and approval requests to YaaKanban through hooks.")) {
            // Only agents found on this Mac (or with our hooks still in place) are listed.
            let found = Integrations.all.map { ($0, $0.status(home: Paths.home(), yaak: Self.yaak)) }
                .filter { $0.1 != .notDetected }
            if found.isEmpty {
                Text("No supported agents found. Install one, then reopen Settings.")
                    .font(.ui(.callout)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Row.padding)
            }
            ForEach(found, id: \.0.agent) { i, status in agentRow(i, status) }
                .id(refresh)
            message
        }
    }

    private func agentRow(_ i: any Integration, _ status: IntegrationStatus) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.l) {
                LogoTile(agent: i.agent)
                Text(i.agent.displayName).font(.ui(.body, .medium))
                Spacer(minLength: Space.m)
                StatusBadge(status: status)
                switch status {
                case .outdated:
                    Button("Update") { apply(i, install: true) }.buttonStyle(.action(.primary, size: .small))
                case .installed, .needsAuthorization:
                    Button("Uninstall") { apply(i, install: false) }.buttonStyle(.action(.secondary, size: .small))
                case .notInstalled:
                    Button("Install") { apply(i, install: true) }.buttonStyle(.action(.primary, size: .small))
                case .notDetected:
                    EmptyView()
                }
                if status == .outdated {
                    Button("Uninstall") { apply(i, install: false) }.buttonStyle(.action(.ghost, size: .small))
                }
            }
            if status == .needsAuthorization {
                AuthorizationSteps(integration: i).padding(.leading, 32 + Space.l)
            } else if let note = i.postInstallNote {
                Text(note).font(.ui(.footnote)).foregroundStyle(.secondary).padding(.leading, 32 + Space.l)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Row.padding).padding(.vertical, Space.l)
    }

    /// The outcome of the last install, uninstall or login-item change, selectable for copying.
    @ViewBuilder private var message: some View {
        if let integrationMessage {
            Text(integrationMessage).font(.ui(.footnote)).foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Row.padding).padding(.bottom, Space.l)
        }
    }

    private var alerts: some View {
        @Bindable var settings = model.settings
        return VStack(alignment: .leading, spacing: 28) {
            GroupSection(title: Text("Alerts")) {
                SettingRow(String(localized: "Stuck threshold"), detail: String(localized: "A running session silent this long, or one tool running this long, may be stuck."),
                           symbol: "hourglass", tint: .orange) {
                    Stepped(String(localized: "\(Int(settings.stuckMinutes)) min"), value: $settings.stuckMinutes, in: 1...60)
                }
                SettingRow(String(localized: "Approval wait"), detail: String(localized: "How long an approval waits in the panel or a notification before the agent asks in its terminal."),
                           symbol: "questionmark.bubble.fill", tint: .purple) {
                    Stepped(String(localized: "\(Int(settings.approvalTimeout)) s"), value: $settings.approvalTimeout, in: 5...25)
                }
                SettingRow(String(localized: "No system notifications while Wave is in front"), symbol: "bell.slash.fill", tint: .gray) {
                    Switch(isOn: $settings.suppressWhenWaveFrontmost)
                }
            }
            GroupSection(title: Text("Session reminders"), footer: Text("Review flashing counts only time you're at the computer (2 minutes without keyboard or mouse, or sleep, counts as away). A reviewed session that hasn't run since turns gradually blue from \u{201C}Start tinting\u{201D}, is bluest halfway between that and \u{201C}Keep reviewed sessions\u{201D}, and fades back to gray and leaves the floating panel when the retention ends. Time counts from when the session ended or you last opened it; opening it again restarts the clock.")) {
                SettingRow(String(localized: "Keep reviewed sessions"), symbol: "checkmark.circle.fill", tint: .green) {
                    Segmented(items: Preferences.retentionChoices.map { (item: $0, title: Self.duration($0)) }, selection: $settings.idleVisibleMinutes)
                        .onChange(of: settings.idleVisibleMinutes) {
                            settings.staleAfterMinutes = min(settings.staleAfterMinutes, settings.idleVisibleMinutes - 1)
                        }
                }
                SettingRow(String(localized: "Flash when input is needed"), symbol: "light.beacon.max.fill", tint: .purple) {
                    Switch(isOn: $settings.flashEnabled)
                }
                if settings.flashEnabled {
                    SettingRow(String(localized: "Start flashing"), detail: String(localized: "After \(Int(settings.flashAfterSeconds)) s without a click")) {
                        Stepper("Start flashing", value: $settings.flashAfterSeconds, in: 5...600, step: 5).labelsHidden()
                    }
                }
                SettingRow(String(localized: "Flash when a review waits too long"), symbol: "light.beacon.max.fill", tint: .green) {
                    Switch(isOn: $settings.reviewFlashEnabled)
                }
                if settings.reviewFlashEnabled {
                    SettingRow(String(localized: "Start flashing"), detail: String(localized: "After \(Int(settings.reviewFlashMinutes)) min at the computer unviewed")) {
                        Stepper("Start flashing", value: $settings.reviewFlashMinutes, in: 1...60).labelsHidden()
                    }
                }
                SettingRow(String(localized: "Tint seen but idle sessions blue"), symbol: "drop.fill", tint: .blue) {
                    Switch(isOn: $settings.staleTintEnabled)
                }
                if settings.staleTintEnabled {
                    SettingRow(String(localized: "Start tinting"), detail: String(localized: "\(Self.duration(settings.staleAfterMinutes)) after it ends")) {
                        Stepper("Start tinting", value: $settings.staleAfterMinutes, in: 1...max(1, settings.idleVisibleMinutes - 1),
                                step: settings.staleAfterMinutes < 60 ? 5 : 15).labelsHidden()
                    }
                    SettingRow(String(localized: "Bluest"), detail: String(localized: "\(Self.duration(settings.stalePeakMinutes)) after it ends")) {
                        EmptyView()
                    }
                }
                SettingRow(String(localized: "Mark reviewed when its terminal is in front (beta)"), symbol: "eye.fill", tint: .green) {
                    Switch(isOn: $settings.autoReviewOnFocus)
                }
                if settings.autoReviewOnFocus {
                    AutomationAccessRows().padding(.leading, Row.textInset).padding(.trailing, Row.padding).padding(.bottom, Space.l)
                }
            }
        }
    }

    private var panel: some View {
        @Bindable var settings = model.settings
        return GroupSection(title: Text("Floating panel")) {
            SettingRow(String(localized: "Show / hide"), symbol: "command", tint: .blue) { KeyCap(keys: "⌥⌘K") }
            SettingRow(String(localized: "Show leverage and today's work time on top"), symbol: "chart.bar.fill", tint: .orange) {
                Switch(isOn: $settings.showRecentStats)
            }
        }
    }

    private var compatibility: some View {
        @Bindable var settings = model.settings
        return VStack(alignment: .leading, spacing: 28) {
            GroupSection(title: Text("Claude Code compatibility"), footer: Text("When the main agent has replied but background agents haven't returned, the session stays running; it moves to review only after the last background agent returns and the main agent has handled its result. When off, every reply from the main agent counts as ready for review.")) {
                SettingRow(String(localized: "Wait for background agents (beta)"), symbol: "person.2.wave.2.fill", tint: .orange) {
                    Switch(isOn: $settings.claudeBackgroundAgents)
                        .onChange(of: settings.claudeBackgroundAgents) { _, on in if !on { model.forgetBackgroundTasks() } }
                }
            }
            GroupSection(title: Text(verbatim: "Wave Terminal · Tabby"), footer: Text("Allow YaaKanban in System Settings › Privacy & Security › Accessibility. You'll be asked on the first jump.")) {
                SettingRow(String(localized: "Switch to the matching tab when jumping"), symbol: "rectangle.stack.fill", tint: .teal) {
                    Switch(isOn: $settings.waveTabSwitching)
                }
            }
            GroupSection(title: Text("pi compatibility"), footer: Text("pi names a session only through /name. When on, an unnamed session gets a short title from the current model on its first message (one small extra model call per session), saved as pi's session name so /resume shows it too. Takes effect after you install or update the pi integration.")) {
                SettingRow(String(localized: "Generate session titles"), symbol: "character.cursor.ibeam", tint: .purple) {
                    Switch(isOn: $settings.piAutoTitle)
                }
            }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 28) {
            GroupSection(title: Text("General")) {
                SettingRow(String(localized: "Setup guide"), symbol: "list.bullet.clipboard.fill", tint: .indigo) {
                    Button("Open…") { AppWindows.open(.setup) }.buttonStyle(.action(size: .small))
                }
                SettingRow(String(localized: "Launch at login"), symbol: "power", tint: .gray) {
                    Switch(isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in
                            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                            catch { integrationMessage = String(localized: "Couldn't change the login item: \(error.localizedDescription)") }
                        }
                }
                SettingRow(String(localized: "Language"), symbol: "globe", tint: .blue) {
                    Picker(selection: Binding(get: { language ?? "" }, set: { language = $0.isEmpty ? nil : $0; AppLanguage.override = language })) {
                        Text("Follow system").tag("")
                        ForEach(AppLanguage.all, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                    } label: { Text("Language") }
                    .labelsHidden().fixedSize()
                }
                SettingRow(String(localized: "First day of the week"), detail: String(localized: "Where the overview's weeks start."), symbol: "calendar", tint: .red) {
                    Picker(selection: Binding(get: { model.settings.firstWeekday }, set: { model.settings.firstWeekday = $0 })) {
                        ForEach(Preferences.weekStarts, id: \.self) { Text(verbatim: Calendar.current.standaloneWeekdaySymbols[$0 - 1]).tag($0) }
                    } label: { Text("First day of the week") }
                    .labelsHidden().fixedSize()
                }
                // Trial, to go once a style is chosen; not localized.
                SettingRow("侧边栏样式（试用）", symbol: "sidebar.left", tint: .purple) {
                    Picker(selection: Binding(get: { model.settings.sidebarStyle }, set: { model.settings.sidebarStyle = $0 })) {
                        ForEach(SidebarHeadStyle.allCases, id: \.self) { Text(verbatim: $0.name).tag($0.rawValue) }
                    } label: { Text(verbatim: "侧边栏样式") }
                    .labelsHidden().fixedSize()
                }
                if language != AppLanguage.atLaunch {
                    SettingRow(String(localized: "Takes effect after YaaKanban restarts.")) {
                        Button("Restart Now") { AppLanguage.relaunch() }.buttonStyle(.action(.primary, size: .small))
                    }
                }
                message
            }
            GroupSection(title: Text("Privacy and feedback"), footer: Text(model.telemetry.doNotTrack ? "DO_NOT_TRACK is set, so no statistics are sent."
                     : !model.telemetry.available ? "This build has no statistics service configured and sends no data."
                     : "Off by default. When on, sends Aptabase one anonymous report a day: version, system, integration status, and rough ranges of feature use and session counts. No prompts, code, paths, project or session names. Command line: yaak telemetry status|on|off.")) {
                SettingRow(String(localized: "Send anonymous usage statistics"), symbol: "chart.line.uptrend.xyaxis", tint: .blue) {
                    Switch(isOn: Binding(get: { model.telemetry.isOn }, set: { model.telemetry.set(enabled: $0) }))
                        .disabled(!model.telemetry.available)
                }
                if model.telemetry.isOn {
                    SettingRow(String(localized: "Anonymous ID \(String(model.telemetry.installId?.prefix(8) ?? ""))…")) {
                        HStack(spacing: Space.s) {
                            Button("View") { FeedbackPrompt.show(title: String(localized: "Today's statistics (sent tomorrow)"), text: model.telemetry.preview()) }
                            Button("Reset") { model.telemetry.resetId() }
                        }
                        .buttonStyle(.action(size: .small))
                    }
                }
                SettingRow(String(localized: "Issues and ideas"), symbol: "bubble.left.fill", tint: .green) {
                    Button("Feedback…") { FeedbackPrompt.present(model) }.buttonStyle(.action(size: .small))
                }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 28) {
            AboutHeader()
            GroupSection(title: Text("Updates"), footer: Text(model.updater.available
                     ? "Updates come from GitHub Releases. A new version downloads in the background, then YaaKanban asks before installing it and restarting."
                     : "This build isn't signed for updates (built from source), so it doesn't update itself.")) {
                SettingRow(String(localized: "Check for updates automatically"), symbol: "arrow.down.circle.fill", tint: .blue) {
                    Switch(isOn: Binding(get: { model.updater.automatic }, set: { model.updater.automatic = $0 }))
                        .disabled(!model.updater.available)
                }
                SettingRow(updateStatus) {
                    if case .ready = model.updater.phase {
                        Button("Install and Restart") { model.updater.installReady() }.buttonStyle(.action(.primary, size: .small))
                    } else {
                        Button("Check Now") { Task { await model.updater.check(manual: true) } }.buttonStyle(.action(size: .small))
                            .disabled(!model.updater.available || model.updater.busy)
                    }
                }
            }
            GroupSection(title: Text("About")) {
                SettingRow(String(localized: "Version"), symbol: "shippingbox.fill", tint: .gray) {
                    HStack(spacing: Space.m) {
                        Text(AboutHeader.version).font(.ui(.callout)).foregroundStyle(.secondary)
                        if let v = model.updater.current { Link("What's New", destination: Updater.notes(for: v)).font(.ui(.callout)) }
                    }
                }
                SettingRow(String(localized: "License"), symbol: "doc.text.fill", tint: .gray) {
                    Text(verbatim: "GPL-3.0").font(.ui(.callout)).foregroundStyle(.secondary)
                }
                SettingRow(String(localized: "Source code"), symbol: "chevron.left.forwardslash.chevron.right", tint: .gray) {
                    Link(destination: AboutHeader.repo) { Text(verbatim: "github.com/ArtrixTech/YaaKanban") }.font(.ui(.callout))
                }
            }
            Text("© 2026 Artrix · Open source under GPL-3.0").font(.ui(.footnote)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: Helpers

extension SettingsView {
    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m < 60 { return String(localized: "\(m) min") }
        return m % 60 == 0 ? String(localized: "\(m / 60) h") : String(localized: "\(m / 60) h \(m % 60) min")
    }

    static var yaak: String { AppModel.yaakPath }

    private var updateStatus: String {
        switch model.updater.phase {
        case .idle: String(localized: "Not checked yet")
        case .checking: String(localized: "Checking…")
        case .downloading(let v): String(localized: "Downloading \(v)…")
        case .ready(let p): String(localized: "\(p.version) is ready to install")
        case .upToDate: String(localized: "Up to date")
        case .failed(let why): String(localized: "Couldn't update: \(why)")
        }
    }

    private func apply(_ i: any Integration, install: Bool) {
        integrationMessage = model.applyIntegration(i, install: install)
        refresh += 1
    }

    private func recheck() {
        model.checkIntegrations()
        refresh += 1
    }
}

/// A setting's value as a figure in a pill, with the stepper that changes it.
private struct Stepped: View {
    @Environment(\.settingTitle) private var settingTitle
    let text: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(_ text: String, value: Binding<Double>, in range: ClosedRange<Double>) {
        self.text = text; _value = value; self.range = range
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(verbatim: text).font(.ui(.callout, .medium).monospacedDigit())
                .padding(.horizontal, Space.m).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Fill.control))
            Stepper(settingTitle, value: $value, in: range).labelsHidden()
        }
    }
}

/// A setting's on/off switch, without a label of its own (the row has the title).
private struct Switch: View {
    @Environment(\.settingTitle) private var title
    @Binding var isOn: Bool
    var body: some View { Toggle(title, isOn: $isOn).switchStyle() }
}

/// Top of the About tab: logo, name, version, one-line pitch.
struct AboutHeader: View {
    static let repo = Feedback.repo
    static var version: String {
        let info = Bundle.main.infoDictionary
        guard let v = info?["CFBundleShortVersionString"] as? String else { return String(localized: "Development build") }
        return "\(v) (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(spacing: Space.s) {
            BrandMark(size: 64).shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            Text(verbatim: "YaaKanban").font(.ui(.title, .bold)).tracking(-0.2).padding(.top, Space.xs)
            Text("Version \(Self.version)").font(.ui(.footnote)).foregroundStyle(.secondary)
            Text("Keeps an eye on your coding agents: know the moment one finishes, gets stuck, or needs you.")
                .font(.ui(.callout)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
        .surface(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }
}

/// Numbered steps for authorizing hooks in the agent, under its row in Settings and the guide.
struct AuthorizationSteps: View {
    let integration: any Integration
    /// Agents with a desktop app and a CLI start on the app's steps.
    @State private var place = ApprovalPlace.app

    var body: some View {
        let steps = integration.pendingSteps(home: Paths.home(), in: place)
        VStack(alignment: .leading, spacing: Space.xxs) {
            if integration.approvesInEitherPlace {
                Segmented(items: [(item: ApprovalPlace.app, title: String(localized: "\(integration.agent.displayName) app")),
                                  (item: .terminal, title: String(localized: "Terminal"))], selection: $place)
                    .padding(.bottom, Space.xs)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { n, step in
                Text("\(n + 1). \(step)").font(.ui(.footnote)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Integration status as a badge.
struct StatusBadge: View {
    let status: IntegrationStatus

    var body: some View {
        switch status {
        case .installed: Badge(text: String(localized: "Installed"), tint: .green)
        case .outdated: Badge(text: String(localized: "Update available"), tint: .orange)
        case .needsAuthorization: Badge(text: String(localized: "Needs approval"), tint: .orange)
        case .notInstalled: Badge(text: String(localized: "Not installed"), tint: .secondary)
        case .notDetected: Badge(text: String(localized: "Not detected"), tint: .secondary)
        }
    }
}
