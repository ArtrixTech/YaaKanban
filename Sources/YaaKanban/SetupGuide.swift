import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import YaaCore
import YaaIntegrations

/// First-run window in three steps: connect the agents, see each one report, then alerts and
/// preferences. Opens by itself on a first launch with nothing connected; the menu, the empty
/// panel and Settings open it again. Closing it at any step counts as done.
struct SetupGuide: View {
    enum Step: Int, CaseIterable { case connect, verify, finish }
    static let id = "setup"
    static let size = NSSize(width: 540, height: 600)

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var step: Step
    @State private var refresh = 0
    @State private var message: String?
    /// nil until the user has been asked.
    @State private var notifications: Bool?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibility = AXIsProcessTrusted()
    /// Shown while the CLI was missing when the guide opened, so its result stays in view.
    @State private var offerCLI = !SetupGuide.cliLinked
    @State private var cliMessage: String?
    /// Starts from the current choice, so reopening the guide and pressing Done changes nothing.
    @State private var shareStats = false
    @State private var closed = false
    /// False for `yaak snapshot` renders, which must not count as the user finishing the guide.
    private let live: Bool
    // Authorization happens in the agent or System Settings, out of our sight.
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(step: Step = .connect, live: Bool = true) { _step = State(initialValue: step); self.live = live }

    var body: some View {
        let _ = refresh
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch step {
                    case .connect: connect
                    case .verify: verify
                    case .finish: finish
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onReceive(poll) { _ in recheck() }
        .task(id: step) { await readPermissions() }
        .onAppear { shareStats = model.telemetry.isOn }
        .onDisappear { if live, !closed { model.finishSetup() } }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 12) {
            BrandMark(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set Up YaaKanban").font(.system(size: 17, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: s == step ? 18 : 7, height: 7)
                }
            }
        }
        .padding(20)
    }

    private var subtitle: String {
        switch step {
        case .connect: String(localized: "Step 1 of 3 · Connect your agents")
        case .verify: String(localized: "Step 2 of 3 · Check that they report")
        case .finish: String(localized: "Step 3 of 3 · Alerts and preferences")
        }
    }

    /// Agents found on this Mac, or with our hooks still in place, with their status now.
    private var found: [(any Integration, IntegrationStatus)] {
        Integrations.all.map { ($0, $0.status(home: Paths.home(), yaak: AppModel.yaakPath)) }.filter { $0.1 != .notDetected }
    }

    @ViewBuilder private var connect: some View {
        Text("YaaKanban adds a small hook to each agent's own settings (a backup is kept), so the agent tells it when a session runs, finishes or needs you. Install it for the agents you use.")
            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        let list = found
        if list.isEmpty {
            Text("No supported agents found on this Mac. Install one (Claude Code, Codex, Cursor, OpenCode, pi and more are supported), then come back here.")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        } else {
            if list.contains(where: { $0.1 == .notInstalled || $0.1 == .outdated }) {
                Button("Install All") { installAll() }.buttonStyle(.borderedProminent)
            }
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.0.agent) { n, item in
                    if n > 0 { Divider() }
                    connectRow(item.0, item.1)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
        if let message {
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connectRow(_ i: any Integration, _ status: IntegrationStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                agentLabel(i.agent)
                Spacer()
                StatusBadge(status: status)
                switch status {
                case .notInstalled: Button("Install") { install(i) }.controlSize(.small)
                case .outdated: Button("Update") { install(i) }.controlSize(.small)
                default: EmptyView()
                }
            }
            if status == .needsAuthorization {
                AuthorizationSteps(steps: i.pendingSteps(home: Paths.home()))
            } else if status == .installed || status == .outdated, let note = i.postInstallNote {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 30)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func agentLabel(_ agent: AgentKind) -> some View {
        HStack(spacing: 8) {
            AgentLogo(agent: agent, size: 16)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
            Text(agent.displayName)
        }
    }

    @ViewBuilder private var verify: some View {
        Text("Agents load hooks when a session starts. Open a new session in each agent and send it a message; it is ticked here as soon as YaaKanban hears from it, and its card appears on the floating panel. Restart sessions that were already running.")
            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        let installed = found.filter { $0.1 != .notInstalled }
        if installed.isEmpty {
            Text("No agent is connected yet. Go back to install one, or skip this for now.")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        } else {
            let heard = model.connectedAgents
            VStack(spacing: 0) {
                ForEach(Array(installed.enumerated()), id: \.element.0.agent) { n, item in
                    if n > 0 { Divider() }
                    verifyRow(item.0, item.1, heard: heard.contains(item.0.agent))
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            if installed.contains(where: { !heard.contains($0.0.agent) }) {
                Text("Nothing yet? Check that the session was started after installing, that the agent trusts the folder you opened, and that any approval it asks for is done. You can finish now; it is ticked whenever the first event arrives.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func verifyRow(_ i: any Integration, _ status: IntegrationStatus, heard: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                agentLabel(i.agent)
                Spacer()
                if heard {
                    Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if status == .needsAuthorization {
                    Label("Needs approval", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for a session…").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 12))
            if !heard, status == .needsAuthorization {
                AuthorizationSteps(steps: i.pendingSteps(home: Paths.home()))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    @ViewBuilder private var finish: some View {
        row(String(localized: "Notifications"), symbol: "bell.badge.fill", tint: .red,
            detail: String(localized: "Alerts when a session finishes, gets stuck or needs you; approve or deny requests right from them.")) {
            switch notifications {
            case true?: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case false?:
                Button("Open System Settings") {
                    openURL(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                }
            case nil: Button("Allow…") { model.notifier.requestAuthorization() }.buttonStyle(.borderedProminent)
            }
        }
        row(String(localized: "Launch at login"), symbol: "power", tint: .gray,
            detail: String(localized: "Keeps watching after a restart. Events from while it is closed are kept and shown later.")) {
            Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch {
                        cliMessage = String(localized: "Couldn't change the login item: \(error.localizedDescription)")
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        row(String(localized: "Accessibility (optional)"), symbol: "accessibility", tint: .blue,
            detail: String(localized: "Lets a click on a card bring the agent's exact window or Wave tab to the front. Without it, YaaKanban only activates the app.")) {
            if accessibility {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Allow…") {
                    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                }
            }
        }
        if offerCLI {
            row(String(localized: "Command line (optional)"), symbol: "terminal.fill", tint: .black,
                detail: String(localized: "Links yaak to ~/.local/bin for yaak status, install and doctor.")) {
                if Self.cliLinked {
                    Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Install") { linkCLI() }
                }
            }
        }
        if model.telemetry.available {
            row(String(localized: "Send anonymous usage statistics"), symbol: "chart.line.uptrend.xyaxis", tint: .blue,
                detail: String(localized: "One report a day of versions, connected agents and rough usage ranges. Never prompts, code, paths or names. Change it any time in Settings.")) {
                Toggle("", isOn: $shareStats).labelsHidden().toggleStyle(.switch)
            }
        }
        if let cliMessage {
            Text(cliMessage).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Text("Everything here can be changed later in Settings, which also opens this guide again.")
            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ title: String, symbol: String, tint: Color, detail: String,
                     @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                SettingLabel(title, symbol: symbol, tint: tint)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 30)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing().controlSize(.small).font(.system(size: 12))
        }
    }

    private var footer: some View {
        HStack {
            if step != .connect {
                Button("Back") { go(-1) }
            }
            Spacer()
            if step == .finish {
                Button("Done") { close(applyStats: true) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                Button("Skip Setup") { close(applyStats: false) }
                Button("Continue") { go(1) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: Actions

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.snappy) { step = next }
    }

    /// Done applies the statistics choice; skipping leaves it to the usual question next launch.
    private func close(applyStats: Bool) {
        if applyStats, model.telemetry.available { model.telemetry.set(enabled: shareStats) }
        closed = true
        model.finishSetup()
        dismiss()
    }

    private func install(_ i: any Integration) {
        message = model.applyIntegration(i, install: true)
        refresh += 1
    }

    private func installAll() {
        let todo = found.filter { $0.1 == .notInstalled || $0.1 == .outdated }.map(\.0)
        let failed = todo.compactMap { i -> String? in
            let m = model.applyIntegration(i, install: true)
            let s = i.status(home: Paths.home(), yaak: AppModel.yaakPath)
            return s == .notInstalled || s == .outdated ? m : nil
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

    private func readPermissions() async {
        notifications = await model.notifier.isAuthorized()
    }

    // MARK: Command line

    static var cliLink: URL { Paths.home().appendingPathComponent(".local/bin/yaak") }
    static var cliLinked: Bool { FileManager.default.fileExists(atPath: cliLink.path) }

    private func linkCLI() {
        let fm = FileManager.default, link = Self.cliLink
        do {
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            // A link left dangling by a moved app is replaced; a real file there is not ours.
            if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil { try fm.removeItem(at: link) }
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: AppModel.yaakPath)
            cliMessage = String(localized: "Linked \(link.path). If yaak isn't found, add ~/.local/bin to your PATH.")
        } catch {
            cliMessage = String(localized: "Couldn't link yaak: \(error.localizedDescription)")
        }
        refresh += 1
    }
}
