import Foundation

/// Opt-in anonymous usage telemetry (spec §6): what may be counted, the daily report, and the
/// local ledger behind it. Only the app sends; this file has no networking.
public enum TelemetryEvent: String, Codable, CaseIterable, Sendable {
    case panelToggle = "panel_toggle"
    case jumpWave = "jump_wave", jumpIterm = "jump_iterm", jumpTerminal = "jump_terminal"
    case jumpEditor = "jump_editor", jumpOther = "jump_other", jumpUnknown = "jump_unknown"
    case resume
    case approvalAllow = "approval_allow", approvalDeny = "approval_deny", approvalTimeout = "approval_timeout"
    case rename, pin
    case feedbackOpen = "feedback_open"
    case integrationInstall = "integration_install", integrationUninstall = "integration_uninstall"
    case integrationFail = "integration_fail"
    case spoolReplay = "spool_replay"

    /// The jump counter for a session's terminal, by kind only (never the program name).
    public static func jump(_ t: TerminalContext?) -> TelemetryEvent {
        guard let t else { return .jumpUnknown }
        if t.isWave || t.termProgram == "waveterm" { return .jumpWave }
        switch t.termProgram {
        case "iTerm.app": return .jumpIterm
        case "Apple_Terminal": return .jumpTerminal
        case "vscode", "cursor": return .jumpEditor
        case nil: return .jumpUnknown
        default: return .jumpOther
        }
    }
}

/// Setting flags a report may carry; anything else is dropped.
public enum TelemetrySetting: String, CaseIterable, Sendable {
    case showPanel = "show_panel", slimRail = "slim_rail", showRecentStats = "recent_stats"
    case flash, reviewFlash = "review_flash", staleTint = "stale_tint"
    case waveTabSwitching = "wave_tab_switching", piAutoTitle = "pi_auto_title", launchAtLogin = "launch_at_login"
}

/// One local day's report. Every field is listed in `docs/telemetry.md`; numbers about the user's
/// work are coarse buckets, not values.
public struct TelemetryReport: Codable, Equatable, Sendable {
    public static let schema = 1

    public var schema = Self.schema
    public var installId: String
    /// Local calendar day, `yyyy-MM-dd`.
    public var day: String
    public var app: String
    public var build: String
    /// macOS major version.
    public var os: String
    public var arch: String
    /// Language code only (`zh`, `en`).
    public var lang: String
    /// Agent → integration status (`installed`, `outdated`, `notInstalled`, `notDetected`).
    public var integrations: [String: String]
    public var settings: [String: Bool]
    /// `TelemetryEvent` → count that day.
    public var counts: [String: Int]
    /// Bucketed figures: `sessions.<agent>`, `turns.<agent>`, `agent_hours`, `parallel_peak`, `leverage`.
    public var figures: [String: String]

    enum CodingKeys: String, CodingKey {
        case schema, installId = "install_id", day, app, build, os, arch, lang, integrations, settings, counts, figures
    }
}

/// The day's numbers before bucketing.
public struct TelemetryFigures: Equatable, Sendable {
    public var sessions: [AgentKind: Int] = [:]
    public var turns: [AgentKind: Int] = [:]
    public var agentHours: Double = 0
    public var parallelPeak = 0
    public var leverage: Double?

    public init() {}

    /// Top-level sessions with a turn started in `day`, and those turns, per agent.
    public init(sessions list: [SessionState], day: DateInterval) {
        for s in list where s.parentId == nil {
            let n = s.turns.filter { day.contains($0.startedAt) && $0.startedAt < day.end }.count
            guard n > 0 else { continue }
            sessions[s.agent, default: 0] += 1
            turns[s.agent, default: 0] += n
        }
    }
}

/// The environment a report describes, gathered by the app.
public struct TelemetryEnvironment: Equatable, Sendable {
    public var app: String
    public var build: String
    public var os: String
    public var arch: String
    public var lang: String

    public init(app: String, build: String, os: String, arch: String, lang: String) {
        self.app = app; self.build = build; self.os = os; self.arch = arch; self.lang = lang
    }

    public static func current(bundle: Bundle = .main) -> TelemetryEnvironment {
        let info = bundle.infoDictionary
        var u = utsname()
        uname(&u)
        let arch = withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return TelemetryEnvironment(app: info?["CFBundleShortVersionString"] as? String ?? "dev",
                                    build: info?["CFBundleVersion"] as? String ?? "0",
                                    os: String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
                                    arch: arch, lang: Locale.current.language.languageCode?.identifier ?? "und")
    }
}

/// What telemetry keeps on disk (`Paths.telemetry`): consent, the install id, and per-day counts
/// while it is on. Both the app and `yaak telemetry` edit it, each with a fresh read first.
public struct TelemetryLedger: Codable, Equatable, Sendable {
    public var enabled = false
    /// The user has been asked once (or chose from the CLI or settings).
    public var asked = false
    public var installId: String?
    /// Day key → event → count. A day appears once the app ran on it with telemetry on.
    public var days: [String: [String: Int]] = [:]
    /// Days already reported (or given up on) are at most this one.
    public var lastSent: String?

    public init() {}

    public static func load(_ url: URL) -> TelemetryLedger {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(TelemetryLedger.self, from: $0) } ?? TelemetryLedger()
    }

    public func save(_ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// Re-reads, changes and writes back under a lock, so the other writer's edits survive (an
    /// `off` from `yaak` racing the app's write must not be undone).
    @discardableResult
    public static func update(_ url: URL, _ f: (inout TelemetryLedger) -> Void) -> TelemetryLedger {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path + ".lock", O_CREAT | O_RDWR, 0o600)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        var l = load(url)
        f(&l)
        l.save(url)
        return l
    }

    /// Turning on keeps an existing id; turning off forgets what was counted.
    public mutating func set(enabled on: Bool) {
        enabled = on
        asked = true
        if on { if installId == nil { installId = UUID().uuidString.lowercased() } } else { days = [:] }
    }

    public mutating func resetId() { installId = enabled ? UUID().uuidString.lowercased() : nil }

    /// Marks `day` as one the app ran on, and counts `event` (`n` times) if given. Nothing while off.
    public mutating func note(_ event: TelemetryEvent? = nil, by n: Int = 1, day: String) {
        guard enabled else { return }
        var d = days[day] ?? [:]
        if let event { d[event.rawValue, default: 0] += n }
        days[day] = d
    }

    /// Finished days not yet reported, oldest first, from the last `Telemetry.maxPendingDays`
    /// calendar days only (the server refuses older ones).
    public func pending(today: String) -> [String] {
        let floor = Telemetry.day(today, minus: Telemetry.maxPendingDays) ?? today
        return days.keys.filter { d in d >= floor && d < today && lastSent.map { d > $0 } ?? true }.sorted()
    }

    /// Reported (or dropped) up to `day`: those days and anything older go.
    public mutating func sent(through day: String) {
        lastSent = max(lastSent ?? day, day)
        days = days.filter { $0.key > day }
    }
}

public enum Telemetry {
    /// Info.plist key holding the TelemetryDeck App ID; empty or missing means telemetry is unavailable.
    public static let appIDKey = "YaakTelemetryDeckAppID"
    /// Days kept unsent at most; older ones are dropped.
    public static let maxPendingDays = 7

    /// Coarse ranges, so a report says "busy" rather than how busy.
    public static func bucket(_ n: Int) -> String {
        switch n {
        case ..<1: "0"
        case 1: "1"
        case 2...5: "2-5"
        case 6...20: "6-20"
        case 21...100: "21-100"
        default: "100+"
        }
    }

    public static func bucket(hours h: Double) -> String {
        switch h {
        case ..<0.1: "0"
        case ..<1: "<1"
        case ..<3: "1-3"
        case ..<8: "3-8"
        case ..<24: "8-24"
        default: "24+"
        }
    }

    public static func bucket(leverage x: Double) -> String {
        switch x {
        case ..<0.5: "<0.5"
        case ..<1: "0.5-1"
        case ..<2: "1-2"
        case ..<4: "2-4"
        default: "4+"
        }
    }

    public static func makeReport(installId: String, day: String, env: TelemetryEnvironment,
                                  integrations: [AgentKind: String], settings: [TelemetrySetting: Bool],
                                  counts: [String: Int], figures: TelemetryFigures) -> TelemetryReport {
        var f: [String: String] = [:]
        for a in AgentKind.allCases {
            if let n = figures.sessions[a], n > 0 { f["sessions.\(a.rawValue)"] = bucket(n) }
            if let n = figures.turns[a], n > 0 { f["turns.\(a.rawValue)"] = bucket(n) }
        }
        f["agent_hours"] = bucket(hours: figures.agentHours)
        f["parallel_peak"] = bucket(figures.parallelPeak)
        if let l = figures.leverage { f["leverage"] = bucket(leverage: l) }
        let known = Set(TelemetryEvent.allCases.map(\.rawValue))
        return TelemetryReport(installId: installId, day: day, app: env.app, build: env.build, os: env.os,
                               arch: env.arch, lang: env.lang,
                               integrations: Dictionary(uniqueKeysWithValues: integrations.map { ($0.key.rawValue, $0.value) }),
                               settings: Dictionary(uniqueKeysWithValues: settings.map { ($0.key.rawValue, $0.value) }),
                               counts: counts.filter { known.contains($0.key) && $0.value > 0 }, figures: f)
    }

    public static func encode(_ r: TelemetryReport, pretty: Bool = false) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return (try? enc.encode(r)) ?? Data()
    }

    /// Gregorian in the local time zone: day keys must not follow a Buddhist or Japanese system
    /// calendar, since the server and the ledger's ordering read them as Gregorian.
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// `yyyy-MM-dd` of the local day containing `date`.
    public static func dayKey(_ date: Date, calendar: Calendar = Telemetry.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The local day a key names.
    public static func interval(ofDay key: String, calendar: Calendar = Telemetry.calendar) -> DateInterval? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        return calendar.dateInterval(of: .day, for: d)
    }

    /// The key `n` days before `key`.
    public static func day(_ key: String, minus n: Int) -> String? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let d = interval(ofDay: key, calendar: utc)?.start,
              let e = utc.date(byAdding: .day, value: -n, to: d) else { return nil }
        return dayKey(e, calendar: utc)
    }

    /// `DO_NOT_TRACK` set to anything but empty or `0`.
    public static func doNotTrack(_ env: [String: String]) -> Bool {
        guard let v = env["DO_NOT_TRACK"] else { return false }
        return !v.isEmpty && v != "0"
    }
}
