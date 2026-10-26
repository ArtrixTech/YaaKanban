import Foundation
import Testing
@testable import YaaCore

@Suite struct UpdateTests {
    @Test func versionsCompareNumerically() throws {
        let v = { (s: String) in try #require(AppVersion(s)) }
        #expect(try v("0.1.10") > v("0.1.9"))
        #expect(try v("v0.2") > v("0.1.99"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try v("V1.2.3").description == "1.2.3")
        #expect(AppVersion("1.2.x") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1..2") == nil)
    }

    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, assets: [String] = ["YaaKanban-0.1.1.zip"]) throws -> GitHubRelease {
        let json: [String: Any] = [
            "tag_name": tag, "name": tag, "body": "notes", "html_url": "https://github.com/ArtrixTech/YaaKanban/releases/tag/\(tag)",
            "draft": draft, "prerelease": prerelease,
            "assets": assets.map { ["name": $0, "size": 10, "browser_download_url": "https://example.com/\($0)"] },
        ]
        return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func offersOnlyNewerFinalReleasesWithAnArchive() throws {
        let current = try #require(AppVersion("0.1.0"))
        #expect(try release("v0.1.1").offer(over: current) != nil)
        #expect(try release("v0.1.0").offer(over: current) == nil)
        #expect(try release("v0.0.9").offer(over: current) == nil)
        #expect(try release("v0.2.0", draft: true).offer(over: current) == nil)
        #expect(try release("v0.2.0", prerelease: true).offer(over: current) == nil)
        #expect(try release("v0.2.0", assets: ["notes.txt"]).offer(over: current) == nil)
        #expect(try release("nightly").offer(over: current) == nil)
        #expect(try release("v0.2.0", assets: ["source.zip", "YaaKanban-0.2.0.zip"]).archive?.name == "YaaKanban-0.2.0.zip")
    }

    @Test func changelogSectionAndExcerpt() throws {
        let log = """
        # Changelog

        ## [Unreleased]

        ## [0.1.1] - 2026-10-26

        ### Added
        - **Search** the last 14 days from the floating panel.
        - `yaak` stuff

        ## [0.1.0] - 2026-10-20

        - First.
        """
        let s = try #require(ReleaseNotes.section("0.1.1", in: log))
        #expect(s.hasPrefix("### Added"))
        #expect(!s.contains("First."))
        #expect(ReleaseNotes.section("v0.1.0", in: log) == "- First.")
        #expect(ReleaseNotes.section("0.1.2", in: log) == nil)
        #expect(ReleaseNotes.section("Unreleased", in: log) == nil)
        #expect(ReleaseNotes.excerpt(s) == "Added\n• Search the last 14 days from the floating panel.\n• yaak stuff")
        #expect(ReleaseNotes.excerpt("- a\n- b\n- c", lines: 2) == "• a\n• b\n…")
    }
}
