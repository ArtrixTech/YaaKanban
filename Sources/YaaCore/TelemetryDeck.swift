import CryptoKit
import Foundation

/// A daily report as a TelemetryDeck signal (their ingest API v2, as their Swift SDK sends it).
/// Payload values are strings, so counts go as buckets like the figures do.
public struct TelemetryDeckSignal: Codable, Equatable, Sendable {
    /// The organization's namespace endpoint; TelemetryDeck asks namespaced organizations to use it.
    public static let ingestURL = URL(string: "https://nom.telemetrydeck.com/v2/namespace/com.yaakanban/")!
    public static let type = "Yaak.daily"

    public var receivedAt: Date
    public var appID: String
    /// SHA-256 of the install id; TelemetryDeck salts and hashes it again.
    public var clientUser: String
    public var sessionID: String
    public var type: String
    public var payload: [String: String]
    public var isTestMode: String

    public init(report r: TelemetryReport, appID: String, at: Date = Date(), testMode: Bool = false) {
        receivedAt = at
        self.appID = appID
        clientUser = SHA256.hash(data: Data(r.installId.utf8)).map { String(format: "%02x", $0) }.joined()
        sessionID = UUID().uuidString
        type = Self.type
        isTestMode = testMode ? "true" : "false"
        var p: [String: String] = [
            // TelemetryDeck's own names, so its built-in version and system charts work.
            "TelemetryDeck.AppInfo.version": r.app,
            "TelemetryDeck.AppInfo.buildNumber": r.build,
            "TelemetryDeck.AppInfo.versionAndBuildNumber": "\(r.app) (build \(r.build))",
            "TelemetryDeck.Device.platform": "macOS",
            "TelemetryDeck.Device.operatingSystem": "macOS",
            "TelemetryDeck.Device.systemMajorVersion": "macOS \(r.os)",
            "TelemetryDeck.Device.architecture": r.arch,
            "TelemetryDeck.RunContext.language": r.lang,
            "Yaak.schema": String(r.schema),
            "Yaak.day": r.day,
        ]
        for (k, v) in r.integrations { p["Yaak.integration.\(k)"] = v }
        for (k, v) in r.settings { p["Yaak.setting.\(k)"] = v ? "on" : "off" }
        for (k, v) in r.counts { p["Yaak.count.\(k)"] = Telemetry.bucket(v) }
        for (k, v) in r.figures { p["Yaak.figure.\(k)"] = v }
        payload = p
    }

    /// The POST body: an array of signals, dates as TelemetryDeck's SDK formats them.
    public static func body(_ signals: [TelemetryDeckSignal], pretty: Bool = false) -> Data {
        let enc = JSONEncoder()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        enc.dateEncodingStrategy = .formatted(f)
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return (try? enc.encode(signals)) ?? Data()
    }
}
