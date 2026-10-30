import AppKit
import Foundation
import Observation
import YaaCore
import YaaIntegrations

/// Owns all session state on the main actor. Socket requests, scanners and timers feed it.
@MainActor @Observable
final class AppModel {
    private(set) var sessions: [String: SessionState] = [:]
    let settings = Preferences()
    let paths = Paths()

    @ObservationIgnored private var store: Store?
    @ObservationIgnored private var server: SocketServer?
    /// A blocked permission hook. `token` ties the expiry timer to this request only.
    private struct PendingReply {
        let token = UUID()
        let requestId: String?
        let send: (Data?) -> Void
    }
    @ObservationIgnored private var pendingReplies: [String: PendingReply] = [:]
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private let usageTracker = UsageTracker()
    @ObservationIgnored let notifier = Notifier()
    @ObservationIgnored lazy var jumper = TerminalJumper(settings: settings)
    @ObservationIgnored private let scanner = ClaudeSessionScanner()
    /// Opt-in anonymous daily reports (off unless the user turned them on).
    let telemetry: TelemetryReporter
    let updater = Updater()

    var serverError: String?
    /// Installed integrations whose hooks the agent will not run yet, with what the user has to do.
    private(set) var integrationIssues: [AgentKind: [String]] = [:]
    /// Agents found on this Mac without our hooks: their sessions show only what a scan can see.
    private(set) var unhookedAgents: Set<AgentKind> = []
    /// No integration installed at all: the panel and menu point to the setup guide.
    private(set) var noIntegrations = false
    /// Opens the setup guide once launch is done: a first launch with nothing connected.
    @ObservationIgnored private(set) var showSetupAtLaunch = false
    /// Agents that have reached YaaKanban through their hooks (the setup guide's check).
    var connectedAgents: Set<AgentKind> { Set(sessions.values.filter(\.hooked).map(\.agent)) }
    /// Debug hook: render windows to PNGs (`yaak snapshot <dir>`), for verification without screen recording.
    @ObservationIgnored var onSnapshot: ((URL) -> Void)?
    /// Session selected in the main window, or `overview` (the home page) or `settingsPage`.
    var selection: String? = AppModel.overview
    static let overview = "overview"
    static let settingsPage = "settings"
    /// The tab the Settings page shows, so a link elsewhere can open the one it means.
    var settingsTab = SettingsView.Tab.agents

    init() {
        telemetry = TelemetryReporter(paths: paths)
        telemetry.build = { [unowned self] day, counts, id in telemetryReport(day: day, counts: counts, installId: id) }
    }

    // MARK: Derived views

    /// Active sessions for the floating panel; idle and ended ones only for a while (24 h by default).
    /// Sub-agents of a session on the board show inside its card instead; one waiting on the user
    /// shows its parent as waiting too, since the whole call is held up. A sub-agent whose parent is
    /// not on the board (it never reported, or has left) gets no card unless it waits on the user.
    var activeSessions: [SessionState] {
        let now = Date()
        let live = sessions.values.filter { isLive($0, now: now) }
        let shown = Set(live.map(\.id))
        var waiting: [String: SessionState] = [:]
        for c in live where c.status == .needsInput { if let p = c.parentId { waiting[p] = c } }
        return sorted(live.compactMap { s in
            if let p = s.parentId, shown.contains(p) || s.status != .needsInput { return nil }
            guard let c = waiting[s.id], s.status != .needsInput else { return s }
            var shownAs = s
            shownAs.status = .needsInput
            shownAs.needsInputMessage = c.needsInputMessage
            shownAs.needsInputSince = c.needsInputSince
            return shownAs
        })
    }

    /// Live sub-agent sessions of `key`, oldest first.
    func subagents(of key: String) -> [SessionState] {
        let now = Date()
        return sessions.values.filter { $0.parentId == key && isLive($0, now: now) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private func isLive(_ s: SessionState, now: Date) -> Bool {
        // A session joins the boards with its first message, so an unused one never lingers.
        if s.dismissedAt != nil || s.isUnstarted { return false }
        // A pin keeps it until the user unpins or ends it.
        if s.parentId == nil, isPinned(s.id) { return true }
        switch s.status {
        // However it ended (an exit, or a terminal crash that looks just like one), the conversation
        // lingers like a reviewed card so it can be resumed, unless the same process went on with a
        // new session (`/clear`, `/new`).
        case .ended:
            if s.parentId != nil || now.timeIntervalSince(s.quietSince) >= settings.idleVisibleSeconds { return false }
            // Moved into a background job: the job's own session shows the conversation.
            if let job = s.parkedIn, sessions.values.contains(where: {
                $0.agent == s.agent && $0.id != s.id && $0.sessionId.hasPrefix(job)
            }) { return false }
            // One process may host sibling sessions (OpenCode, the Codex app): only a top-level
            // session started after this one's last event (or its restore) replaced it.
            guard let pid = s.agentPid else { return true }
            let since = max(s.lastEventAt, s.restoredAt ?? s.lastEventAt)
            return !sessions.values.contains {
                $0.agentPid == pid && $0.id != s.id && $0.parentId == nil && $0.startedAt >= since
            }
        // Unreviewed results stay until looked at; reviewed ones fade out after a while.
        // A sub-agent's result is its parent's business, so it only lingers briefly.
        case .idle:
            if s.parentId != nil { return now.timeIntervalSince(s.lastEventAt) < Self.subagentLinger }
            return s.unreadSince != nil || now.timeIntervalSince(s.quietSince) < settings.idleVisibleSeconds
        default: return true
        }
    }

    static let subagentLinger: TimeInterval = 60

    /// A session's status as the user sees it: one that has left the boards (retention over, or
    /// ended on the panel) is ended, whatever the agent did.
    func display(_ s: SessionState) -> DisplayStatus {
        s.parentId == nil && !isLive(s, now: Date()) ? .ended : s.display
    }

    var allSessions: [SessionState] { sorted(sessions.values.filter { !$0.isUnstarted }) }

    /// Active sessions as the boards show them: most urgent first, then the user's order or start order.
    var board: [SessionState] { Board.ordered(activeSessions, manualOrder: settings.manualOrder, pinned: settings.pinned) }

    func isPinned(_ key: String) -> Bool { settings.pinned.contains(key) }

    /// Pins a session above every status, or unpins it.
    func togglePin(_ key: String) {
        if isPinned(key) { settings.pinned.removeAll { $0 == key } } else { settings.pinned.insert(key, at: 0); telemetry.count(.pin) }
    }

    /// Moves sessions before `target`, or to the end.
    func move(_ ids: [String], before target: String?) {
        settings.manualOrder = Board.move(ids, before: target, board: board.map(\.id), manualOrder: settings.manualOrder)
    }

    /// Context-menu moves: -1 up, +1 down, nil to the top.
    func step(_ ids: [String], by delta: Int?) {
        let flat = board.map(\.id)
        guard let first = ids.first, let i = flat.firstIndex(of: first) else { return }
        let j = delta.map { i + $0 } ?? 0
        guard j != i, flat.indices.contains(j) else { return }
        // Moving down: land before the card after the one we pass.
        move(ids, before: j < i ? flat[j] : (flat.indices.contains(j + 1) ? flat[j + 1] : nil))
    }

    /// Sessions the user has not ended; counts and badges ignore the rest.
    private var visible: [SessionState] { sessions.values.filter { $0.dismissedAt == nil } }
    var attentionCount: Int { visible.filter { $0.status.needsAttention }.count }
    /// Sessions waiting on the user: blocked, stuck, or finished and not yet reviewed.
    var pendingCount: Int { sessions.values.filter(Self.wantsUser).count }
    static func wantsUser(_ s: SessionState) -> Bool {
        s.dismissedAt == nil && (s.status.needsAttention || s.display == .review)
    }
    var hasStuck: Bool { visible.contains { $0.status == .stuck } }
    var hasNeedsInput: Bool { visible.contains { $0.status == .needsInput } }
    var reviewCount: Int { visible.filter { $0.display == .review }.count }
    var runningCount: Int { visible.filter { $0.status == .running }.count }

    /// History order: most recent first.
    private func sorted(_ list: [SessionState]) -> [SessionState] {
        list.sorted { $0.lastEventAt > $1.lastEventAt }
    }

    // MARK: Lifecycle

    func start() {
        _ = Self.yaakPath
        do {
            let store = try Store(path: paths.database)
            store.purgeDetails()
            for s in store.loadAll() {
                // Codex background calls recorded before they were filtered out.
                if Normalizer.isCodexBackground(s.agent, transcriptPath: s.transcriptPath) { store.delete(id: s.id); continue }
                sessions[s.id] = s
            }
            self.store = store
        } catch {
            serverError = "History unavailable: \(error)"
        }
        beginActivity()
        // Sessions that were live when the app quit may have ended meanwhile.
        tick()
        syncLanes()

        do {
            try FileManager.default.createDirectory(at: paths.base, withIntermediateDirectories: true)
            let server = SocketServer(path: paths.socket.path) { [weak self] line, reply in
                Task { @MainActor in self?.handle(line: line, reply: reply) }
            }
            try server.start()
            self.server = server
        } catch {
            serverError = "Cannot listen on \(paths.socket.path): \(error)"
        }
        let spooled = Wire.drainSpool(paths: paths) { ingest($0.envelope, alert: false) }
        telemetry.count(.spoolReplay, by: spooled)

        notifier.onAction = { [weak self] key, requestId, action in
            self?.handleNotificationAction(key: key, requestId: requestId, action: action)
        }
        notifier.setUp()

        checkIntegrations()
        if !settings.setupDone {
            // Someone who already connected agents (an older version) needs no guide.
            if noIntegrations { showSetupAtLaunch = true } else { settings.setupDone = true }
        }
        // Without the guide nothing else asks; asking again is a no-op.
        if !showSetupAtLaunch { notifier.requestAuthorization() }
        timers.append(Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        // Authorization happens in the agent, out of our sight; a minute is soon enough to notice.
        timers.append(Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIntegrations() }
        })
        timers.append(Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        })
        // Common modes: keep going while a dialog or menu is open.
        for t in timers { RunLoop.main.add(t, forMode: .common) }
        scan()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.awaySince = self?.awaySince ?? Date() }
        }
        // Auto review: on switching apps at once, then every second while a terminal is in front.
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkFocus() }
        }
        let focus = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkFocus() }
        }
        RunLoop.main.add(focus, forMode: .common)
        timers.append(focus)
    }

    // MARK: Auto review

    @ObservationIgnored private var probingFocus = false

    /// Experimental: a finished turn whose pane the user has in front counts as reviewed, as if
    /// its card was clicked. Only while the user is at the Mac, and only for terminals that can
    /// say which pane is in front (`FocusWatcher`).
    private func checkFocus() {
        guard settings.autoReviewOnFocus, !probingFocus,
              let front = NSWorkspace.shared.frontmostApplication,
              let bundle = front.bundleIdentifier, FocusWatcher.terminals.contains(bundle),
              awaySince == nil, !Self.screenLocked,
              CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) < Self.awayAfter
        else { return }
        let waiting = sessions.values.filter { s in s.display == .review && s.terminal.map { Self.focusable($0, of: s) } == true }
        guard !waiting.isEmpty else { return }
        probingFocus = true
        FocusWatcher.probe(front: front, wanted: waiting.compactMap(\.terminal)) { [weak self] focus in
            guard let self else { return }
            probingFocus = false
            for s in waiting where s.terminal.map(focus.shows) == true && sessions[s.id]?.display == .review {
                markRead(s.id)
            }
        }
    }

    /// A pane known only by its tty counts while the agent still holds that tty: once it is gone,
    /// macOS hands the tty to the next new tab.
    private static func focusable(_ t: TerminalContext, of s: SessionState) -> Bool {
        if t.isWave || t.itermSession != nil || t.weztermPane != nil || t.tmuxPane != nil { return true }
        guard let tty = t.tty, let pid = s.agentPid else { return false }
        return ProcessUtil.isAlive(pid) && ProcessUtil.tty(of: pid) == tty
    }

    private static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// Re-reads each installed integration's authorization state from the agents' own files.
    func checkIntegrations() {
        let home = Paths.home()
        var issues: [AgentKind: [String]] = [:]
        var unhooked: Set<AgentKind> = []
        var installed = 0
        for i in Integrations.all {
            guard i.isInstalled(home: home) else {
                if i.isDetected(home: home) { unhooked.insert(i.agent) }
                continue
            }
            installed += 1
            let steps = i.pendingSteps(home: home)
            if !steps.isEmpty { issues[i.agent] = steps }
        }
        if issues != integrationIssues { integrationIssues = issues }
        if unhooked != unhookedAgents { unhookedAgents = unhooked }
        if (installed == 0) != noIntegrations { noIntegrations = installed == 0 }
    }

    /// Installs or removes `i`'s hooks; the message to show, nil on success with nothing to add.
    @discardableResult
    func applyIntegration(_ i: any Integration, install: Bool) -> String {
        let name = i.agent.displayName
        defer { checkIntegrations() }
        do {
            try Installer.apply(try i.plan(install: install, home: Paths.home(), yaak: Self.yaakPath))
            telemetry.count(install ? .integrationInstall : .integrationUninstall)
            return !install ? String(localized: "\(name) uninstalled.")
                : i.pendingSteps(home: Paths.home()).isEmpty ? String(localized: "\(name) installed. Sessions you start from now on report to YaaKanban; restart ones already running.")
                : String(localized: "\(name) installed. You still need to approve it in \(name); the steps are above.")
        } catch {
            telemetry.count(.integrationFail)
            return "\(name): \(error)"
        }
    }

    /// The guide was finished or closed: it stays closed, and notifications are asked for if not yet.
    func finishSetup() {
        settings.setupDone = true
        notifier.requestAuthorization()
    }

    /// Path the hooks call: the stable link to this app's yaak, made or re-pointed on first use.
    static let yaakPath: String = {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/yaak").path
        // Only a real app bundle owns the link; a dev build run in place must not take it over.
        let home = Paths.home(), link = StableYaak.link(home: home).path
        guard Bundle.main.bundleURL.pathExtension == "app" else { return bundled }
        guard StableYaak.mayClaim(bundle: Bundle.main.bundleURL, home: home) else {
            // Another copy owns the link; hooks installed from here still go through it.
            return FileManager.default.fileExists(atPath: link) ? link : bundled
        }
        // A lost race with another writer still leaves a valid link.
        return (try? StableYaak.ensure(home: home, target: bundled))
            ?? ((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != nil ? link : bundled)
    }()

    func stop() {
        endAway(at: Date())
        store?.setMeta(Self.heartbeatKey, Date().timeIntervalSince1970)
        server?.stop()
        for (_, r) in pendingReplies { r.send(Wire.encode(WireReply(decision: nil))) }
    }

    // MARK: Ingest

    private func handle(line: Data, reply: @escaping @Sendable (Data?) -> Void) {
        if let dir = JSONValue.parse(line)?["snapshot"]?.string {
            reply(nil)
            onSnapshot?(URL(fileURLWithPath: dir))
            return
        }
        guard let req = Wire.decode(WireRequest.self, line) else { reply(nil); return }
        switch req.kind {
        case .event:
            reply(nil)
            ingest(req.envelope, alert: true)
        case .permission:
            guard let key = ingest(req.envelope, alert: true) else { reply(nil); return }
            pendingReplies[key]?.send(Wire.encode(WireReply(decision: nil)))
            let pending = PendingReply(requestId: sessions[key]?.pendingPermission?.id, send: reply)
            pendingReplies[key] = pending
            let timeout = min(settings.approvalTimeout, req.timeout ?? settings.approvalTimeout)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.expirePermission(key: key, token: pending.token)
            }
        }
    }

    /// Applies an envelope; returns the session key it touched.
    @discardableResult
    func ingest(_ env: HookEnvelope, alert: Bool) -> String? {
        var key: String?
        for ev in Normalizer.normalize(env) {
            if case .backgroundStart = ev.kind, !settings.claudeBackgroundAgents { continue }
            key = update(SessionState.key(ev.agent, ev.sessionId), alert: alert) { old in
                var s = SessionReducer.apply(ev, to: old)
                // Another agent started it as a tool: it works for that one, from its first turn on.
                if s.parentId == nil, old?.turns.isEmpty ?? true, let pids = env.ancestorPids {
                    s.parentId = CallerLink.caller(of: s, ancestors: pids, among: sessions.values)
                }
                return s
            }
        }
        if let key { linkParent(key) }
        return key
    }

    @discardableResult
    private func update(_ key: String, alert: Bool, _ f: (SessionState?) -> SessionState?) -> String {
        let old = sessions[key]
        guard var new = f(old) else { return key }
        // A sub-agent's finished turn is reviewed through its parent.
        if new.parentId != nil { new.unreadSince = nil }
        sessions[key] = new
        // The tick and the scan pass every session through here; rewriting the unchanged ones
        // dirtied gigabytes a day.
        if new != old { store?.save(new) }
        record(Activity.rows(old: old, new: new, now: Date()))
        if old?.pendingPermission?.awaitingDecision == true && new.pendingPermission?.awaitingDecision != true {
            pendingReplies.removeValue(forKey: key)?.send(Wire.encode(WireReply(decision: nil)))
            notifier.withdraw(key: key)
        }
        if alert, new.dismissedAt == nil, let a = Alerts.between(old, new),
           new.parentId == nil || !a.isDone { notifier.post(a, for: new, settings: settings) }
        // The Wave badge stays on until the user has dealt with it, including reviewing a finished turn.
        if (old.map(Self.wantsUser) ?? false) != Self.wantsUser(new) { jumper.badge(new, on: Self.wantsUser(new)) }
        return key
    }

    // MARK: Permissions

    /// `requestId` is the request the user saw (panel or notification); it must match the one
    /// still pending, so a stale button or notification can never approve a newer command.
    func decide(_ key: String, _ decision: PermissionDecision, requestId: String) {
        guard let pending = pendingReplies[key], pending.requestId == requestId else { return }
        pendingReplies[key] = nil
        pending.send(Wire.encode(WireReply(decision: decision)))
        notifier.withdraw(key: key)
        telemetry.count(decision == .allow ? .approvalAllow : .approvalDeny)
        update(key, alert: false) { s in
            guard var s else { return nil }
            s.pendingPermission = nil
            s.needsInputMessage = nil
            s.status = .running
            s.lastEventAt = Date()
            return s
        }
    }

    func canDecide(_ key: String) -> Bool { pendingReplies[key] != nil }

    private func expirePermission(key: String, token: UUID) {
        guard let pending = pendingReplies[key], pending.token == token else { return }
        pendingReplies[key] = nil
        pending.send(Wire.encode(WireReply(decision: nil)))
        telemetry.count(.approvalTimeout)
        // The agent now shows its own prompt in the terminal; the session still needs input.
        update(key, alert: false) { s in
            guard var s else { return nil }
            s.pendingPermission?.awaitingDecision = false
            return s
        }
    }

    private func handleNotificationAction(key: String, requestId: String?, action: Notifier.Action) {
        switch action {
        case .allow: decide(key, .allow, requestId: requestId ?? "")
        case .deny: decide(key, .deny, requestId: requestId ?? "")
        case .open: jump(key)
        }
    }

    // MARK: Periodic work

    private func tick() {
        let now = Date()
        trackAway(now: now)
        if now.timeIntervalSince(tokensFlushedAt) >= 60 { flushTokens() }
        store?.setMeta(Self.heartbeatKey, now.timeIntervalSince1970)
        telemetry.tick(now: now)
        let cfg = settings.stuckConfig
        for key in Array(sessions.keys) {
            update(key, alert: true) { s in
                guard let s else { return nil }
                if s.terminal?.waveJWT != nil, s.dropsWaveToken(now: now, gone: Self.isGone(s)) {
                    var out = s
                    out.terminal?.waveJWT = nil
                    return out
                }
                return StuckDetector.evaluate(s, now: now, config: cfg, isAlive: ProcessUtil.isAlive)
            }
        }
        syncLanes()
    }

    private func scan() {
        for ev in scanner.scan() {
            // Alert on unhooked sessions we already know (hooks alert for the rest); the first
            // sighting is just discovery.
            let k = SessionState.key(ev.agent, ev.sessionId)
            update(k, alert: sessions[k].map { !$0.hooked } ?? false) { SessionReducer.apply(ev, to: $0) }
        }
        for s in sessions.values where s.parentId == nil && s.status != .ended { linkParent(s.id) }
        // Titles for every live session; for unhooked ones also the latest prompt and reply.
        for s in activeSessions {
            var peek: TranscriptPeek?
            switch s.agent {
            case .claudeCode: peek = scanner.peek(s)
            case .codex:
                if let t = scanner.codexTitle(s.sessionId), t != s.peek?.title { peek = s.peek ?? TranscriptPeek(); peek?.title = t }
            default: break
            }
            guard let peek, peek != s.peek else { continue }
            update(s.id, alert: false) { s in
                guard var s else { return nil }
                s.peek = peek
                return s
            }
        }
        usageTracker.refresh(activeSessions.map {
            UsageTracker.Target(key: $0.id, agent: $0.agent, sessionId: $0.sessionId, transcriptPath: $0.transcriptPath)
        }) { [weak self] results in
            guard let self else { return }
            for (key, r) in results {
                endReportedTools(key, r.finishedTools)
                update(key, alert: false) { s in
                    guard var s else { return nil }
                    s.usage = r.usage
                    // Claude's reply comes from the transcript peek; Codex has none, so use the tally's.
                    if s.agent == .codex {
                        var p = s.peek ?? TranscriptPeek()
                        p.lastReply = r.lastReply
                        s.peek = p
                    }
                    return s
                }
            }
        }
    }

    /// Ends tool calls the transcript shows a result for but no hook reported (a failed call
    /// without the PostToolUseFailure hook, an interrupt). Recent calls are left to the hooks,
    /// which carry the output and arrive within moments.
    private func endReportedTools(_ key: String, _ finished: [(id: String, failed: Bool)]) {
        guard let s = sessions[key], !finished.isEmpty else { return }
        let failed = Dictionary(finished.map { ($0.id, $0.failed) }) { $1 }
        let now = Date()
        for t in s.runningTools where now.timeIntervalSince(t.startedAt) > 10 {
            guard let f = failed[t.id] else { continue }
            // Stamped at the last known event, so it does not count as new activity.
            let e = AgentEvent(agent: s.agent, sessionId: s.sessionId, at: s.lastEventAt,
                               kind: .toolEnd(id: t.id, name: t.name, output: nil, isError: f))
            update(key, alert: false) { SessionReducer.apply(e, to: $0) }
        }
    }

    // MARK: Activity

    /// Bumped on each recorded row, so the efficiency views redraw.
    private(set) var activityVersion = 0
    /// The user has been away (no input for `awayAfter`, or the Mac asleep) since then.
    private(set) var awaySince: Date? { didSet { if awaySince != nil { presentSince = nil } } }
    /// The user has been at the Mac since then (launch, or the end of the last absence); nil while away.
    private(set) var presentSince: Date? = Date()
    /// Activity before this was rebuilt from the session history: running time and turns only.
    private(set) var recordedSince: Date?
    static let awayAfter: TimeInterval = 120
    private static let heartbeatKey = "heartbeat"
    private static let awayKey = "awaySince"
    private static let recordedKey = "recordedSince"
    /// Each session's lane as last recorded, so a tick can catch lanes the record missed.
    @ObservationIgnored private var recordedLanes: [String: Lane] = [:]
    /// Token use waiting to be written: one row per session per minute instead of one per scan.
    @ObservationIgnored private var pendingTokens: [String: Double] = [:]
    @ObservationIgnored private var tokensFlushedAt = Date()
    @ObservationIgnored private var reports: [ReportKey: (version: Int, at: Date, report: ActivityReport)] = [:]
    private struct ReportKey: Hashable { var range: DateInterval; var buckets: Int }

    /// The session's lane, as the boards show it: one past its retention has left the lanes.
    private func lane(_ s: SessionState?) -> Lane? {
        guard let s, s.parentId == nil, s.dismissedAt == nil else { return nil }
        return Lane(display(s))
    }

    private func record(_ rows: [ActivityRow]) {
        guard let store else { return }
        var rows = rows
        rows.removeAll { r in
            guard r.kind == .tokens else { return false }
            pendingTokens[r.session, default: 0] += r.value
            return true
        }
        guard !rows.isEmpty else { return }
        for r in rows where r.kind == .lane { recordedLanes[r.session] = Lane(rawValue: r.text) }
        // The heartbeat covers the rows just written, so lanes left open at a quit close after them.
        store.record(rows, meta: [Self.heartbeatKey: Date().timeIntervalSince1970])
        activityVersion += 1
    }

    private func flushTokens() {
        tokensFlushedAt = Date()
        guard !pendingTokens.isEmpty else { return }
        let rows = pendingTokens.map { ActivityRow(at: tokensFlushedAt, session: $0.key, kind: .tokens, value: $0.value) }
        pendingTokens = [:]
        store?.record(rows)
        activityVersion += 1
    }

    /// At launch, before the first tick: the time the app was not running counts as away, and
    /// lanes still open then end when it stopped (nothing was watching after that). The first
    /// launch also rebuilds what the session history knows of the time before.
    private func beginActivity() {
        guard let store else { return }
        store.purgeActivity()
        let now = Date()
        if let since = store.meta(Self.recordedKey) {
            recordedSince = Date(timeIntervalSince1970: since)
        } else {
            let since = store.firstActivity() ?? now
            store.record(ActivityBackfill.rows(Array(sessions.values), before: since),
                         meta: [Self.recordedKey: since.timeIntervalSince1970])
            recordedSince = since
        }
        // Away when the app stopped (or was killed), else from the last sign of life.
        let hb = store.meta(Self.heartbeatKey).map(Date.init(timeIntervalSince1970:))
        let wasAway = store.meta(Self.awayKey).map(Date.init(timeIntervalSince1970:))
        store.deleteMeta(Self.awayKey)
        recordedLanes = store.lanes()
        guard let hb, let from = [hb, wasAway ?? hb].min(), now.timeIntervalSince(hb) > 30 || wasAway != nil else { return }
        var rows = [ActivityRow(at: from, session: "", kind: .away, value: now.timeIntervalSince(from))]
        for id in recordedLanes.keys { rows.append(ActivityRow(at: hb, session: id, kind: .lane)) }
        record(rows)
    }

    /// Lanes as they are now, where the record says otherwise: at launch, and on each tick for
    /// sessions whose lane changed without a state change (retention running out).
    private func syncLanes() {
        let now = Date()
        var rows: [ActivityRow] = []
        for id in Set(recordedLanes.keys).union(sessions.keys) {
            let l = lane(sessions[id])
            if l != recordedLanes[id] { rows.append(ActivityRow(at: now, session: id, kind: .lane, text: l?.rawValue ?? "")) }
        }
        record(rows)
    }

    /// Away once there has been no mouse or keyboard input for `awayAfter`, counted from the last input.
    private func trackAway(now: Date) {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= Self.awayAfter {
            beginAway(at: now.addingTimeInterval(-idle))
        } else {
            endAway(at: now.addingTimeInterval(-idle))
        }
    }

    private func beginAway(at t: Date) {
        guard awaySince == nil else { return }
        awaySince = t
        // Survives a crash or force quit, so that time still counts as away at the next launch.
        store?.setMeta(Self.awayKey, t.timeIntervalSince1970)
    }

    private func endAway(at end: Date) {
        guard let since = awaySince else { return }
        awaySince = nil
        presentSince = end
        store?.deleteMeta(Self.awayKey)
        if end > since { record([ActivityRow(at: since, session: "", kind: .away, value: end.timeIntervalSince(since))]) }
    }

    /// The report for `range`, computed again when something was recorded, at most every few
    /// seconds (views ask on every redraw). A range already over is kept for minutes: only an
    /// absence ending later still reaches into it.
    func report(_ range: DateInterval, buckets: Int = 48, edges: [Date]? = nil) -> ActivityReport {
        guard let store else { return ActivityReport(range: range) }
        let now = Date()
        let key = ReportKey(range: range, buckets: edges.map { $0.count - 1 } ?? buckets)
        if let c = reports[key] {
            let age = now.timeIntervalSince(c.at)
            if range.end <= c.at ? age < 600 : (c.version == activityVersion || age < 5) && age < 30 { return c.report }
        }
        if reports.count > 24 { reports = [:] }
        let r = ActivityReport.compute(rows: store.activity(from: range.start, to: min(range.end, now)),
                                       lanesBefore: store.lanes(before: range.start), range: range, now: now,
                                       awaySince: awaySince, recordedSince: recordedSince, buckets: buckets, edges: edges)
        reports[key] = (activityVersion, now, r)
        return r
    }

    // MARK: Sub-agents

    /// Transcripts already read for a parent link (the header is written once, at start).
    @ObservationIgnored private var linkChecked: Set<String> = []

    /// Links a sub-agent session to its parent, from the transcript header.
    private func linkParent(_ key: String) {
        guard !linkChecked.contains(key), let s = sessions[key], s.parentId == nil, s.agent == .pi,
              let path = s.transcriptPath else { return }
        let url = URL(fileURLWithPath: path)
        // Not written yet: try again on the next event or scan.
        guard let header = SubagentLink.header(transcript: url) else { return }
        linkChecked.insert(key)
        guard let parent = header.parentSession else { return }
        let pk = SessionState.key(s.agent, parent)
        guard pk != key else { return }
        update(key, alert: false) { s in
            guard var s else { return nil }
            s.parentId = pk
            return s
        }
    }

    // MARK: User actions

    /// Turning background-agent tracking off forgets the agents still out; the stuck check then
    /// finishes sessions with nothing after their stopped turn (others go stuck on silence).
    func forgetBackgroundTasks() {
        for key in sessions.keys where sessions[key]?.backgroundTasks != nil {
            update(key, alert: false) { s in
                guard var s else { return nil }
                s.backgroundTasks = nil
                return s
            }
        }
    }

    /// The user looked at the session: a finished turn counts as reviewed, and the clocks for
    /// turning blue and leaving the board start again.
    func markRead(_ key: String) {
        update(key, alert: false) { s in
            guard var s else { return nil }
            s.unreadSince = nil
            s.reviewedAt = Date()
            return s
        }
    }

    /// When the user last clicked each card, so a session waiting on them stops flashing.
    private(set) var acknowledged: [String: Date] = [:]

    func jump(_ key: String) {
        acknowledged[key] = Date()
        // A sub-agent has no window of its own; it runs inside its parent's.
        if let p = sessions[key]?.parentId, sessions[p] != nil { return jump(p) }
        markRead(key)
        guard let s = sessions[key] else { return }
        record([ActivityRow(at: Date(), session: key, kind: .focus)])
        guard Self.isGone(s) else { telemetry.count(.jump(s.terminal)); jumper.jump(to: s); return }
        let runners = waveRunners(for: s)
        let name = s.terminal?.termProgram.flatMap(TerminalJumper.app(forTermProgram:))?.localizedName ?? String(localized: "Terminal")
        let why: String? = s.terminal?.isWave == true && runners.isEmpty ? String(localized: "Wave’s authorization has expired")
            : TerminalJumper.runsResume(s) ? nil
            : s.terminal?.termProgram == "waveterm" ? String(localized: "It’s not known which Wave tab it was in")
            : String(localized: "\(name) doesn’t accept typed-in commands from other apps")
        switch Self.askReopen(s, cannotRun: why.map { ($0, name) }) {
        case .alertFirstButtonReturn: telemetry.count(.resume); jumper.resume(s, wave: runners) { Self.tellResumeFailed(s) }
        case .alertSecondButtonReturn: telemetry.count(.resume); jumper.copyResume(s)
        default: break
        }
    }

    /// Wave terminals that may still run commands in the session's tab, best first: its own token,
    /// then other sessions in that tab, live ones (their block is surely open) before gone ones,
    /// newest first. A token whose block was closed fails and the next is tried.
    private func waveRunners(for s: SessionState) -> [TerminalContext] {
        guard let t = s.terminal, t.isWave else { return [] }
        let others = t.waveTabId.map { tab in
            sessions.values.filter { $0.id != s.id && $0.terminal?.waveTabId == tab && $0.terminal?.waveJWT != nil }
                .sorted { a, b in
                    let (la, lb) = (!Self.isGone(a), !Self.isGone(b))
                    return la != lb ? la : a.lastEventAt > b.lastEventAt
                }
                .compactMap(\.terminal)
        } ?? []
        var seen = Set<String>()
        return ([t] + others).filter { $0.waveJWT.map { seen.insert($0).inserted } ?? false }
    }

    private static func tellResumeFailed(_ s: SessionState) {
        let alert = NSAlert()
        if let icon = BrandMark.image { alert.icon = icon }
        alert.messageText = String(localized: "Couldn’t open it in Wave")
        alert.informativeText = String(localized: "The tab or terminal may be closed, or Wave’s authorization may have expired. The resume command is copied: open a new terminal in Wave and paste it to continue \(s.agent.displayName).")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// `cannotRun`: why the command can't be typed in for the user, and the terminal to go to.
    private static func askReopen(_ s: SessionState, cannotRun: (why: String, app: String)?) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        if let icon = BrandMark.image { alert.icon = icon }
        alert.messageText = String(localized: "\(s.agent.displayName) is no longer running")
        if let (why, app) = cannotRun {
            // Nothing can type into that terminal: go there and paste.
            alert.informativeText = String(localized: "\(why), so it can’t be reopened automatically. YaaKanban will switch to \(app) and copy the resume command: open a new terminal there and paste it to continue.")
            alert.addButton(withTitle: String(localized: "Switch to \(app) and Copy"))
        } else {
            alert.informativeText = String(localized: "Reopen this session in its original terminal?")
            alert.addButton(withTitle: String(localized: "Reopen"))
        }
        alert.addButton(withTitle: String(localized: "Copy Resume Command"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    /// The agent is no longer running this session: it ended, or its process died (a crashed terminal).
    static func isGone(_ s: SessionState) -> Bool {
        s.status == .ended || s.agentPid.map { !ProcessUtil.isAlive($0) } ?? false
    }

    /// Ends a session on the boards: it stays in history and comes back if the agent needs the user.
    func dismiss(_ key: String) {
        update(key, alert: false) { s in
            guard var s else { return nil }
            s.dismissedAt = Date()
            s.unreadSince = nil
            return s
        }
    }

    func undismiss(_ key: String) {
        update(key, alert: false) { s in
            guard var s, s.dismissedAt != nil else { return nil }
            s.dismissedAt = nil
            return s
        }
    }

    /// How far back the panel's search reaches.
    static let searchDays = 14

    /// Top-level sessions active in the last `searchDays` days that match `query` (all of them for
    /// an empty one), most recent first: what the panel's search finds.
    func search(_ query: String) -> [SessionState] {
        let since = Date().addingTimeInterval(-Double(Self.searchDays) * 86400)
        let q = query.trimmingCharacters(in: .whitespaces)
        return sorted(sessions.values.filter {
            $0.parentId == nil && !$0.isUnstarted && $0.quietSince >= since && (q.isEmpty || $0.matches(q))
        })
    }

    /// Puts an ended session back on the boards as a reviewed card, with a fresh retention.
    func restore(_ key: String) {
        update(key, alert: false) { s in
            guard var s else { return nil }
            let now = Date()
            s.dismissedAt = nil
            s.unreadSince = nil
            s.reviewedAt = now
            s.restoredAt = now
            return s
        }
    }

    /// Asks for a new name; an empty one goes back to the agent's title.
    func rename(_ key: String) {
        guard let s = sessions[key] else { return }
        let alert = NSAlert()
        if let icon = BrandMark.image { alert.icon = icon }
        alert.messageText = String(localized: "Rename Session")
        alert.informativeText = String(localized: "Only changes the name shown in YaaKanban. Leave it empty to go back to the agent’s title.")
        let field = NSTextField(string: s.customName ?? s.title)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        telemetry.count(.rename)
        update(key, alert: false) { s in
            guard var s else { return nil }
            s.customName = name.isEmpty ? nil : String(name.prefix(80))
            return s
        }
    }

    func remove(_ key: String) {
        settings.pinned.removeAll { $0 == key }
        sessions[key] = nil
        store?.delete(id: key)
    }
}

extension SessionState {
    static func key(_ agent: AgentKind, _ sessionId: String) -> String { "\(agent.rawValue):\(sessionId)" }
}
