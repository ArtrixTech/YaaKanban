import Darwin
import Foundation

/// File locations shared by the app and the CLI. `YAAK_HOME` overrides the base for tests.
public struct Paths: Sendable {
    public var base: URL

    public init(environment env: [String: String] = ProcessInfo.processInfo.environment) {
        if let h = env["YAAK_HOME"] {
            base = URL(fileURLWithPath: h)
        } else {
            base = Paths.home(env).appendingPathComponent("Library/Application Support/YaaKanban")
        }
    }

    /// `$HOME`, honoured so tests and `HOME=… yaak` never touch the real home directory.
    public static func home(_ env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory())
    }

    public var socket: URL { base.appendingPathComponent("yaak.sock") }
    public var spool: URL { base.appendingPathComponent("spool") }
    public var database: URL { base.appendingPathComponent("history.sqlite") }
}

/// One line of JSON from the CLI to the app.
public struct WireRequest: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case event, permission }
    public var kind: Kind
    public var envelope: HookEnvelope
    /// For `.permission`: how long the CLI will wait for a reply.
    public var timeout: TimeInterval?

    public init(kind: Kind, envelope: HookEnvelope, timeout: TimeInterval? = nil) {
        self.kind = kind
        self.envelope = envelope
        self.timeout = timeout
    }
}

public enum PermissionDecision: String, Codable, Sendable { case allow, deny }

/// The app's reply to a `.permission` request. A nil decision means "ask in the terminal".
public struct WireReply: Codable, Sendable {
    public var decision: PermissionDecision?
    public init(decision: PermissionDecision?) { self.decision = decision }
}

public enum Wire {
    /// Per-string cap applied to hook payloads before sending. Deterministic, so pre/post hooks still
    /// derive the same synthetic tool id from the trimmed input.
    public static let stringLimit = 8192

    public static func trim(_ v: JSONValue, limit: Int = stringLimit) -> JSONValue {
        switch v {
        case .string(let s) where s.count > limit: return .string(String(s.prefix(limit)) + "…")
        case .array(let a): return .array(a.map { trim($0, limit: limit) })
        case .object(let o): return .object(o.mapValues { trim($0, limit: limit) })
        default: return v
        }
    }

    public static func encode<T: Encodable>(_ v: T) -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .millisecondsSince1970
        var d = (try? enc.encode(v)) ?? Data()
        d.append(0x0A)
        return d
    }

    public static func decode<T: Decodable>(_ t: T.Type, _ d: Data) -> T? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .millisecondsSince1970
        return try? dec.decode(t, from: d)
    }

    /// Writes a request into the spool directory for replay when the app starts.
    public static func spool(_ req: WireRequest, paths: Paths) throws {
        try FileManager.default.createDirectory(at: paths.spool, withIntermediateDirectories: true)
        let name = String(format: "%.0f-%@.json", req.envelope.receivedAt.timeIntervalSince1970 * 1000, UUID().uuidString)
        try encode(req).write(to: paths.spool.appendingPathComponent(name), options: .atomic)
    }

    /// Reads and deletes spooled requests, oldest first.
    public static func drainSpool(paths: Paths) -> [WireRequest] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: paths.spool.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
            let url = paths.spool.appendingPathComponent(name)
            defer { try? fm.removeItem(at: url) }
            return (try? Data(contentsOf: url)).flatMap { decode(WireRequest.self, $0) }
        }
    }
}

// MARK: - Unix domain socket

public enum UnixSocket {
    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
        }
        return addr
    }

    static func setTimeout(_ fd: Int32, _ seconds: TimeInterval, _ opt: Int32) {
        var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, opt, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Connects, sends `data`, and optionally waits for one reply line. Returns nil when the
    /// app is not listening (caller should spool) or no reply arrived in time.
    public static func send(_ data: Data, to path: String, replyTimeout: TimeInterval? = nil) -> (sent: Bool, reply: Data?) {
        guard var addr = address(path) else { return (false, nil) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return (false, nil) }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        setTimeout(fd, 0.2, SO_SNDTIMEO)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard ok, writeAll(fd, data) else { return (false, nil) }
        guard let replyTimeout else { return (true, nil) }
        setTimeout(fd, replyTimeout, SO_RCVTIMEO)
        return (true, readLine(fd))
    }

    public static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }

    /// Reads up to the first newline (or EOF). Caps at 4 MB.
    public static func readLine(_ fd: Int32) -> Data? {
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while out.count < 4 << 20 {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            out.append(contentsOf: buf[0..<n])
            if let i = out.firstIndex(of: 0x0A) { return out.prefix(upTo: i) }
        }
        return out.isEmpty ? nil : out
    }
}

/// Accepts connections on a Unix socket; each connection carries one request line.
public final class SocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (_ line: Data, _ reply: @escaping @Sendable (Data?) -> Void) -> Void

    private let path: String
    private var fd: Int32 = -1
    private let handler: Handler

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        unlink(path)
        guard var addr = UnixSocket.address(path) else { throw POSIXError(.ENAMETOOLONG) }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard bound, listen(fd, 64) == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        chmod(path, 0o600)
        let listenFd = fd
        Thread.detachNewThread { [handler] in
            while true {
                let c = accept(listenFd, nil, nil)
                if c < 0 {
                    switch errno {
                    case EINTR, ECONNABORTED: continue
                    case EMFILE, ENFILE, ENOBUFS, ENOMEM: usleep(100_000); continue
                    default: return // EBADF/EINVAL: stop() closed the socket
                    }
                }
                var one: Int32 = 1
                setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                DispatchQueue.global().async {
                    UnixSocket.setTimeout(c, 2, SO_RCVTIMEO)
                    guard let line = UnixSocket.readLine(c) else { close(c); return }
                    let once = OnceFlag()
                    handler(line) { reply in
                        guard once.claim() else { return }
                        if let reply { _ = UnixSocket.writeAll(c, reply) }
                        close(c)
                    }
                }
            }
        }
    }

    public func stop() {
        if fd >= 0 { close(fd); fd = -1 }
        unlink(path)
    }
}

final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
