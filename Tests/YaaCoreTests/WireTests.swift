import Foundation
import Testing
@testable import YaaCore

private func tempPaths() -> Paths {
    // Short base keeps the socket path under the sun_path limit.
    let dir = "/tmp/yaak-\(UUID().uuidString.prefix(8))"
    return Paths(environment: ["YAAK_HOME": dir])
}

@Suite struct WireTests {
    @Test func roundTripWithReply() throws {
        let paths = tempPaths()
        try FileManager.default.createDirectory(at: paths.base, withIntermediateDirectories: true)
        let server = SocketServer(path: paths.socket.path) { line, reply in
            let req = Wire.decode(WireRequest.self, line)
            let decision: PermissionDecision? = req?.kind == .permission ? .allow : nil
            reply(Wire.encode(WireReply(decision: decision)))
        }
        try server.start()
        defer { server.stop() }

        let env = HookEnvelope(agent: .claudeCode, event: "PermissionRequest", payload: .object(["session_id": .string("s")]))
        let r = UnixSocket.send(Wire.encode(WireRequest(kind: .permission, envelope: env, timeout: 2)),
                                to: paths.socket.path, replyTimeout: 2)
        #expect(r.sent)
        #expect(r.reply.flatMap { Wire.decode(WireReply.self, $0) }?.decision == .allow)
    }

    @Test func noListenerFailsFast() {
        let paths = tempPaths()
        let start = Date()
        let r = UnixSocket.send(Data("x\n".utf8), to: paths.socket.path)
        #expect(!r.sent)
        #expect(Date().timeIntervalSince(start) < 0.1)
    }

    @Test func spoolDrainsInOrder() throws {
        let paths = tempPaths()
        for i in 0..<3 {
            let env = HookEnvelope(agent: .pi, event: "e\(i)", receivedAt: Date(timeIntervalSince1970: Double(1000 + i)))
            try Wire.spool(WireRequest(kind: .event, envelope: env), paths: paths)
        }
        #expect(Wire.drainSpool(paths: paths).map(\.envelope.event) == ["e0", "e1", "e2"])
        #expect(Wire.drainSpool(paths: paths).isEmpty)
    }

    @Test func storeSaveLoadPurge() throws {
        let paths = tempPaths()
        let store = try Store(path: paths.database)
        var s = SessionState(agent: .codex, sessionId: "x", at: Date(timeIntervalSince1970: 0))
        s.tools = [ToolCall(id: "1", name: "Bash", summary: "ls", input: "{}", output: "out", isError: false, startedAt: s.startedAt)]
        store.save(s)
        #expect(store.loadAll() == [s])
        store.purgeDetails(now: Date())
        let purged = store.loadAll()[0]
        #expect(purged.tools[0].summary == "ls")
        #expect(purged.tools[0].output == nil)
    }
}
