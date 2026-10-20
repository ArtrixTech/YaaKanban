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
let approvalEvents: [AgentKind: String] = [.claudeCode: "PermissionRequest", .opencode: "permission"]

func runHook(agent: AgentKind, event: String) -> Never {
    let stdin = isatty(0) == 0 ? FileHandle.standardInput.readDataToEndOfFile() : Data()
    var payload = JSONValue.parse(stdin) ?? .object([:])
    let pid = env["YAAK_AGENT_PID"].flatMap(Int32.init) ?? ProcessUtil.hookOwner()
    let wantsDecision = approvalEvents[agent] == event

    if wantsDecision, case .object(var o) = payload {
        o[Normalizer.awaitingKey] = .bool(true)
        payload = .object(o)
    }
    // Plugins stamp `ts` (ms) when the event happened; hooks without it use now.
    let at = payload["ts"]?.number.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
    let envelope = HookEnvelope(agent: agent, event: event, receivedAt: at, agentPid: pid,
                                cwd: FileManager.default.currentDirectoryPath,
                                terminal: TerminalContext(environment: env), payload: payload)

    if wantsDecision {
        let wait = TimeInterval(Integrations.approvalTimeout + 5)
        let req = WireRequest(kind: .permission, envelope: envelope, timeout: wait)
        let r = UnixSocket.send(Wire.encode(req), to: paths.socket.path, replyTimeout: wait)
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
    if !UnixSocket.send(Wire.encode(req), to: paths.socket.path).sent {
        try? Wire.spool(req, paths: paths)
    }
    exit(0)
}

func decisionOutput(_ agent: AgentKind, _ d: PermissionDecision) -> String {
    switch agent {
    case .claudeCode:
        var decision: [String: Any] = ["behavior": d.rawValue]
        if d == .deny { decision["message"] = "Denied from YaaKanban" }
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
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
    let yaak = option("--yaak") ?? selfPath()
    let dry = args.contains("--dry-run")
    let explicit = option("--agent") != nil
    if install && !yaak.contains(".app/Contents/Helpers/") {
        print("warning: hooks will point at \(yaak), which is not inside YaaKanban.app")
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
            }
        } catch {
            failed = true
            print("\(i.agent.rawValue): error: \(error)")
        }
    }
    exit(failed ? 1 : 0)
}

func runStatus() -> Never {
    let home = Paths.home(env)
    for i in Integrations.all { print("\(i.agent.rawValue): \(i.status(home: home).rawValue)") }
    let up = UnixSocket.send(Wire.encode(["ping": true]), to: paths.socket.path).sent
    print("app: \(up ? "listening" : "not running") (\(paths.socket.path))")
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
case "snapshot":
    // Debug: ask the running app to render its windows to PNGs.
    let dir = args.count > 1 ? args[1] : "/tmp/yaak-snapshot"
    exit(UnixSocket.send(Wire.encode(["snapshot": URL(fileURLWithPath: dir).path]), to: paths.socket.path).sent ? 0 : 1)
default:
    print(usage)
    exit(args.isEmpty ? 0 : 2)
}
