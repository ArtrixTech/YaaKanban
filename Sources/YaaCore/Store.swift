import Foundation
import SQLite3

/// SQLite history. Each session is stored as a JSON snapshot keyed by `SessionState.id`.
public final class Store {
    private var db: OpaquePointer?
    /// Full tool input/output is dropped from sessions older than this.
    public static let detailRetention: TimeInterval = 30 * 24 * 3600

    public init(path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(path.path, &db) == SQLITE_OK else { throw StoreError.open }
        try exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS sessions (
              id TEXT PRIMARY KEY,
              agent TEXT NOT NULL,
              status TEXT NOT NULL,
              last_event_at REAL NOT NULL,
              slim INTEGER NOT NULL DEFAULT 0,
              json BLOB NOT NULL
            );
            CREATE INDEX IF NOT EXISTS sessions_last ON sessions(last_event_at);
            """)
    }

    deinit { sqlite3_close(db) }

    public enum StoreError: Error { case open, sql(String) }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            defer { sqlite3_free(err) }
            throw StoreError.sql(err.map { String(cString: $0) } ?? "?")
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public func save(_ s: SessionState) {
        let enc = JSONEncoder()
        guard let data = try? enc.encode(s) else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO sessions (id, agent, status, last_event_at, slim, json) VALUES (?,?,?,?,0,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, s.id, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, s.agent.rawValue, -1, Self.transient)
        sqlite3_bind_text(stmt, 3, s.status.rawValue, -1, Self.transient)
        sqlite3_bind_double(stmt, 4, s.lastEventAt.timeIntervalSince1970)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 5, $0.baseAddress, Int32(data.count), Self.transient) }
        sqlite3_step(stmt)
    }

    public func loadAll() -> [SessionState] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT json FROM sessions ORDER BY last_event_at DESC", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [SessionState] = []
        let dec = JSONDecoder()
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let p = sqlite3_column_blob(stmt, 0) else { continue }
            let data = Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, 0)))
            if let s = try? dec.decode(SessionState.self, from: data) { out.append(s) }
        }
        return out
    }

    public func delete(id: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM sessions WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, Self.transient)
        sqlite3_step(stmt)
    }

    /// Strips tool input/output from sessions idle longer than `detailRetention`; keeps metadata.
    public func purgeDetails(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.detailRetention).timeIntervalSince1970
        for var s in loadAll() where s.lastEventAt.timeIntervalSince1970 < cutoff && s.tools.contains(where: { !$0.input.isEmpty || $0.output != nil }) {
            for i in s.tools.indices { s.tools[i].input = ""; s.tools[i].output = nil }
            save(s)
        }
    }
}
