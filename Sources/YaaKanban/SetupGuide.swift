import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import YaaCore
import YaaIntegrations

/// First-run window in three steps: connect the agents, see each one report, then alerts and
/// preferences. Opens by itself on a first launch with nothing connected; the menu, the empty
/// panel and Settings open it again. Closing it at any step counts as done. Frameless: no title
/// bar or traffic lights, its own close button, dragged by the background.
struct SetupGuide: View {
    enum Step: Int, CaseIterable { case connect, verify, finish }
    static let id = "setup"
    static let size = NSSize(width: 560, height: 640)

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
    @State private var wantAccessibility = true
    /// Shown while the CLI was missing when the guide opened.
    @State private var offerCLI = !SetupGuide.cliLinked
    @State private var wantCLI = true
    @State private var shareStats = true
    @State private var closed = false
    /// False for `yaak snapshot` renders, which must not count as the user finishing the guide.
    private let live: Bool
    // Authorization happens in the agent or System Settings, out of our sight.
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(step: Step = .connect, live: Bool = true) { _step = State(initialValue: step); self.live = live }

    var body: some View {
        let _ = refresh
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    switch step {
                    case .connect: connect
                    case .verify: verify
                    case .finish: finish
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Backdrop())
        .background(FramelessWindow())
        .onReceive(poll) { _ in recheck() }
        .task(id: step) { await readPermissions() }
        .onAppear(perform: loadChoices)
        .onDisappear { if live, !closed { model.finishSetup() } }
        .onExitCommand { close(apply: false) }
    }
    // MARK: Parts

    private var topBar: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule().fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: s == step ? 22 : 8, height: 8)
            }
            Spacer()
            Button { close(apply: false) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain).help(String(localized: "Skip Setup"))
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            BrandMark(size: 52).shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .padding(.bottom, 6)
            Text("Step \(step.rawValue + 1) of 3").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 26, weight: .bold))
            Text(lead).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var title: String {
        switch step {
        case .connect: String(localized: "Connect your agents")
        case .verify: String(localized: "Check that they report")
        case .finish: String(localized: "Alerts and preferences")
        }
    }

    private var lead: String {
        switch step {
        case .connect: String(localized: "YaaKanban adds a small hook to each agent's own settings (a backup is kept), so the agent tells it when a session runs, finishes or needs you. Install it for the agents you use.")
        case .verify: String(localized: "Hooks load when a session starts. Open a new session in each agent and send one message; the agent is ticked here once its first event arrives. Sessions that were already running need a restart.")
        case .finish: String(localized: "Everything here can be changed later in Settings, which also opens this guide again.")
        }
    }

    /// Agents found on this Mac, or with our hooks still in place, with their status now.
    private var found: [(any Integration, IntegrationStatus)] {
        Integrations.all.map { ($0, $0.status(home: Paths.home(), yaak: AppModel.yaakPath)) }.filter { $0.1 != .notDetected }
    }

    private static func pending(_ s: IntegrationStatus) -> Bool { s == .notInstalled || s == .outdated }

    @ViewBuilder private var connect: some View {
        let list = found
        if list.isEmpty {
            Text("No supported agents found on this Mac. Install one (Claude Code, Codex, Cursor, OpenCode, pi and more are supported), then come back here.")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        } else {
            if list.contains(where: { Self.pending($0.1) }) {
                Button { installAll() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "link.circle.fill").font(.system(size: 30))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect All Agents").font(.system(size: 16, weight: .bold))
                            Text("Recommended · installs the hook in every agent below at once")
                                .font(.system(size: 11)).opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.gradient))
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(Pressable())
                .keyboardShortcut(.defaultAction)
            } else if list.allSatisfy({ $0.1 == .installed }) {
                banner(String(localized: "Every agent below is connected."), symbol: "checkmark.seal.fill", tint: .green)
            }
            card {
                ForEach(Array(list.enumerated()), id: \.element.0.agent) { n, item in
                    if n > 0 { Divider().padding(.leading, 56) }
                    connectRow(item.0, item.1)
                }
            }
        }
        if let message {
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connectRow(_ i: any Integration, _ status: IntegrationStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                agentLogo(i.agent)
                Text(i.agent.displayName).font(.system(size: 13, weight: .medium))
                Spacer()
                StatusBadge(status: status)
                switch status {
                case .notInstalled: Button("Install") { install(i) }.controlSize(.small)
                case .outdated: Button("Update") { install(i) }.controlSize(.small)
                default: EmptyView()
                }
            }
            if status == .needsAuthorization {
                AuthorizationSteps(steps: i.pendingSteps(home: Paths.home())).padding(.leading, 14)
            } else if status == .installed || status == .outdated, let note = i.postInstallNote {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 44)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func agentLogo(_ agent: AgentKind) -> some View {
        AgentLogo(agent: agent, size: 18)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
    @ViewBuilder private var verify: some View {
        let installed = found.filter { $0.1 != .notInstalled }
        if installed.isEmpty {
            Text("No agent is connected yet. Go back to install one, or skip this for now.")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        } else {
            let heard = model.connectedAgents
            card {
                ForEach(Array(installed.enumerated()), id: \.element.0.agent) { n, item in
                    if n > 0 { Divider().padding(.leading, 56) }
                    verifyRow(item.0, item.1, heard: heard.contains(item.0.agent))
                }
            }
            if installed.contains(where: { !heard.contains($0.0.agent) }) {
                Text("Still waiting after sending a message? Check that the agent trusts the folder you opened and that any approval it asks for is done. You can finish now; the tick appears whenever the first event arrives.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func verifyRow(_ i: any Integration, _ status: IntegrationStatus, heard: Bool) -> some View {
        let name = i.agent.displayName
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                agentLogo(i.agent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 13, weight: .medium))
                    if !heard {
                        Text(status == .needsAuthorization
                             ? String(localized: "Approve the hook in \(name) first (steps below).")
                             : String(localized: "No events yet. Open a new \(name) session and send a message."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Group {
                    if heard {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if status == .needsAuthorization {
                        Label("Needs approval", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Listening…").foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.system(size: 12, weight: .medium)).fixedSize()
            }
            if !heard, status == .needsAuthorization {
                AuthorizationSteps(steps: i.pendingSteps(home: Paths.home())).padding(.leading, 14)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    @ViewBuilder private var finish: some View {
        card {
            row(String(localized: "Notifications"), symbol: "bell.badge.fill", tint: .red,
                detail: notifications == false
                    ? String(localized: "Notifications are off for YaaKanban. Turn them on in System Settings, or you will miss done alerts and approval requests.")
                    : String(localized: "Alerts when a session finishes, gets stuck or needs you; approve or deny requests right from them.")) {
                switch notifications {
                case true?: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case false?:
                    Button("Open System Settings") {
                        openURL(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                    .buttonStyle(.borderedProminent)
                case nil: Button("Allow…") { askNotifications() }.buttonStyle(.borderedProminent)
                }
            }
            Divider().padding(.leading, 56)
            row(String(localized: "Launch at login"), symbol: "power", tint: .gray,
                detail: String(localized: "Keeps watching after a restart. Events from while it is closed are kept and shown later.")) {
                Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
            }
            Divider().padding(.leading, 56)
            row(String(localized: "Accessibility (optional)"), symbol: "accessibility", tint: .blue,
                detail: String(localized: "Lets a click on a card bring the agent's exact window or Wave tab to the front. Without it, YaaKanban only activates the app.")) {
                if accessibility {
                    Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Toggle("", isOn: $wantAccessibility).labelsHidden().toggleStyle(.switch)
                }
            }
            if offerCLI {
                Divider().padding(.leading, 56)
                row(String(localized: "Command line (optional)"), symbol: "terminal.fill", tint: .black,
                    detail: String(localized: "Links yaak to ~/.local/bin for yaak status, install and doctor.")) {
                    Toggle("", isOn: $wantCLI).labelsHidden().toggleStyle(.switch)
                }
            }
            if model.telemetry.available {
                Divider().padding(.leading, 56)
                row(String(localized: "Send anonymous usage statistics"), symbol: "chart.line.uptrend.xyaxis", tint: .blue,
                    detail: String(localized: "One report a day of versions, connected agents and rough usage ranges. Never prompts, code, paths or names. Change it any time in Settings.")) {
                    Toggle("", isOn: $shareStats).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private func row(_ title: String, symbol: String, tint: Color, detail: String,
                     @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing().controlSize(.small).font(.system(size: 12))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }

    private func banner(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(tint)
            Text(text).font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.12)))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .connect {
                Button("Back") { go(-1) }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            Spacer()
            if step != .finish {
                Button("Skip Setup") { close(apply: false) }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            Group {
                if step == .finish {
                    Button { close(apply: true) } label: { Text("Done").frame(minWidth: 84) }
                        .keyboardShortcut(.defaultAction)
                } else if step == .connect, found.contains(where: { Self.pending($0.1) }) {
                    // Return is the big connect button's; Continue stays a plain choice.
                    Button { go(1) } label: { Text("Continue").frame(minWidth: 84) }.buttonStyle(.bordered)
                } else {
                    Button { go(1) } label: { Text("Continue").frame(minWidth: 84) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
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
        if wantAccessibility, !accessibility {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    private func install(_ i: any Integration) {
        message = model.applyIntegration(i, install: true)
        refresh += 1
    }

    private func installAll() {
        let todo = found.filter { Self.pending($0.1) }.map(\.0)
        let failed = todo.compactMap { i -> String? in
            let m = model.applyIntegration(i, install: true)
            return Self.pending(i.status(home: Paths.home(), yaak: AppModel.yaakPath)) ? m : nil
        }
        message = failed.isEmpty
            ? String(localized: "Installed. Sessions you start from now on report to YaaKanban; restart ones already running.")
            : failed.joined(separator: "\n")
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

/// Presses in slightly, for a custom-drawn button.
private struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
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
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ v: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            w.styleMask.insert(.fullSizeContentView)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
        }
    }
}
