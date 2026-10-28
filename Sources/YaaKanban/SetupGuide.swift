import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import YaaCore
import YaaIntegrations

/// First-run window in two steps: connect the agents (each one is ticked once its first event
/// arrives, whenever that is), then alerts and preferences. Opens by itself on a first launch with
/// nothing connected; the menu, the empty panel and Settings open it again. Closing it at any step
/// counts as done. Frameless: no title bar or traffic lights, its own close button, dragged by the
/// background. The page itself never scrolls; only the agent list does. While it is open the app
/// shows in the Dock and the app switcher, so the user can get back to it after going to an agent.
/// What the user does elsewhere (approving hooks, permissions) is read again when they come back.
struct SetupGuide: View {
    enum Step: Int, CaseIterable { case connect, finish }
    static let id = "setup"
    static let size = NSSize(width: 560, height: 600)

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var step: Step
    @State private var refresh = 0
    @State private var message: String?
    /// nil until the user has been asked.
    @State private var notifications: Bool?
    @State private var askedNotifications = false
    // The last step's choices start on and apply on Done; the user turns off what they don't want.
    @State private var launchAtLogin = true
    @State private var accessibility = AXIsProcessTrusted()
    /// Shown while the CLI was missing when the guide opened.
    @State private var offerCLI = !SetupGuide.cliLinked
    @State private var wantCLI = true
    @State private var shareStats = true
    @State private var closed = false
    /// Agents still waiting for approval when the user pressed Continue.
    @State private var unapproved: [String] = []
    /// The hidden title bar's height, which the window adds on top of the content.
    @State private var titleBar: CGFloat = 0
    /// False for `yaak snapshot` renders, which must not count as the user finishing the guide.
    private let live: Bool

    init(step: Step = .connect, live: Bool = true) { _step = State(initialValue: step); self.live = live }

    var body: some View {
        let _ = refresh
        VStack(alignment: .leading, spacing: 16) {
            header
            switch step {
            case .connect: connect
            case .finish: finish
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .ignoresSafeArea()
        // The content draws under the title bar, but the window still sizes itself to content + bar.
        .frame(height: Self.size.height - titleBar, alignment: .bottom)
        .background(Backdrop())
        .background(FramelessWindow(titleBar: $titleBar))
        .onComeBack(perform: recheck)
        .task(id: step) { await readPermissions() }
        .onAppear {
            loadChoices()
            if live { NSApp.setActivationPolicy(.regular); NSApp.activate() }
        }
        .onDisappear {
            guard live else { return }
            NSApp.setActivationPolicy(.accessory)
            if !closed { model.finishSetup() }
        }
        .onExitCommand { close(apply: false) }
    }

    // MARK: Parts

    /// Logo and title on the left, progress and close on the right, the lead underneath.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                BrandMark(size: 44).shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                Text(title).font(.ui(.display, .bold)).tracking(-0.3)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Step.allCases, id: \.self) { s in
                        Capsule().fill(s.rawValue <= step.rawValue ? Color.accentColor : Fill.controlHover)
                            .frame(width: s == step ? 22 : 8, height: 8)
                    }
                }
                Button { close(apply: false) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Fill.control))
                }
                .buttonStyle(.plain).help(String(localized: "Skip Setup")).padding(.leading, 6)
            }
            Text(lead).font(.ui(.body)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        switch step {
        case .connect: String(localized: "Connect your agents")
        case .finish: String(localized: "Alerts and preferences")
        }
    }

    private var lead: String {
        switch step {
        case .connect: String(localized: "YaaKanban adds a small hook to each agent's own settings (a backup is kept), so the agent tells it when a session runs, finishes or needs you. Install it for the agents you use.")
        case .finish: String(localized: "Everything here can be changed later in Settings, which also opens this guide again.")
        }
    }

    /// Agents found on this Mac, or with our hooks still in place, with their status now. Those
    /// waiting for the user's approval come first, so their steps are not below the fold.
    private var found: [(any Integration, IntegrationStatus)] {
        let all = Integrations.all.map { ($0, $0.status(home: Paths.home(), yaak: AppModel.yaakPath)) }.filter { $0.1 != .notDetected }
        return all.filter { $0.1 == .needsAuthorization } + all.filter { $0.1 != .needsAuthorization }
    }

    private static func pending(_ s: IntegrationStatus) -> Bool { s == .notInstalled || s == .outdated }

    @ViewBuilder private var connect: some View {
        let list = found, heard = model.connectedAgents
        if list.isEmpty {
            Text("No supported agents found on this Mac. Install one (Claude Code, Codex, Cursor, OpenCode, pi and more are supported), then come back here.")
                .font(.ui(.body)).fixedSize(horizontal: false, vertical: true)
        } else {
            if list.contains(where: { Self.pending($0.1) }) {
                Button { installAll() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "link.circle.fill").font(.system(size: 28))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect All Agents").font(.system(size: 16, weight: .bold))
                            Text("Recommended · installs the hook in every agent below at once")
                                .font(.system(size: 11)).opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Plate(shape: RoundedRectangle(cornerRadius: Radius.group, style: .continuous), tint: .accentColor))
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 3)
                }
                .buttonStyle(Pressable())
                .keyboardShortcut(.defaultAction)
            } else if list.allSatisfy({ heard.contains($0.0.agent) }) {
                Banner(String(localized: "Every agent below is connected."), symbol: "checkmark.seal.fill", tint: .green)
            }
            // Only the list scrolls; it sits on the page with no card around it.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(list, id: \.0.agent) { item in
                        connectRow(item.0, item.1, heard: heard.contains(item.0.agent))
                    }
                }
                .padding(.vertical, Space.s)
            }
            .scrollIndicators(.automatic)
            // Rows fade out at both edges instead of being cut.
            .mask(VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom).frame(height: 18)
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 24)
            })
            .frame(maxHeight: .infinity)
            // Said once for every row still waiting, instead of under each.
            if list.contains(where: { Self.waiting($0.1, heard: heard.contains($0.0.agent)) }) {
                Text("An agent is ticked by itself the next time you use it. Sessions already running need a restart.")
                    .font(.ui(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        if let message {
            Text(message).font(.ui(.footnote)).foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One agent from install to its first event: Install → Installed (waiting) → Connected.
    private func connectRow(_ i: any Integration, _ status: IntegrationStatus, heard: Bool) -> some View {
        let waiting = Self.waiting(status, heard: heard)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Space.l) {
                LogoTile(agent: i.agent)
                Text(i.agent.displayName).font(.ui(.body, .medium))
                Spacer(minLength: Space.m)
                switch status {
                case .notInstalled: Button("Install") { install(i) }.buttonStyle(.action(.secondary, tint: .accentColor))
                case .outdated: Button("Update") { install(i) }.buttonStyle(.action(.secondary, tint: .accentColor))
                case .needsAuthorization:
                    Badge(text: String(localized: "Needs approval"), symbol: "exclamationmark.circle.fill", tint: .orange)
                default:
                    if heard {
                        Badge(text: String(localized: "Connected"), symbol: "checkmark.circle.fill", tint: .green)
                    } else {
                        Badge(text: String(localized: "Waiting for first use"), symbol: "clock", tint: .secondary)
                    }
                }
            }
            if status == .needsAuthorization {
                AuthorizationSteps(integration: i).padding(.leading, 14)
            } else if waiting, let note = i.postInstallNote {
                Text(note).font(.ui(.footnote)).foregroundStyle(.secondary).padding(.leading, 44)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Space.m)
    }

    /// Installed, and not heard from yet.
    private static func waiting(_ s: IntegrationStatus, heard: Bool) -> Bool { !heard && s == .installed }

    @ViewBuilder private var finish: some View {
        GroupCard {
            SettingRow(String(localized: "Notifications"),
                       detail: notifications == false
                           ? String(localized: "Notifications are off for YaaKanban. Turn them on in System Settings, or you will miss done alerts and approval requests.")
                           : String(localized: "Alerts when a session finishes, gets stuck or needs you; approve or deny requests right from them."),
                       symbol: "bell.badge.fill", tint: .red) {
                switch notifications {
                case true?: Badge(text: String(localized: "Allowed"), symbol: "checkmark.circle.fill", tint: .green)
                case false?:
                    Button("Open System Settings") {
                        // The system asks only once; after a "Don't Allow", go straight to this app's own page.
                        let id = Bundle.main.bundleIdentifier ?? "com.artrix.yaakanban"
                        openURL(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!)
                    }
                    .buttonStyle(.action(.primary))
                case nil: Button("Allow…") { askNotifications() }.buttonStyle(.action(.primary))
                }
            }
            SettingRow(String(localized: "Launch at login"),
                       detail: String(localized: "Keeps watching after a restart. Events from while it is closed are kept and shown later."),
                       symbol: "power", tint: .gray) {
                Toggle("", isOn: $launchAtLogin).switchStyle()
            }
            SettingRow(String(localized: "Accessibility (optional)"),
                       detail: String(localized: "Lets a click on a card bring the agent's exact window or Wave tab to the front. Without it, YaaKanban only activates the app."),
                       symbol: "accessibility", tint: .blue) {
                if accessibility {
                    Badge(text: String(localized: "Allowed"), symbol: "checkmark.circle.fill", tint: .green)
                } else {
                    // Asked here, next to its reason, not later when a card is clicked.
                    Button("Allow…") { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
                        .buttonStyle(.action(.primary))
                }
            }
            if offerCLI {
                SettingRow(String(localized: "Command line (optional)"),
                           detail: String(localized: "Links yaak to ~/.local/bin for yaak status, install and doctor."),
                           symbol: "terminal.fill", tint: .black) {
                    Toggle("", isOn: $wantCLI).switchStyle()
                }
            }
            if model.telemetry.available {
                SettingRow(String(localized: "Send anonymous usage statistics"),
                           detail: String(localized: "One report a day of versions, connected agents and rough usage ranges. Never prompts, code, paths or names. Change it any time in Settings."),
                           symbol: "chart.line.uptrend.xyaxis", tint: .blue) {
                    Toggle("", isOn: $shareStats).switchStyle()
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .connect {
                Button("Back") { go(-1) }.buttonStyle(.action(.ghost))
            }
            Spacer()
            if step != .finish {
                Button("Skip Setup") { close(apply: false) }.buttonStyle(.action(.ghost))
            }
            if step == .finish {
                Button("Done") { close(apply: true) }
                    .buttonStyle(.action(.primary, size: .large)).keyboardShortcut(.defaultAction)
            } else if step == .connect, found.contains(where: { Self.pending($0.1) }) {
                // Return is the big connect button's; Continue stays a plain choice.
                Button("Continue") { proceed() }.buttonStyle(.action(.secondary, size: .large))
            } else {
                Button("Continue") { proceed() }
                    .buttonStyle(.action(.primary, size: .large)).keyboardShortcut(.defaultAction)
            }
        }
        .alert(String(localized: "Still needs approval"), isPresented: Binding(get: { !unapproved.isEmpty }, set: { if !$0 { unapproved = [] } })) {
            Button("Not Yet", role: .cancel) {}
            Button("Continue Anyway") { go(1) }
        } message: {
            Text("\(ListFormatter.localizedString(byJoining: unapproved)) won’t report to YaaKanban until you approve its hooks.")
        }
    }

    /// Leaving the agents step with some still unapproved asks first; Skip Setup does not.
    private func proceed() {
        if step == .connect {
            unapproved = found.filter { $0.1 == .needsAuthorization }.map(\.0.agent.displayName)
            if !unapproved.isEmpty { return }
        }
        go(1)
    }

    // MARK: Actions

    /// First run starts every choice on; a reopened guide shows what is set now.
    private func loadChoices() {
        if model.settings.setupDone {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            shareStats = model.telemetry.isOn
        } else {
            // A "no" given before (CLI or Settings) stands.
            shareStats = model.telemetry.isOn || !model.telemetry.asked
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.snappy) { step = next }
    }

    /// Done applies the last step's choices; skipping or closing leaves everything as it is.
    private func close(apply: Bool) {
        if apply { applyChoices() }
        closed = true
        model.finishSetup()
        dismiss()
    }

    private func applyChoices() {
        let service = SMAppService.mainApp
        if launchAtLogin != (service.status == .enabled) {
            if launchAtLogin { try? service.register() } else { try? service.unregister() }
        }
        if offerCLI, wantCLI, !Self.cliLinked { linkCLI() }
        if model.telemetry.available { model.telemetry.set(enabled: shareStats) }
    }

    /// Only a failure is said here; the row shows the rest (its badge, or the steps left to do).
    private func install(_ i: any Integration) {
        let m = model.applyIntegration(i, install: true)
        message = Self.pending(i.status(home: Paths.home(), yaak: AppModel.yaakPath)) ? m : nil
        refresh += 1
    }

    private func installAll() {
        let todo = found.filter { Self.pending($0.1) }.map(\.0)
        let failed = todo.compactMap { i -> String? in
            let m = model.applyIntegration(i, install: true)
            return Self.pending(i.status(home: Paths.home(), yaak: AppModel.yaakPath)) ? m : nil
        }
        message = failed.isEmpty ? nil : failed.joined(separator: "\n")
        refresh += 1
    }

    private func recheck() {
        model.checkIntegrations()
        accessibility = AXIsProcessTrusted()
        if step == .finish { Task { await readPermissions() } }
        refresh += 1
    }

    /// On the last step, the system prompt comes up by itself the first time, next to its reason.
    private func readPermissions() async {
        notifications = await model.notifier.isAuthorized()
        if live, step == .finish, notifications == nil, !askedNotifications { askNotifications() }
    }

    private func askNotifications() {
        askedNotifications = true
        model.notifier.requestAuthorization { _ in
            Task { @MainActor in refresh += 1 }
        }
    }

    // MARK: Command line

    static var cliLink: URL { Paths.home().appendingPathComponent(".local/bin/yaak") }
    static var cliLinked: Bool { FileManager.default.fileExists(atPath: cliLink.path) }

    private func linkCLI() {
        let fm = FileManager.default, link = Self.cliLink
        try? fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A link left dangling by a moved app is replaced; a real file there is not ours.
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil { try? fm.removeItem(at: link) }
        try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: AppModel.yaakPath)
    }
}

/// Translucent window background with a faint accent glow at the top.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            Blur()
            LinearGradient(colors: [Color.accentColor.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    private struct Blur: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let v = NSVisualEffectView()
            v.material = .sidebar
            v.blendingMode = .behindWindow
            v.state = .active
            return v
        }
        func updateNSView(_ v: NSVisualEffectView, context: Context) {}
    }
}

/// Turns the hosting window frameless: content under a transparent, empty title bar, no traffic
/// lights, movable by its background. Keeps `.titled` so it still takes key and keeps its corners.
private struct FramelessWindow: NSViewRepresentable {
    @Binding var titleBar: CGFloat

    func makeNSView(context: Context) -> NSView { let p = Probe(); p.report = { titleBar = $0 }; return p }
    func updateNSView(_ v: NSView, context: Context) {}

    private final class Probe: NSView {
        var report: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            // Only a window that grows to fit its content (the scene) adds the bar; snapshot ones are fixed.
            if w.identifier != nil {
                let bar = w.frame.height - w.contentLayoutRect.height
                DispatchQueue.main.async { [report] in report?(bar) }
            }
            w.styleMask.insert(.fullSizeContentView)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
        }
    }
}
