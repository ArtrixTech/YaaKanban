import AppKit
import Foundation
import Observation
import Security
import YaaCore

/// Keeps the app current from GitHub Releases (spec §6): looks for a newer release now and then,
/// downloads and checks its archive in the background, then offers it in a one-line message on
/// the floating panel (no alert) before replacing the app and restarting. After an update the
/// first launch says so the same way, with a link to the release notes.
@MainActor @Observable
final class Updater {
    enum Phase: Equatable {
        case idle, checking, downloading(String), upToDate, failed(String)
        /// Downloaded, verified and waiting for the user's yes.
        case ready(Pending)
    }

    struct Pending: Equatable {
        let version: String
        let notes: String
        let page: URL
        /// The verified app inside the update cache.
        let app: URL
    }

    private(set) var phase: Phase = .idle
    /// The version this launch was updated to, until the user closes the message about it.
    private(set) var justUpdated: AppVersion?
    /// The user closed the message offering this version; it stays offered in the menu and settings.
    private(set) var dismissed: String?
    /// Looks for updates on its own; on by default, off in settings.
    var automatic: Bool {
        didSet { d.set(automatic, forKey: "autoUpdate"); schedule() }
    }

    @ObservationIgnored private let d = UserDefaults.standard
    @ObservationIgnored private var timer: Timer?

    static let feed = URL(string: "https://api.github.com/repos/ArtrixTech/YaaKanban/releases/latest")!
    /// How often the background check runs while the app is open.
    static let interval: TimeInterval = 6 * 3600

    let current: AppVersion?
    /// Team of the running app's signature; an update must be signed by the same team.
    let team: String?

    init(bundle: Bundle = .main) {
        d.register(defaults: ["autoUpdate": true])
        automatic = d.bool(forKey: "autoUpdate")
        current = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
        team = bundle.bundleIdentifier == nil ? nil : Self.team(of: bundle.bundleURL)
    }

    var busy: Bool {
        switch phase {
        case .checking, .downloading: true
        default: false
        }
    }

    /// A packaged, team-signed build: `swift run` and ad-hoc builds have nothing to compare an
    /// update's signature against, so they never update.
    var available: Bool { current != nil && team != nil }

    func start() {
        noteUpdated()
        schedule()
        if automatic { Task { await check(manual: false) } }
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard automatic, available else { return }
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(manual: false) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Looks for a release newer than this build; downloads and verifies it, then asks.
    func check(manual: Bool) async {
        guard available, let current else { return }
        if busy { return }
        if case .ready(let p) = phase { if manual, dismissed == p.version { dismissed = nil }; return }
        phase = .checking
        do {
            let feed = d.string(forKey: "updateFeedURL").flatMap(URL.init(string:)) ?? Self.feed
            guard let offer = try await Self.latest(feed)?.offer(over: current), let version = offer.version?.description else {
                phase = .upToDate
                return
            }
            phase = .downloading(version)
            let app = try await Self.download(offer, version: version, team: team)
            phase = .ready(Pending(version: version, notes: offer.body ?? "", page: offer.htmlURL, app: app))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Network and files (off the main actor)

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.waitsForConnectivity = true
        c.timeoutIntervalForResource = 1800
        c.httpAdditionalHeaders = ["Accept": "application/vnd.github+json", "User-Agent": "YaaKanban"]
        return URLSession(configuration: c)
    }()

    /// The latest published release; nil when there is none yet (404).
    nonisolated private static func latest(_ feed: URL) async throws -> GitHubRelease? {
        let (data, response) = try await session.data(from: feed)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 404 { return nil }
            throw UpdateError.http(http.statusCode)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// The update cache: one folder per version, emptied once the update is in place.
    nonisolated static var cache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.artrix.yaakanban/Updates")
    }

    /// Downloads the release's archive (once per version), unpacks it and checks the app inside:
    /// the expected bundle and version, a valid signature, and the running app's team.
    nonisolated private static func download(_ release: GitHubRelease, version: String, team: String?) async throws -> URL {
        let fm = FileManager.default
        let dir = cache.appendingPathComponent(version)
        let app = dir.appendingPathComponent("YaaKanban.app")
        if fm.fileExists(atPath: app.path), (try? verify(app, version: version, team: team)) != nil { return app }
        guard let asset = release.archive else { throw UpdateError.noArchive }
        let (file, response) = try await session.download(from: asset.browserDownloadURL)
        defer { try? fm.removeItem(at: file) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", file.path, dir.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0, fm.fileExists(atPath: app.path) else { throw UpdateError.badArchive }
        try verify(app, version: version, team: team)
        return app
    }

    nonisolated private static func verify(_ app: URL, version: String, team: String?) throws {
        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == "com.artrix.yaakanban",
              (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) == AppVersion(version)
        else { throw UpdateError.badArchive }
        guard let team, Self.team(of: app) == team else { throw UpdateError.badSignature }
    }

    /// The team that signed `app`, if its signature (nested code included) is valid.
    nonisolated static func team(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), nil) == errSecSuccess
        else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: Asking and installing

    /// What the panel's update message says, if anything: an update ready to install, or the
    /// version just updated to. Closing it hides it; the menu and settings still offer the update.
    enum Notice: Equatable { case ready(Pending), updated(AppVersion) }

    var notice: Notice? {
        if case .ready(let p) = phase, dismissed != p.version { return .ready(p) }
        return justUpdated.map(Notice.updated)
    }

    func dismiss() {
        switch notice {
        case .ready(let p): dismissed = p.version
        case .updated: justUpdated = nil
        case nil: break
        }
    }

    /// Installs the update that is ready, if any.
    func installReady() {
        if case .ready(let p) = phase { install(p) }
    }

    /// Replaces this app with the verified update and opens it, once this process has quit.
    /// Where the app cannot be replaced (a read-only or translocated copy), opens the release page.
    func install(_ p: Pending) {
        let bundle = Bundle.main.bundleURL
        let parent = bundle.deletingLastPathComponent()
        guard !bundle.path.contains("/AppTranslocation/"), FileManager.default.isWritableFile(atPath: parent.path) else {
            NSWorkspace.shared.open(p.page)
            phase = .failed(String(localized: "Can't replace the app where it is; download the update from the release page."))
            return
        }
        // The old copy is moved aside and the new one moved in right after, so the hooks' link
        // to `yaak` is missing only for that instant; the old copy is restored if the move fails.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        old="$2.old-$$"
        mv "$2" "$old" || exit 1
        if mv "$3" "$2"; then
          rm -rf "$old"
        else
          mv "$old" "$2"
        fi
        xattr -dr com.apple.quarantine "$2" 2>/dev/null
        open "$2"
        """
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", script, "sh", "\(ProcessInfo.processInfo.processIdentifier)", bundle.path, p.app.path]
        do { try sh.run() } catch { phase = .failed(error.localizedDescription); return }
        NSApp.terminate(nil)
    }

    // MARK: After an update

    /// First launch of a newer version than the last one: clears the cache and says so (the
    /// panel's message, until closed), with the way to its release notes.
    private func noteUpdated() {
        guard let current else { return }
        let last = d.string(forKey: "lastRunVersion").flatMap(AppVersion.init)
        d.set(current.description, forKey: "lastRunVersion")
        guard let last, last < current else { return }
        try? FileManager.default.removeItem(at: Self.cache)
        justUpdated = current
    }

    /// The release page of `version`.
    static func notes(for version: AppVersion) -> URL {
        URL(string: "https://github.com/ArtrixTech/YaaKanban/releases/tag/v\(version.description)")!
    }
}

enum UpdateError: LocalizedError {
    case noArchive, badArchive, badSignature, http(Int)

    var errorDescription: String? {
        switch self {
        case .noArchive: String(localized: "The release has no app archive.")
        case .badArchive: String(localized: "The downloaded update is not a YaaKanban build of that version.")
        case .badSignature: String(localized: "The downloaded update isn't signed by the same developer; it was not installed.")
        case .http(let code): String(localized: "GitHub answered with HTTP \(code).")
        }
    }
}
