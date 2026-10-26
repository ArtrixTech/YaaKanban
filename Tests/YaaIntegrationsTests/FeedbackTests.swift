import Foundation
import Testing
@testable import YaaIntegrations
import YaaCore

@Suite struct FeedbackTests {
    @Test func issueLinkFillsTheDiagnosticsField() throws {
        let u = Feedback.issueURL(.bug, diagnostics: "- app: listening\n- telemetry: off")
        let q = try #require(URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(u.path == "/ArtrixTech/YaaKanban/issues/new")
        #expect(q.first { $0.name == "template" }?.value == "bug_report.yml")
        #expect(q.first { $0.name == "diagnostics" }?.value == "- app: listening\n- telemetry: off")
        let plain = Feedback.issueURL(.feature, diagnostics: nil)
        #expect(plain.query == "template=feature_request.yml")
    }

    /// The report names no path, so a home with the user's name never shows up in it.
    @Test func diagnosticsHaveNoPaths() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-diag-someuser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(environment: ["YAAK_HOME": home.appendingPathComponent("support").path])
        let d = Diagnostics.gather(paths: paths, home: home, yaak: "/x/yaak",
                                   env: TelemetryEnvironment(app: "0.1.0", build: "1", os: "15", arch: "arm64", lang: "en"),
                                   appListening: false, telemetry: true)
        let text = d.markdown
        #expect(text.contains("- claude-code: notInstalled"))
        #expect(text.contains("- cursor: notDetected"))
        #expect(text.contains("- app: not running") && text.contains("- telemetry: on"))
        #expect(!text.contains("someuser") && !text.contains("/"))
    }
}
