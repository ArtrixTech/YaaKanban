import AppKit
import Foundation
import Observation
import ServiceManagement
import YaaCore
import YaaIntegrations

/// Sends the opt-in daily reports to Aptabase (spec §6). Counts go to the ledger file as they
/// happen; once a local day is over its report is built and sent once, whether or not the send
/// succeeds.
@MainActor @Observable
final class TelemetryReporter {
    private let url: URL
    /// Mirrors the ledger (which `yaak telemetry` may change too) for the settings toggle.
    private(set) var enabled: Bool
    private(set) var installId: String?
    /// Aptabase App Key from Info.plist; nil means this build cannot send.
    let appKey: String?
    let doNotTrack: Bool
    private let ingestURL: URL?
    /// Builds the report for a finished day from its counts.
    @ObservationIgnored var build: ((_ day: String, _ counts: [String: Int], _ installId: String) -> TelemetryReport?)?
    /// The day already marked in the ledger by this launch.
    @ObservationIgnored private var noted: String?

    /// Waits for a network rather than failing at once: the first tick of a new day is often just
    /// after waking, before Wi-Fi is back, and a failed send is dropped (spec §6).
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.waitsForConnectivity = true
        c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c)
    }()

    init(paths: Paths, bundle: Bundle = .main, env: [String: String] = ProcessInfo.processInfo.environment) {
        url = paths.telemetry
        // Defaults overrides, for trying an App Key or a local capture server without rebuilding.
        let raw = UserDefaults.standard.string(forKey: Telemetry.appKeyKey)
            ?? bundle.object(forInfoDictionaryKey: Telemetry.appKeyKey) as? String ?? ""
        appKey = raw.isEmpty ? nil : raw
        ingestURL = UserDefaults.standard.string(forKey: "YaakTelemetryIngestURL").flatMap(URL.init(string:))
            ?? AptabaseEvent.ingestURL(appKey: raw)
        doNotTrack = Telemetry.doNotTrack(env)
        let l = TelemetryLedger.load(url)
        enabled = l.enabled
        installId = l.installId
    }

    /// This build has somewhere to send to, and the user's environment does not forbid it.
    var available: Bool { appKey != nil && ingestURL != nil && !doNotTrack }
    var isOn: Bool { enabled && available }
    /// The user has answered once, here, in Settings or from the CLI.
    var asked: Bool { TelemetryLedger.load(url).asked }

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
        guard let id, let appKey, let ingestURL else { return }
        // At most 7 days are pending, well under Aptabase's batch limit; keep the newest regardless.
        let events = due.compactMap { d in build?(d.day, d.counts, id).map(event) }.suffix(AptabaseEvent.maxBatch)
        guard let first = events.first else { return }
        var req = URLRequest(url: ingestURL, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(appKey, forHTTPHeaderField: "App-Key")
        // As the SDK sends it; Aptabase hashes it into the day's anonymous user.
        let sys = first.systemProps
        req.setValue("\(sys.osName)/\(sys.osVersion) \(sys.locale)", forHTTPHeaderField: "User-Agent")
        req.httpBody = AptabaseEvent.body(Array(events))
        let ledger = url, days = due.map(\.day)
        Self.session.dataTask(with: req) { _, response, error in
            let result = TelemetryLedger.SendResult(at: Date(), days: days, response: response, error: error)
            TelemetryLedger.update(ledger) { l in if l.enabled { l.lastResult = result } }
        }.resume()
    }

    /// Debug builds mark their events as debug data (Aptabase's Debug/Release switch).
    private func event(_ r: TelemetryReport) -> AptabaseEvent {
        #if DEBUG
        AptabaseEvent(report: r, debug: true)
        #else
        AptabaseEvent(report: r)
        #endif
    }

    /// Today's report so far; setup and settings are as of now, as they would be at send time.
    func preview() -> String {
        let l = TelemetryLedger.load(url)
        let day = Telemetry.dayKey(Date())
        guard let r = build?(day, l.days[day] ?? [:], l.installId ?? "—") else { return "" }
        return String(decoding: AptabaseEvent.body([event(r)], pretty: true), as: UTF8.self)
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
        alert.messageText = String(localized: "Help improve YaaKanban?")
        alert.informativeText = String(localized: "When on, YaaKanban sends Aptabase one anonymous usage report a day: version, system, which agents are connected, how often each feature is used, and rough ranges such as the number of sessions. It never includes prompts, code, paths, or project or session names. Turn it off or see what will be sent any time in Settings › Privacy and feedback.")
        alert.addButton(withTitle: String(localized: "Turn On"))
        alert.addButton(withTitle: String(localized: "No Thanks"))
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
