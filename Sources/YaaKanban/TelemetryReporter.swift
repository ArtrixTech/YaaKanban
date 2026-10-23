import AppKit
import Foundation
import Observation
import ServiceManagement
import YaaCore
import YaaIntegrations

/// Sends the opt-in daily reports to TelemetryDeck (spec §6). Counts go to the ledger file as they
/// happen; once a local day is over its report is built and sent once, whether or not the send
/// succeeds.
@MainActor @Observable
final class TelemetryReporter {
    private let url: URL
    /// Mirrors the ledger (which `yaak telemetry` may change too) for the settings toggle.
    private(set) var enabled: Bool
    private(set) var installId: String?
    /// TelemetryDeck App ID from Info.plist; nil means this build cannot send.
    let appID: String?
    let doNotTrack: Bool
    private let ingestURL: URL
    /// Builds the report for a finished day from its counts.
    @ObservationIgnored var build: ((_ day: String, _ counts: [String: Int], _ installId: String) -> TelemetryReport?)?
    /// The day already marked in the ledger by this launch.
    @ObservationIgnored private var noted: String?

    private static let session = URLSession(configuration: .ephemeral)

    init(paths: Paths, bundle: Bundle = .main, env: [String: String] = ProcessInfo.processInfo.environment) {
        url = paths.telemetry
        // Defaults overrides, for trying an App ID or a local capture server without rebuilding.
        let raw = UserDefaults.standard.string(forKey: Telemetry.appIDKey)
            ?? bundle.object(forInfoDictionaryKey: Telemetry.appIDKey) as? String ?? ""
        appID = raw.isEmpty ? nil : raw
        ingestURL = UserDefaults.standard.string(forKey: "YaakTelemetryIngestURL").flatMap(URL.init(string:))
            ?? TelemetryDeckSignal.ingestURL
        doNotTrack = Telemetry.doNotTrack(env)
        let l = TelemetryLedger.load(url)
        enabled = l.enabled
        installId = l.installId
    }

    /// This build has somewhere to send to, and the user's environment does not forbid it.
    var available: Bool { appID != nil && !doNotTrack }
    var isOn: Bool { enabled && available }

    func set(enabled on: Bool) {
        apply(TelemetryLedger.update(url) { $0.set(enabled: on) })
        noted = nil
        tick()
    }

    func resetId() { apply(TelemetryLedger.update(url) { $0.resetId() }) }

    func count(_ event: TelemetryEvent, by n: Int = 1) {
        guard isOn, n > 0 else { return }
        let day = Telemetry.dayKey(Date())
        TelemetryLedger.update(url) { $0.note(event, by: n, day: day) }
    }

    /// Called on the app's tick: follows CLI changes, marks today, and sends finished days once.
    func tick(now: Date = Date()) {
        var l = TelemetryLedger.load(url)
        apply(l)
        let day = Telemetry.dayKey(now)
        guard isOn, noted != day else { return }
        noted = day
        // One locked update, so a `yaak telemetry off` cannot slip between reading and marking sent.
        var due: [(day: String, counts: [String: Int])] = []
        var id: String?
        TelemetryLedger.update(url) { l in
            guard l.enabled else { return }
            l.note(day: day)
            let p = l.pending(today: day)
            guard let last = p.last else { return }
            due = p.map { ($0, l.days[$0] ?? [:]) }
            id = l.installId
            l.sent(through: last)
        }
        guard let id, let appID else { return }
        let signals = due.compactMap { d in build?(d.day, d.counts, id).map { signal($0, appID: appID) } }
        guard !signals.isEmpty else { return }
        var req = URLRequest(url: ingestURL, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = TelemetryDeckSignal.body(signals)
        Self.session.dataTask(with: req).resume()
    }

    /// Debug builds mark their signals as test data (TelemetryDeck's Test Mode).
    private func signal(_ r: TelemetryReport, appID: String) -> TelemetryDeckSignal {
        #if DEBUG
        TelemetryDeckSignal(report: r, appID: appID, testMode: true)
        #else
        TelemetryDeckSignal(report: r, appID: appID)
        #endif
    }

    /// Today's report so far; setup and settings are as of now, as they would be at send time.
    func preview() -> String {
        let l = TelemetryLedger.load(url)
        let day = Telemetry.dayKey(Date())
        guard let r = build?(day, l.days[day] ?? [:], l.installId ?? "—") else { return "" }
        return String(decoding: TelemetryDeckSignal.body([signal(r, appID: appID ?? "—")], pretty: true), as: UTF8.self)
    }

    private func apply(_ l: TelemetryLedger) {
        // Turned off and on again (say from `yaak`) since this launch marked today: mark it again.
        if enabled != l.enabled { enabled = l.enabled; noted = nil }
        if installId != l.installId { installId = l.installId }
    }

    /// Asks once, a moment after the first launch of a build that can send.
    func askIfNeeded() {
        guard available, !TelemetryLedger.load(url).asked else { return }
        let alert = NSAlert()
        if let icon = BrandMark.image { alert.icon = icon }
        alert.messageText = "帮助改进 YaaKanban？"
        alert.informativeText = "开启后，YaaKanban 每天向 TelemetryDeck 发送一份匿名使用统计：版本、系统、已接入哪些 agent、各功能的使用次数，以及会话数等粗略区间。不含 prompt、代码、路径、项目或会话名。随时可在 设置 › 隐私与反馈 关闭，或查看将要发送的内容。"
        alert.addButton(withTitle: "开启")
        alert.addButton(withTitle: "不用了")
        NSApp.activate(ignoringOtherApps: true)
        set(enabled: alert.runModal() == .alertFirstButtonReturn)
    }
}

extension AppModel {
    /// The report for `day`: environment and setup now, the day's counts and coarse figures.
    func telemetryReport(day: String, counts: [String: Int], installId: String) -> TelemetryReport? {
        guard let range = Telemetry.interval(ofDay: day) else { return nil }
        let r = report(range, buckets: 24)
        var f = TelemetryFigures(sessions: Array(sessions.values), day: range)
        f.agentHours = r.agentTime / 3600
        f.parallelPeak = r.parallelPeak
        f.leverage = r.leverage
        let home = Paths.home()
        let s = settings
        let flags: [TelemetrySetting: Bool] = [
            .showPanel: s.showPanel, .slimRail: s.slimRail, .showRecentStats: s.showRecentStats,
            .flash: s.flashEnabled, .reviewFlash: s.reviewFlashEnabled, .staleTint: s.staleTintEnabled,
            .waveTabSwitching: s.waveTabSwitching, .piAutoTitle: s.piAutoTitle,
            .launchAtLogin: SMAppService.mainApp.status == .enabled,
        ]
        return Telemetry.makeReport(installId: installId, day: day, env: .current(),
                                    integrations: Dictionary(uniqueKeysWithValues: Integrations.all.map {
                                        ($0.agent, $0.status(home: home, yaak: SettingsView.yaak).rawValue)
                                    }),
                                    settings: flags, counts: counts, figures: f)
    }

    func diagnostics() -> Diagnostics {
        Diagnostics.gather(paths: paths, home: Paths.home(), yaak: SettingsView.yaak, env: .current(),
                           appListening: serverError == nil, telemetry: telemetry.isOn)
    }
}
