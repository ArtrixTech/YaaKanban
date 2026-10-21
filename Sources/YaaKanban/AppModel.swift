import AppKit
import Foundation
import Observation
import YaaCore

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

    var serverError: String?
    /// Debug hook: render windows to PNGs (`yaak snapshot <dir>`), for verification without screen recording.
    @ObservationIgnored var onSnapshot: ((URL) -> Void)?
    /// Session selected in the main window.
    var selection: String?

    // MARK: Derived views

    /// Active sessions for the floating panel; idle and ended ones only for a while (24 h by default).
    /// Sub-agents of a session on the board show inside its card instead.
    var activeSessions: [SessionState] {
        let now = Date()
        let live = sessions.values.filter { isLive($0, now: now) }
        let shown = Set(live.map(\.id))
        return sorted(live.filter { s in s.parentId.map { !shown.contains($0) } ?? true })
    }

    /// Live sub-agent sessions of `key`, oldest first.
    func subagents(of key: String) -> [SessionState] {
        let now = Date()
        return sessions.values.filter { $0.parentId == key && isLive($0, now: now) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private func isLive(_ s: SessionState, now: Date) -> Bool {
        if s.dismissedAt != nil { return false }
        switch s.status {
        // However it ended (an exit, or a terminal crash that looks just like one), the conversation
        // lingers like a reviewed card so it can be resumed, unless the same process went on with a
        // new session (`/clear`, `/new`).
        case .ended:
            if s.parentId != nil || now.timeIntervalSince(s.quietSince) >= settings.idleVisibleSeconds { return false }
            // One process may host sibling sessions (OpenCode, the Codex app): only a top-level
            // session started after this one's last event replaced it.
            guard let pid = s.agentPid else { return true }
            return !sessions.values.contains {
                $0.agentPid == pid && $0.id != s.id && $0.parentId == nil && $0.startedAt >= s.lastEventAt
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

    var allSessions: [SessionState] { sorted(Array(sessions.values)) }

    /// Active sessions as the boards show them: most urgent first, then the user's order or start order.
    var board: [SessionState] { Board.ordered(activeSessions, manualOrder: settings.manualOrder) }

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
        // Sessions that were live when the app quit may have ended meanwhile.
        tick()

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
        for req in Wire.drainSpool(paths: paths) { ingest(req.envelope, alert: false) }

        notifier.onAction = { [weak self] key, requestId, action in
            self?.handleNotificationAction(key: key, requestId: requestId, action: action)
        }
        notifier.requestAuthorization()

        timers.append(Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        timers.append(Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        })
        // Common modes: keep going while a dialog or menu is open.
        for t in timers { RunLoop.main.add(t, forMode: .common) }
        scan()
    }

    func stop() {
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
            key = update(SessionState.key(ev.agent, ev.sessionId), alert: alert) { SessionReducer.apply(ev, to: $0) }
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
        store?.save(new)
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

    // MARK: Sub-agents

    /// Transcripts already read for a parent link (the header is written once, at start).
    @ObservationIgnored private var linkChecked: Set<String> = []

    /// Links a sub-agent session to its parent, from the transcript header.
    private func linkParent(_ key: String) {
        guard !linkChecked.contains(key), let s = sessions[key], s.parentId == nil, s.agent == .pi,
              let path = s.transcriptPath else { return }
        let url = URL(fileURLWithPath: path)
        // Not written yet: try again on the next event or scan.
        guard FileManager.default.fileExists(atPath: path) else { return }
        linkChecked.insert(key)
        guard let parent = SubagentLink.parentSession(transcript: url) else { return }
        let pk = SessionState.key(s.agent, parent)
        guard pk != key else { return }
        update(key, alert: false) { s in
            guard var s else { return nil }
            s.parentId = pk
            return s
        }
    }

    // MARK: User actions

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
        guard Self.isGone(s) else { jumper.jump(to: s); return }
        let runners = waveRunners(for: s)
        switch Self.askReopen(s, canRun: s.terminal?.isWave != true || !runners.isEmpty) {
        case .alertFirstButtonReturn: jumper.resume(s, wave: runners) { Self.tellResumeFailed(s) }
        case .alertSecondButtonReturn: jumper.copyResume(s)
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
        alert.messageText = "没能在 Wave 里打开"
        alert.informativeText = "原标签页或终端可能已关闭，Wave 的授权也可能已过期。恢复命令已复制，在 Wave 里新开一个终端粘贴即可继续 \(s.agent.displayName)。"
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func askReopen(_ s: SessionState, canRun: Bool) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        if let icon = BrandMark.image { alert.icon = icon }
        alert.messageText = "\(s.agent.displayName) 进程已不在"
        if canRun {
            alert.informativeText = "是否在原终端重新打开这个会话？"
            alert.addButton(withTitle: "重新打开")
        } else {
            // Nothing can type into that Wave tab any more: go there and paste.
            alert.informativeText = "Wave 的授权已过期，无法自动打开。将切到 Wave 并复制恢复命令，在原标签页新开一个终端粘贴即可继续。"
            alert.addButton(withTitle: "切到 Wave 并复制")
        }
        alert.addButton(withTitle: "复制恢复命令")
        alert.addButton(withTitle: "取消")
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

    func remove(_ key: String) {
        sessions[key] = nil
        store?.delete(id: key)
    }
}

extension SessionState {
    static func key(_ agent: AgentKind, _ sessionId: String) -> String { "\(agent.rawValue):\(sessionId)" }
}
