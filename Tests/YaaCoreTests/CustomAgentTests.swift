import Foundation
import Testing
@testable import YaaCore

@Suite struct CustomAgentTests {
    private func tempDir() -> URL {
        let dir = URL(fileURLWithPath: "/tmp/yaak-custom-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func idSanitizationAndValidation() {
        #expect(CustomAgent.sanitizeId("My Cool Agent!") == "my-cool-agent")
        #expect(CustomAgent.sanitizeId("  ...--Bot_2.0--  ") == "bot_2.0")
        #expect(CustomAgent.sanitizeId("a:b/c\\d") == "a-b-c-d")
        #expect(CustomAgent.sanitizeId("../../etc/passwd") == "etc-passwd")
        #expect(CustomAgent.sanitizeId("foo..bar") == "foo.bar")
        #expect(CustomAgent.sanitizeId(String(repeating: "x", count: 80)).count == CustomAgent.maxIdLength)
        #expect(CustomAgent.sanitizeId("!!!") == "")

        #expect(CustomAgent.isValidId("my-agent"))
        #expect(CustomAgent.isValidId("bot_2.0"))
        #expect(!CustomAgent.isValidId(""))
        #expect(!CustomAgent.isValidId("-bad"))
        #expect(!CustomAgent.isValidId(".bad"))
        #expect(!CustomAgent.isValidId("Upper"))
        #expect(!CustomAgent.isValidId("has:colon"))
        #expect(!CustomAgent.isValidId("has space"))
        #expect(!CustomAgent.isValidId("../escape"))
        #expect(!CustomAgent.isValidId("a/b"))
        #expect(!CustomAgent.isValidId("a..b"))
    }

    @Test func monograms() {
        #expect(CustomAgent.monogram(from: "My Agent") == "MA")
        #expect(CustomAgent.monogram(from: "my-bot") == "MB")
        #expect(CustomAgent.monogram(from: "goose") == "GO")
        #expect(CustomAgent.monogram(from: "小助手") == "小")
        let custom = CustomAgent(id: "g", name: "Goose", icon: CustomAgentIcon(kind: .monogram, value: "gs"))
        #expect(custom.monogram == "GS")
    }

    @Test func resumeCommandTemplate() {
        let a = CustomAgent(id: "goose", name: "Goose", resumeCommandTemplate: "goose session --resume {session_id}")
        #expect(a.resumeCommand(sessionId: "abc-123") == "goose session --resume 'abc-123'")
        #expect(a.resumeCommand(sessionId: "has space") == "goose session --resume 'has space'")
        // Shell injection payload is safely single-quoted, never executed.
        #expect(a.resumeCommand(sessionId: "x'; touch /tmp/pwned; '") == "goose session --resume 'x'\\''; touch /tmp/pwned; '\\'''")
        // Guard against leading dash flag injection.
        #expect(a.resumeCommand(sessionId: "-evil") == nil)
        #expect(a.resumeCommand(sessionId: "") == nil)

        let b = CustomAgent(id: "b", name: "B", resumeCommandTemplate: "mycli --continue")
        #expect(b.resumeCommand(sessionId: "s1") == "mycli --continue")

        let c = CustomAgent(id: "c", name: "C", resumeCommandTemplate: nil)
        #expect(c.resumeCommand(sessionId: "s1") == nil)

        let s = SessionState(agent: .custom, sessionId: "s1", at: Date(), customAgentId: "goose")
        #expect(s.resumeCommand == nil)
        #expect(s.resumeCommand(customAgent: a) == "goose session --resume 's1'")
    }

    @Test func storeRoundTripAndMinimalJSON() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("custom-agents.json")

        let agent = CustomAgent(
            id: "goose", name: "Goose", protocol: .claude, supportsApproval: false,
            resumeCommandTemplate: "goose --resume {session_id}",
            icon: CustomAgentIcon(kind: .symbol, value: "bird.fill", color: .teal),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try CustomAgentStore.save([agent], to: file)
        let loaded = CustomAgentStore.load(from: file)
        #expect(loaded == [agent])
        #expect(CustomAgentStore.find("goose", at: file) == agent)
        #expect(CustomAgentStore.find("missing", at: file) == nil)

        // Minimal hand-edited JSON decodes with sensible defaults.
        let minimal = Data("[{\"id\": \"aider\", \"name\": \"Aider\"}]\n".utf8)
        try minimal.write(to: file)
        let minLoaded = CustomAgentStore.load(from: file)
        #expect(minLoaded.count == 1)
        #expect(minLoaded[0].id == "aider")
        #expect(minLoaded[0].name == "Aider")
        #expect(minLoaded[0].protocol == .generic)
        #expect(minLoaded[0].supportsApproval == true)
        #expect(minLoaded[0].icon.kind == .monogram)
        #expect(minLoaded[0].icon.color == .auto)
    }

    @Test func agentIdentityParsing() {
        #expect(AgentIdentity.from(sessionKey: "claude-code:abc") == AgentIdentity(.claudeCode))
        #expect(AgentIdentity.from(sessionKey: "custom:goose:s1") == AgentIdentity(.custom, customId: "goose"))
        #expect(AgentIdentity.from(sessionKey: "custom:goose:part:with:colons") == AgentIdentity(.custom, customId: "goose"))
        #expect(AgentIdentity.from(sessionKey: "custom:s1") == AgentIdentity(.custom, customId: nil))
        #expect(AgentIdentity.from(sessionKey: "unknown:s1") == nil)
    }

    @Test func legacyDecodingBackwardCompatibility() throws {
        // Legacy HookEnvelope without customAgentId or customFormat.
        let envJSON = """
        {"agent":"claude-code","event":"Stop","receivedAt":1700000000000,"terminal":{},"payload":{"session_id":"s1"}}
        """
        let env = Wire.decode(HookEnvelope.self, Data(envJSON.utf8))
        #expect(env != nil)
        #expect(env?.agent == .claudeCode)
        #expect(env?.customAgentId == nil)
        #expect(env?.customFormat == nil)

        // Legacy SessionState without customAgentId.
        let s = SessionState(agent: .codex, sessionId: "t1", at: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)
        #expect(decoded.id == "codex:t1")
        #expect(decoded.customAgentId == nil)
    }

    @Test func normalizerGenericCustomEvents() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func norm(_ event: String, _ payload: [String: JSONValue]) -> [AgentEvent] {
            let env = HookEnvelope(agent: .custom, event: event, receivedAt: t0, cwd: "/tmp/proj",
                                   payload: .object(payload), customAgentId: "my-bot", customFormat: .generic)
            return Normalizer.normalize(env)
        }

        let start = norm("session-start", ["session_id": .string("s1")])
        #expect(start.count == 1)
        #expect(start[0].kind == .sessionStart)
        #expect(start[0].customAgentId == "my-bot")

        let prompt = norm("prompt", ["sessionId": .string("s1"), "prompt": .string("Fix tests")])
        #expect(prompt.first?.kind == .promptSubmitted("Fix tests"))

        let ts = norm("tool-start", ["session_id": .string("s1"), "id": .string("c1"), "toolName": .string("bash"),
                                     "toolInput": .object(["command": .string("ls")])])
        #expect(ts.first?.kind == .toolStart(id: "c1", name: "bash", input: .object(["command": .string("ls")])))

        let te = norm("tool-end", ["session_id": .string("s1"), "id": .string("c1"), "tool": .string("bash"),
                                   "output": .string("boom"), "isError": .bool(true)])
        #expect(te.first?.kind == .toolEnd(id: "c1", name: "bash", output: "boom", isError: true))

        let perm = norm("permission-request", ["session_id": .string("s1"), "id": .string("c2"), "tool": .string("bash"),
                                               "input": .object(["command": .string("rm -rf /tmp/x")]),
                                               Normalizer.awaitingKey: .bool(true)])
        if case .permission(let req) = perm.first?.kind {
            #expect(req.id == "c2")
            #expect(req.tool == "bash")
            #expect(req.awaitingDecision == true)
        } else {
            Issue.record("expected permission event")
        }

        let ask = norm("needs-input", ["session_id": .string("s1"), "message": .string("Continue?")])
        #expect(ask.first?.kind == .needsInput("Continue?"))

        let ans = norm("input-answered", ["session_id": .string("s1")])
        #expect(ans.first?.kind == .inputAnswered)

        let end = norm("turn-end", ["session_id": .string("s1"), "message": .string("Done")])
        #expect(end.first?.kind == .turnEnd(lastMessage: "Done"))

        let intr = norm("interrupted", ["session_id": .string("s1")])
        #expect(intr.first?.kind == .interrupted(lastMessage: nil))

        let subStart = norm("subagent-start", ["session_id": .string("s1"), "subagent_id": .string("sub1"), "type": .string("search")])
        #expect(subStart.first?.kind == .subagentStart(id: "sub1", type: "search"))

        let subStop = norm("subagent-stop", ["session_id": .string("s1"), "subagent_id": .string("sub1")])
        #expect(subStop.first?.kind == .subagentStop(id: "sub1"))

        let title = norm("title", ["session_id": .string("s1"), "title": .string("Refactor auth")])
        #expect(title.first?.kind == .titleChanged("Refactor auth"))

        let bye = norm("session-end", ["session_id": .string("s1")])
        #expect(bye.first?.kind == .sessionEnd)
    }

    @Test func normalizerClaudeCompatibleCustomEvents() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // Auto-detect Claude schema when customFormat is nil and event is PascalCase Claude event.
        let env = HookEnvelope(
            agent: .custom, event: "PermissionRequest", receivedAt: t0, cwd: "/tmp/p",
            payload: .object([
                "session_id": .string("c1"),
                "tool_name": .string("Bash"),
                "tool_use_id": .string("tu1"),
                "tool_input": .object(["command": .string("echo hi")]),
                Normalizer.awaitingKey: .bool(true),
            ]),
            customAgentId: "claude-fork", customFormat: nil
        )
        let evs = Normalizer.normalize(env)
        #expect(evs.count == 1)
        #expect(evs[0].customAgentId == "claude-fork")
        if case .permission(let req) = evs[0].kind {
            #expect(req.id == "tu1")
            #expect(req.tool == "Bash")
            #expect(req.awaitingDecision == true)
        } else {
            Issue.record("expected permission event from auto-detected Claude schema")
        }

        // Explicit customFormat: .claude with Stop event.
        let stopEnv = HookEnvelope(
            agent: .custom, event: "Stop", receivedAt: t0,
            payload: .object(["session_id": .string("c1"), "last_assistant_message": .string("Ready")]),
            customAgentId: "claude-fork", customFormat: .claude
        )
        #expect(Normalizer.normalize(stopEnv).first?.kind == .turnEnd(lastMessage: "Ready"))
    }

    @Test func reducerIsolatesCustomAgentsWithSameSessionId() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let eA = AgentEvent(agent: .custom, sessionId: "default", at: t0, kind: .promptSubmitted("hello A"), customAgentId: "bot-a")
        let eB = AgentEvent(agent: .custom, sessionId: "default", at: t0, kind: .promptSubmitted("hello B"), customAgentId: "bot-b")
        let sA = SessionReducer.apply(eA, to: nil)
        let sB = SessionReducer.apply(eB, to: nil)
        #expect(sA.id == "custom:bot-a:default")
        #expect(sB.id == "custom:bot-b:default")
        #expect(sA.id != sB.id)
        #expect(sA.customAgentId == "bot-a")
        #expect(sB.customAgentId == "bot-b")
        #expect(sA.matches("Bot Alpha", agentDisplayName: "Bot Alpha"))
        #expect(sA.matches("bot-a"))
    }

    @Test func aiPromptAndSnippet() {
        let g = CustomAgent(id: "my-bot", name: "My Bot", protocol: .generic, supportsApproval: true)
        let gPrompt = g.aiPrompt(yaakPath: "/usr/local/bin/yaak")
        #expect(gPrompt.contains("--id my-bot"))
        #expect(gPrompt.contains("tool_start"))
        #expect(gPrompt.contains("permission"))

        let c = CustomAgent(id: "fork-cc", name: "Fork CC", protocol: .claude, supportsApproval: true)
        let cPrompt = c.aiPrompt(yaakPath: "/usr/local/bin/yaak")
        #expect(cPrompt.contains("--id fork-cc --format claude"))
        #expect(cPrompt.contains("PermissionRequest"))
    }

    @Test func yaakCLICustomHookEndToEnd() throws {
        // Locate the built `yaak` binary next to the test bundle / build products.
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/out/Products/Debug/yaak"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/debug/yaak"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/arm64-apple-macosx/debug/yaak"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/x86_64-apple-macosx/debug/yaak"),
        ]
        guard let yaak = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) else {
            return
        }

        let dir = tempDir()
        defer { try? fm.removeItem(at: dir) }
        let paths = Paths(environment: ["YAAK_HOME": dir.path])

        // 1) Unknown / unregistered custom id with no app running -> exits 0 and spools.
        do {
            let p = Process()
            p.executableURL = yaak
            p.arguments = ["hook", "custom", "prompt", "--id", "unregistered-bot", "--session", "s42", "--prompt", "hi from cli"]
            p.environment = ["HOME": dir.path, "YAAK_HOME": dir.path]
            p.standardInput = Pipe()
            (p.standardInput as! Pipe).fileHandleForWriting.closeFile()
            try p.run()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0)

            var replayed: [WireRequest] = []
            Wire.drainSpool(paths: paths) { replayed.append($0) }
            #expect(replayed.count == 1)
            #expect(replayed[0].envelope.agent == .custom)
            #expect(replayed[0].envelope.customAgentId == "unregistered-bot")
            #expect(replayed[0].envelope.payload["session_id"]?.string == "s42")
            #expect(replayed[0].envelope.payload["prompt"]?.string == "hi from cli")
        }

        // 2) Blocking permission with Claude format via --agent custom --format claude -> returns Claude JSON decision.
        do {
            let server = SocketServer(path: paths.socket.path) { line, reply in
                let req = Wire.decode(WireRequest.self, line)
                let decision: PermissionDecision? = req?.kind == .permission ? .allow : nil
                reply(Wire.encode(WireReply(decision: decision)))
            }
            try server.start()
            defer { server.stop() }

            let p = Process()
            p.executableURL = yaak
            p.arguments = ["hook", "--agent", "custom", "--id", "my-claude", "--format", "claude", "PermissionRequest"]
            p.environment = ["HOME": dir.path, "YAAK_HOME": dir.path]
            let inPipe = Pipe(), outPipe = Pipe()
            p.standardInput = inPipe
            p.standardOutput = outPipe
            try p.run()
            inPipe.fileHandleForWriting.write(Data("{\"session_id\":\"c9\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}".utf8))
            inPipe.fileHandleForWriting.closeFile()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0)
            let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            #expect(out.contains("\"hookEventName\":\"PermissionRequest\""))
            #expect(out.contains("\"behavior\":\"allow\""))

            // 3) Blocking permission with generic format -> returns plain "allow".
            let p2 = Process()
            p2.executableURL = yaak
            p2.arguments = ["hook", "custom", "permission", "--id", "my-generic", "--session", "g1", "--tool", "bash"]
            p2.environment = ["HOME": dir.path, "YAAK_HOME": dir.path]
            let inPipe2 = Pipe(), outPipe2 = Pipe()
            p2.standardInput = inPipe2
            p2.standardOutput = outPipe2
            try p2.run()
            inPipe2.fileHandleForWriting.closeFile()
            p2.waitUntilExit()
            #expect(p2.terminationStatus == 0)
            let out2 = String(decoding: outPipe2.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(out2 == "allow")
        }

        // 4) Resilience: corrupt custom-agents.json, unknown event, missing --id, non-JSON stdin all exit 0 quickly.
        try Data("{not valid json!!!".utf8).write(to: paths.customAgents)
        let badCases: [([String], String)] = [
            (["hook", "custom", "unknown_event", "--id", "bot"], "{}"),
            (["hook", "custom", "prompt"], "{\"session_id\":\"s1\",\"prompt\":\"hi\"}"),
            (["hook", "custom", "prompt", "--id", "bot"], "<<<not json at all>>>"),
            (["hook", "custom"], ""),
        ]
        for (argv, stdinText) in badCases {
            let start = Date()
            let p = Process()
            p.executableURL = yaak
            p.arguments = argv
            p.environment = ["HOME": dir.path, "YAAK_HOME": dir.path]
            let inPipe = Pipe()
            p.standardInput = inPipe
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            if !stdinText.isEmpty { inPipe.fileHandleForWriting.write(Data(stdinText.utf8)) }
            inPipe.fileHandleForWriting.closeFile()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0, "args=\(argv)")
            #expect(Date().timeIntervalSince(start) < 0.5, "args=\(argv) took too long")
        }
    }
}
