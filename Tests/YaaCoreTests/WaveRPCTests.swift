import Foundation
import Testing
@testable import YaaCore

/// A stand-in for Wave's socket: one connection, one JSON request per line, answered by `reply`
/// (nil: no answer). Each answer is preceded by an unrelated event line, as Wave may send them.
private final class FakeWave: @unchecked Sendable {
    let path = "/tmp/yaak-w\(UUID().uuidString.prefix(8)).sock"
    let jwt: String
    private(set) var requests: [JSONValue] = []
    private let fd: Int32
    private let lock = NSLock()

    init(reply: @escaping @Sendable (JSONValue) -> JSONValue?) throws {
        jwt = Self.jwt(sock: path)
        unlink(path)
        guard var addr = UnixSocket.address(path) else { throw POSIXError(.ENAMETOOLONG) }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
        }
        guard bound, listen(fd, 4) == 0 else { throw POSIXError(.EADDRINUSE) }
        let listenFd = fd
        Thread.detachNewThread { [self] in
            let c = accept(listenFd, nil, nil)
            guard c >= 0 else { return }
            defer { close(c) }
            var pending = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(c, &buf, buf.count)
                guard n > 0 else { return }
                pending.append(contentsOf: buf[0..<n])
                while let i = pending.firstIndex(of: 0x0A) {
                    let line = pending.prefix(upTo: i)
                    pending.removeSubrange(...i)
                    guard let req = JSONValue.parse(Data(line)) else { continue }
                    lock.withLock { requests.append(req) }
                    guard let answer = reply(req) else { continue }
                    var out = Data("{\"command\":\"eventrecv\",\"data\":{}}\n".utf8)
                    out.append(try! JSONEncoder().encode(answer))
                    out.append(0x0A)
                    _ = UnixSocket.writeAll(c, out)
                }
            }
        }
    }

    var seen: [JSONValue] { lock.withLock { requests } }

    deinit { close(fd); unlink(path) }

    /// A token naming this socket, shaped like Wave's (header.claims.signature, base64url).
    static func jwt(sock: String) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        let claims = try! enc.encode(JSONValue.object(["sock": .string(sock), "blockid": .string("b1")]))
        let b64 = claims.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(b64).sig"
    }
}

@Suite struct WaveRPCTests {
    private func ok(_ req: JSONValue, _ data: JSONValue? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["resid": req["reqid"] ?? .null]
        if let data { o["data"] = data }
        return .object(o)
    }

    @Test func readsShellStateAndTypes() throws {
        let wave = try FakeWave { [self] req in
            switch req["command"]?.string {
            case "authenticate": return ok(req, .object(["routeid": .string("proc:1")]))
            case "getrtinfo": return ok(req, .object(["shell:state": .string("ready"), "shell:type": .string("zsh")]))
            default: return ok(req)
            }
        }
        let rpc = try #require(WaveRPC(jwt: wave.jwt, timeout: 2))
        #expect(rpc.shellState(block: "b1") == "ready")
        #expect(rpc.type(WaveResume.typedLine("claude --resume 's'", cwd: "/tmp/a b"), block: "b1"))

        let reqs = wave.seen
        #expect(reqs.map { $0["command"]?.string } == ["authenticate", "getrtinfo", "controllerinput"])
        #expect(reqs[0]["route"]?.string == "$control")
        #expect(reqs[0]["data"]?.string == wave.jwt)
        #expect(reqs[1]["data"]?["oref"]?.string == "block:b1")
        #expect(reqs[2]["data"]?["blockid"]?.string == "b1")
        let typed = try #require(reqs[2]["data"]?["inputdata64"]?.string.flatMap { Data(base64Encoded: $0) })
        #expect(String(decoding: typed, as: UTF8.self) == "\u{05}\u{15}cd '/tmp/a b' && claude --resume 's'\r")
        #expect(Set(reqs.compactMap { $0["reqid"]?.string }).count == 3)
    }

    @Test func errorsAndSilenceAreFailures() throws {
        let wave = try FakeWave { [self] req in
            switch req["command"]?.string {
            case "authenticate": return ok(req)
            case "getrtinfo": return ok(req) // no rtinfo for the block: state unknown
            case "controllerinput" where req["data"]?["blockid"]?.string == "gone":
                return .object(["resid": req["reqid"] ?? .null, "error": .string("no shell input chan")])
            default: return nil
            }
        }
        let rpc = try #require(WaveRPC(jwt: wave.jwt, timeout: 1))
        #expect(rpc.shellState(block: "b1") == nil)
        #expect(!rpc.type("x", block: "gone"))
        // Sent but never answered: it may have arrived, so it must not be run again elsewhere.
        #expect(rpc.type("x", block: "b1"))
    }

    @Test func shellAtPromptNeedsAShellInTheForeground() {
        #expect(!ProcessUtil.shellAtPrompt(tty: "/dev/null"))
        #expect(!ProcessUtil.shellAtPrompt(tty: "/dev/ttys999"))
        // The test runner itself is in the foreground of its terminal, if it has one.
        if let tty = ProcessUtil.tty(of: getpid()) { #expect(!ProcessUtil.shellAtPrompt(tty: tty)) }
    }

    @Test func rejectedTokenOrNoSocket() throws {
        let wave = try FakeWave { req in .object(["resid": req["reqid"] ?? .null, "error": .string("invalid token")]) }
        #expect(WaveRPC(jwt: wave.jwt, timeout: 1) == nil)
        #expect(WaveRPC(jwt: "not-a-jwt") == nil)
        let start = Date()
        #expect(WaveRPC(jwt: FakeWave.jwt(sock: "/tmp/yaak-none.sock"), timeout: 1) == nil)
        #expect(Date().timeIntervalSince(start) < 0.5)
    }
}
