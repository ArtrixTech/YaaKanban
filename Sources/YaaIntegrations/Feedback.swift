import Foundation
import YaaCore

/// The diagnostics report for feedback (`yaak doctor`, the app's 反馈…): setup facts only, no
/// paths, never session content.
public struct Diagnostics: Sendable {
    public var app: String
    public var os: String
    public var arch: String
    public var integrations: [(agent: AgentKind, status: IntegrationStatus)]
    /// Whether the app answers on its socket (nil: not checked, e.g. from inside the app).
    public var appListening: Bool?
    public var spooled: Int
    public var databaseBytes: Int?
    public var telemetry: Bool

    public static func gather(paths: Paths, home: URL, yaak: String, env: TelemetryEnvironment,
                              appListening: Bool?, telemetry: Bool) -> Diagnostics {
        let fm = FileManager.default
        let spooled = (try? fm.contentsOfDirectory(atPath: paths.spool.path))?.count ?? 0
        let db = (try? fm.attributesOfItem(atPath: paths.database.path))?[.size] as? Int
        return Diagnostics(app: "\(env.app) (\(env.build))",
                           os: ProcessInfo.processInfo.operatingSystemVersionString, arch: env.arch,
                           integrations: Integrations.all.map { ($0.agent, $0.status(home: home, yaak: yaak)) },
                           appListening: appListening, spooled: spooled, databaseBytes: db, telemetry: telemetry)
    }

    public var markdown: String {
        var lines = ["- YaaKanban: \(app)", "- macOS: \(os) (\(arch))"]
        lines += integrations.map { "- \($0.agent.rawValue): \($0.status.rawValue)" }
        if let appListening { lines.append("- app: \(appListening ? "listening" : "not running")") }
        lines.append("- spool: \(spooled) pending")
        if let databaseBytes { lines.append("- history: \(ByteCountFormatter.string(fromByteCount: Int64(databaseBytes), countStyle: .file))") }
        lines.append("- telemetry: \(telemetry ? "on" : "off")")
        return lines.joined(separator: "\n")
    }
}

public enum Feedback {
    public static let repo = URL(string: "https://github.com/ArtrixTech/YaaKanban")!

    public enum Kind: String, Sendable {
        case bug, feature
        var template: String { self == .bug ? "bug_report.yml" : "feature_request.yml" }
    }

    /// A new-issue link with the form's `diagnostics` field filled in (GitHub issue forms take
    /// field ids as query parameters). Kept well under URL length limits.
    public static func issueURL(_ kind: Kind, diagnostics: String?) -> URL {
        var c = URLComponents(url: repo.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        var q = [URLQueryItem(name: "template", value: kind.template)]
        if let diagnostics, !diagnostics.isEmpty { q.append(URLQueryItem(name: "diagnostics", value: String(diagnostics.prefix(4000)))) }
        c.queryItems = q
        return c.url!
    }
}
