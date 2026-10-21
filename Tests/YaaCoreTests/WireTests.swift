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

    /// A line cut short (no newline) was spooled by the sender; the server must not handle it too.
    @Test func serverIgnoresUnterminatedLine() throws {
        let paths = tempPaths()
        try FileManager.default.createDirectory(at: paths.base, withIntermediateDirectories: true)
        let seen = OnceFlag()
        let server = SocketServer(path: paths.socket.path) { _, reply in _ = seen.claim(); reply(nil) }
        try server.start()
        defer { server.stop() }
        #expect(UnixSocket.send(Data("{\"x\":1}".utf8), to: paths.socket.path).sent)
        usleep(100_000)
        #expect(seen.claim()) // handler never ran
    }

    @Test func noListenerFailsFast() {
        let paths = tempPaths()
        let start = Date()
        let r = UnixSocket.send(Data("x\n".utf8), to: paths.socket.path)
        #expect(!r.sent)
        #expect(Date().timeIntervalSince(start) < 0.1)
    }

    /// A listener that accepts but never reads must not hold a hook past its deadline.
    @Test func sendGivesUpAtDeadline() throws {
        let paths = tempPaths()
        try FileManager.default.createDirectory(at: paths.base, withIntermediateDirectories: true)
        guard var addr = UnixSocket.address(paths.socket.path) else { Issue.record("path too long"); return }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd); unlink(paths.socket.path) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(bound == 0 && listen(fd, 1) == 0)

        let start = Date()
        let r = UnixSocket.send(Data(repeating: 0x61, count: 8 << 20), to: paths.socket.path,
                                deadline: start + 0.05)
        #expect(!r.sent)
        #expect(Date().timeIntervalSince(start) < 0.15)
    }

    /// An agent that keeps stdin open must not hold the hook either.
    @Test func readAllStopsAtDeadlineAndLimit() {
        var p: [Int32] = [0, 0]
        #expect(pipe(&p) == 0)
        defer { close(p[0]); close(p[1]) }
        _ = Data("{\"a\":1}".utf8).withUnsafeBytes { write(p[1], $0.baseAddress!, $0.count) }

        let start = Date()
        let d = UnixSocket.readAll(p[0], deadline: start + 0.05, limit: 1 << 20)
        #expect(d == Data("{\"a\":1}".utf8))
        #expect(Date().timeIntervalSince(start) < 0.15)

        _ = Data(repeating: 0x62, count: 100).withUnsafeBytes { write(p[1], $0.baseAddress!, $0.count) }
        #expect(UnixSocket.readAll(p[0], deadline: Date() + 1, limit: 10).count == 10)
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
