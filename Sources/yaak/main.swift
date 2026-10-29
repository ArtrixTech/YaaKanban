import Darwin
import Foundation
import YaaCore
import YaaIntegrations

let usage = """
usage:
  yaak hook <agent> <event>            (called by agent hooks; reads payload on stdin)
  yaak install   [--agent <a>] [--dry-run] [--yaak <path>]
  yaak uninstall [--agent <a>] [--dry-run]
  yaak status
  yaak doctor                          (diagnostics to paste into a bug report)
  yaak telemetry [status|on|off]       (opt-in anonymous usage reports, sent by the app)

agents: \(AgentKind.allCases.map(\.rawValue).joined(separator: ", "))
"""

let args = Array(CommandLine.arguments.dropFirst())
let env = ProcessInfo.processInfo.environment
let paths = Paths(environment: env)

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

/// Absolute path of this binary with symlinks resolved, so hooks keep working from `~/.local/bin/yaak`.
func selfPath() -> String {
    let raw = Bundle.main.executablePath ?? CommandLine.arguments[0]
    return URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
}

// MARK: hook

/// Agents whose permission hook can take a decision from the app.
let approvalEvents: [AgentKind: String] = [.claudeCode: "PermissionRequest", .qwen: "PermissionRequest", .zcode: "PermissionRequest",
                                           .copilot: "permissionRequest", .opencode: "permission"]

/// Hooks must return within ~100 ms: reading stdin and sending to the app share one budget from
/// process start. Whatever misses it is dropped (stdin) or spooled (the send).
let hookStarted = Date()
let hookStdinBudget: TimeInterval = 0.06
let hookBudget: TimeInterval = 0.09
let hookStdinLimit = 16 << 20

func runHook(agent: AgentKind, event: String) -> Never {
    let stdin = isatty(0) == 0
        ? UnixSocket.readAll(0, deadline: hookStarted + hookStdinBudget, limit: hookStdinLimit) : Data()
    let sendBy = hookStarted + hookBudget
    // Trim large strings (Edit's originalFile, Write content) so the socket line stays small.
    var payload = Wire.trim(JSONValue.parse(stdin) ?? .object([:]))
    let pid = env["YAAK_AGENT_PID"].flatMap(Int32.init) ?? ProcessUtil.hookOwner()
    // Questions (AskUserQuestion) also arrive as permission requests; never hold those up.
    let tool = (payload["tool_name"] ?? payload["toolName"] ?? payload["tool"])?.string?.lowercased() ?? ""
    let wantsDecision = approvalEvents[agent] == event && !Normalizer.askTools.contains(tool)

    if wantsDecision, case .object(var o) = payload {
        o[Normalizer.awaitingKey] = .bool(true)
        payload = .object(o)
    }
    // Plugins stamp `ts` (ms) when the event happened; hooks without it use now.
    let at = payload["ts"]?.number.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
    // A Claude Code background job (`/bg`) runs under its daemon, whose terminal variables are
    // those of whichever pane happened to start the daemon, not where the job is shown.
    let terminal = env["CLAUDE_CODE_SESSION_KIND"] == "bg" ? TerminalContext()
        : TerminalContext(environment: env, tty: pid.flatMap(ProcessUtil.tty(of:)))
    let envelope = HookEnvelope(agent: agent, event: event, receivedAt: at, agentPid: pid,
                                cwd: FileManager.default.currentDirectoryPath,
                                terminal: terminal, payload: payload,
                                ancestorPids: pid.map { ProcessUtil.ancestors(of: $0) })

    if wantsDecision {
        let wait = TimeInterval(Integrations.approvalTimeout + 5)
        let req = WireRequest(kind: .permission, envelope: envelope, timeout: wait)
        let r = UnixSocket.send(Wire.encode(req), to: paths.socket.path, deadline: sendBy, replyTimeout: wait)
        if r.sent {
            if let d = r.reply.flatMap({ Wire.decode(WireReply.self, $0) })?.decision { print(decisionOutput(agent, d)) }
            exit(0)
        }
        // App is down: record the request, let the agent ask in the terminal.
        var spooled = envelope
        if case .object(var o) = spooled.payload { o[Normalizer.awaitingKey] = .bool(false); spooled.payload = .object(o) }
        try? Wire.spool(WireRequest(kind: .event, envelope: spooled), paths: paths)
        exit(0)
    }

    let req = WireRequest(kind: .event, envelope: envelope)
    if !UnixSocket.send(Wire.encode(req), to: paths.socket.path, deadline: sendBy).sent {
        try? Wire.spool(req, paths: paths)
    }
    exit(0)
}

func decisionOutput(_ agent: AgentKind, _ d: PermissionDecision) -> String {
    switch agent {
    case .claudeCode, .qwen, .zcode:
        var decision: [String: Any] = ["behavior": d.rawValue]
        if d == .deny { decision["message"] = "Denied from YaaKanban" }
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: out), as: UTF8.self)
    case .copilot:
        var out: [String: Any] = ["behavior": d.rawValue]
        if d == .deny { out["message"] = "Denied from YaaKanban" }
        return String(decoding: try! JSONSerialization.data(withJSONObject: out), as: UTF8.self)
    default:
        return d.rawValue
    }
}

// MARK: install / uninstall / status

func selected() -> [any Integration] {
    guard let a = option("--agent") else { return Integrations.all }
    guard let kind = AgentKind(rawValue: a), let i = Integrations.named(kind) else {
        FileHandle.standardError.write(Data("unknown agent \(a)\n".utf8)); exit(2)
    }
    return [i]
}

func runInstall(_ install: Bool) -> Never {
    let home = Paths.home(env)
    let dry = args.contains("--dry-run")
    let explicit = option("--agent") != nil
    let me = selfPath()
    var yaak = option("--yaak") ?? me
    if install && !yaak.contains(".app/Contents/Helpers/") {
        print("warning: hooks will point at \(yaak), which is not inside YaaKanban.app")
    } else if install && option("--yaak") == nil {
        // Hooks call a fixed link, so moving the app does not make agents ask for trust again.
        let link = StableYaak.link(home: home).path
        let app = URL(fileURLWithPath: String(me[..<me.range(of: ".app/Contents/Helpers/")!.lowerBound]) + ".app")
        if !StableYaak.mayClaim(bundle: app, home: home) {
            // Another (installed) copy owns the link; leave it pointing there.
            if FileManager.default.fileExists(atPath: link) { yaak = link }
        } else if dry { yaak = link } else {
            do { yaak = try StableYaak.ensure(home: home, target: me) }
            catch { print("warning: \(error); hooks will point at \(yaak)") }
        }
    }
    var failed = false
    for i in selected() {
        if install && !explicit && !i.isDetected(home: home) { print("\(i.agent.rawValue): not detected, skipped"); continue }
        do {
            let changes = try i.plan(install: install, home: home, yaak: yaak)
            if changes.isEmpty { print("\(i.agent.rawValue): already \(install ? "installed" : "uninstalled")"); continue }
            if dry {
                print("\(i.agent.rawValue): would\n" + Installer.describe(changes))
            } else {
                try Installer.apply(changes)
                print("\(i.agent.rawValue): \(install ? "installed" : "uninstalled")")
                if install, let note = i.postInstallNote { print("  note: \(note)") }
                if install { printSteps(i.pendingSteps(home: home, in: .terminal)) }
            }
        } catch {
            failed = true
            print("\(i.agent.rawValue): error: \(error)")
        }
    }
    exit(failed ? 1 : 0)
}

func printSteps(_ steps: [String]) {
    guard !steps.isEmpty else { return }
    print("  to authorize:")
    for (n, s) in steps.enumerated() { print("    \(n + 1). \(s)") }
}

func runStatus() -> Never {
    let home = Paths.home(env)
    for i in Integrations.all {
        let s = i.status(home: home)
        let steps = s == .installed ? i.pendingSteps(home: home, in: .terminal) : []
        print("\(i.agent.rawValue): \(steps.isEmpty ? s.rawValue : IntegrationStatus.needsAuthorization.rawValue)")
        printSteps(steps)
    }
    let up = UnixSocket.send(Wire.encode(["ping": true]), to: paths.socket.path).sent
    print("app: \(up ? "listening" : "not running") (\(paths.socket.path))")
    exit(0)
}

// MARK: doctor / telemetry

/// The YaaKanban.app this binary is bundled in, if any.
func appBundle() -> Bundle? {
    let app = URL(fileURLWithPath: selfPath()).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return app.pathExtension == "app" ? Bundle(url: app) : nil
}

func runDoctor() -> Never {
    let up = UnixSocket.send(Wire.encode(["ping": true]), to: paths.socket.path).sent
    let d = Diagnostics.gather(paths: paths, home: Paths.home(env), yaak: selfPath(),
                               env: TelemetryEnvironment.current(bundle: appBundle() ?? .main), appListening: up,
                               telemetry: TelemetryLedger.load(paths.telemetry).enabled)
    print(d.markdown)
    exit(0)
}

func runTelemetry() -> Never {
    switch args.dropFirst().first ?? "status" {
    case "on":
        if Telemetry.doNotTrack(env) { print("DO_NOT_TRACK is set; telemetry stays off"); exit(1) }
        TelemetryLedger.update(paths.telemetry) { $0.set(enabled: true) }
        print("telemetry: on (the app sends one anonymous report per day; see docs/telemetry.md)")
    case "off":
        TelemetryLedger.update(paths.telemetry) { $0.set(enabled: false) }
        print("telemetry: off (counts cleared)")
    case "status":
        let l = TelemetryLedger.load(paths.telemetry)
        // The app, launched from Finder or at login, does not see this shell's DO_NOT_TRACK.
        let state = !l.enabled ? "off" : Telemetry.doNotTrack(env)
            ? "on (DO_NOT_TRACK in this shell does not reach the app; run `yaak telemetry off`)" : "on"
        print("telemetry: \(state)")
        if l.enabled, let id = l.installId { print("install id: \(id)") }
        if let s = l.lastSent { print("last reported day: \(s)") }
        if let r = l.lastResult {
            let outcome = r.ok ? "accepted" : r.error ?? "HTTP \(r.status.map(String.init) ?? "?")"
            print("last send: \(r.at.formatted(date: .numeric, time: .shortened)), \(r.days.joined(separator: " ")): \(outcome)")
        }
        let appKey = appBundle()?.object(forInfoDictionaryKey: Telemetry.appKeyKey) as? String ?? ""
        let usable = AptabaseEvent.ingestURL(appKey: appKey) != nil
        print("Aptabase: \(usable ? "configured" : "no usable App Key in this build (nothing is sent)")")
    default:
        print(usage); exit(2)
    }
    exit(0)
}

switch args.first {
case "hook":
    // Never fail an agent because of a bad invocation.
    guard args.count >= 3, let agent = AgentKind(rawValue: args[1]) else { exit(0) }
    runHook(agent: agent, event: args[2])
case "install": runInstall(true)
case "uninstall": runInstall(false)
case "status": runStatus()
case "doctor": runDoctor()
case "telemetry": runTelemetry()
case "snapshot":
    // Debug: ask the running app to render its windows to PNGs.
    let dir = args.count > 1 ? args[1] : "/tmp/yaak-snapshot"
    exit(UnixSocket.send(Wire.encode(["snapshot": URL(fileURLWithPath: dir).path]), to: paths.socket.path).sent ? 0 : 1)
default:
    print(usage)
    exit(args.isEmpty ? 0 : 2)
}
