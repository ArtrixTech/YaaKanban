import CryptoKit
import Foundation

/// A daily report as an Aptabase event (their ingest API v0, as their Swift SDK sends it).
/// Props are strings, so counts go as buckets like the figures do.
public struct AptabaseEvent: Codable, Equatable, Sendable {
    public static let name = "daily"
    /// Aptabase takes at most this many events in one request.
    public static let maxBatch = 25
    /// Aptabase rejects longer prop keys.
    public static let maxKey = 40

    public struct SystemProps: Codable, Equatable, Sendable {
        public var isDebug: Bool
        public var locale: String
        public var osName: String
        public var osVersion: String
        public var appVersion: String
        public var appBuildNumber: String
        public var sdkVersion: String
    }

    public var timestamp: Date
    public var sessionId: String
    public var eventName: String
    public var systemProps: SystemProps
    public var props: [String: String]

    public init(report r: TelemetryReport, at: Date = Date(), debug: Bool = false) {
        timestamp = at
        // The SDK's form: start second and a random suffix. One session per report.
        sessionId = String(UInt64(at.timeIntervalSince1970) * 100_000_000 + UInt64.random(in: 0...99_999_999))
        eventName = Self.name
        systemProps = SystemProps(isDebug: debug, locale: r.lang, osName: "macOS", osVersion: r.os,
                                  appVersion: r.app, appBuildNumber: r.build, sdkVersion: "yaakanban@\(r.app)")
        var p: [String: String] = [
            "schema": String(r.schema),
            "day": r.day,
            "arch": r.arch,
            // Aptabase has no users; this lets days from one install be linked, never the install id itself.
            "install": SHA256.hash(data: Data(r.installId.utf8)).map { String(format: "%02x", $0) }.joined(),
        ]
        for (k, v) in r.integrations { p["integration.\(k)"] = v }
        for (k, v) in r.settings { p["setting.\(k)"] = v ? "on" : "off" }
        for (k, v) in r.counts { p["count.\(k)"] = Telemetry.bucket(v) }
        for (k, v) in r.figures { p["figure.\(k)"] = v }
        props = p
    }

    /// The ingest endpoint for an App Key; its second part names the region. Nil for an unknown
    /// region (self-hosted keys need the `YaakTelemetryIngestURL` override).
    public static func ingestURL(appKey: String) -> URL? {
        let parts = appKey.split(separator: "-")
        guard parts.count == 3, parts[0] == "A" else { return nil }
        switch parts[1] {
        case "EU": return URL(string: "https://eu.aptabase.com/api/v0/events")
        case "US": return URL(string: "https://us.aptabase.com/api/v0/events")
        default: return nil
        }
    }

    /// The POST body: an array of events, dates as Aptabase's SDK formats them.
    public static func body(_ events: [AptabaseEvent], pretty: Bool = false) -> Data {
        let enc = JSONEncoder()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        enc.dateEncodingStrategy = .formatted(f)
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return (try? enc.encode(events)) ?? Data()
    }
}
