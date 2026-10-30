import Foundation

/// Wave's own RPC (newline-delimited JSON on the socket named in a block's JWT), for what `wsh`
/// has no command for: reading a block's shell state and typing into it.
public final class WaveRPC {
    private let fd: Int32
    private var buffer = Data()
    private var nextId = 0
    private let deadline: Date

    /// Connects to the socket the token names and authenticates with it; nil when either fails.
    /// `timeout` bounds the whole connection, every call included: open one per task.
    public init?(jwt: String, timeout: TimeInterval = 2) {
        deadline = Date().addingTimeInterval(timeout)
        guard var path = Self.claims(jwt)?["sock"]?.string else { return nil }
        if path.hasPrefix("~/") { path = Paths.home().path + path.dropFirst(1) }
        guard var addr = UnixSocket.address(path) else { return nil }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        // A failed init past this point still runs deinit, which closes the socket.
        guard ok, case .data = call("authenticate", .string(jwt), route: "$control") else { return nil }
    }

    deinit { close(fd) }

    /// The block's shell as Wave's shell integration last reported it: `ready` at a prompt,
    /// `running-command` while a command runs, nil when unknown (no integration, block not shown
    /// since its shell started, or the block is gone).
    public func shellState(block: String) -> String? {
        guard case .data(let info) = call("getrtinfo", .object(["oref": .string("block:\(block)")])) else { return nil }
        return info["shell:state"]?.string
    }

    /// Writes `text` to the block's terminal as typed input. False only when it surely did not
    /// arrive: the request was not sent, or Wave refused it (the block or its shell is gone). Sent
    /// but unanswered counts as typed, so the caller doesn't run the command a second time elsewhere.
    public func type(_ text: String, block: String) -> Bool {
        let data = Data(text.utf8).base64EncodedString()
        switch call("controllerinput", .object(["blockid": .string(block), "inputdata64": .string(data)])) {
        case .data, .noReply: return true
        case .notSent, .refused: return false
        }
    }

    enum Reply { case data(JSONValue), refused, notSent, noReply }

    /// The reply's data (`.null` when it has none), Wave's refusal, or why there is no answer.
    private func call(_ command: String, _ data: JSONValue, route: String? = nil) -> Reply {
        nextId += 1
        let id = "yaak-\(nextId)"
        var msg: [String: JSONValue] = ["command": .string(command), "reqid": .string(id), "data": data,
                                        "timeout": .number((max(0.001, deadline.timeIntervalSinceNow) * 1000).rounded(.up))]
        if let route { msg["route"] = .string(route) }
        guard var line = try? JSONEncoder().encode(JSONValue.object(msg)) else { return .notSent }
        line.append(0x0A)
        guard UnixSocket.writeAll(fd, line, deadline: deadline) else { return .notSent }
        while let raw = readLine() {
            guard let reply = JSONValue.parse(raw), reply["resid"]?.string == id else { continue }
            if let err = reply["error"]?.string, !err.isEmpty { return .refused }
            return .data(reply["data"] ?? .null)
        }
        return .noReply
    }

    private func readLine() -> Data? {
        var buf = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            if let i = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: i)
                buffer.removeSubrange(...i)
                return line
            }
            let left = deadline.timeIntervalSinceNow
            guard left > 0, buffer.count < 4 << 20 else { return nil }
            UnixSocket.setTimeout(fd, max(left, 0.001), SO_RCVTIMEO)
            let n = read(fd, &buf, buf.count)
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { return nil }
            buffer.append(contentsOf: buf[0..<n])
        }
    }

    /// The token's claims, unverified (Wave checks the signature).
    static func claims(_ jwt: String) -> JSONValue? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        return Data(base64Encoded: b64).flatMap(JSONValue.parse)
    }
}
