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
            CREATE TABLE IF NOT EXISTS activity (
              at REAL NOT NULL,
              session TEXT NOT NULL,
              kind TEXT NOT NULL,
              value REAL NOT NULL DEFAULT 0,
              text TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS activity_at ON activity(at);
            CREATE INDEX IF NOT EXISTS activity_lane ON activity(kind, session, at);
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value REAL NOT NULL);
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

    /// What goes to disk: the Wave JWT is a live credential, so it is dropped once it is no
    /// longer needed to resume the session (see `SessionState.dropsWaveToken`).
    public static func persistable(_ s: SessionState, now: Date = Date()) -> SessionState {
        guard s.terminal?.waveJWT != nil, s.dropsWaveToken(now: now) else { return s }
        var out = s
        out.terminal?.waveJWT = nil
        return out
    }

    public func save(_ s: SessionState) {
        let enc = JSONEncoder()
        guard let data = try? enc.encode(Self.persistable(s)) else { return }
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
        // Its activity stays: past days keep their numbers.
    }

    // MARK: Activity

    /// Efficiency rows are kept this long (two weeks are compared, with room to look back).
    public static let activityRetention: TimeInterval = 90 * 24 * 3600

    private func run(_ sql: String, bind: (OpaquePointer?) -> Void) {
        query(sql, bind: bind) { _ in }
    }

    private func query(_ sql: String, bind: (OpaquePointer?) -> Void, row: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }

    /// Writes `rows`, and the `meta` values with them, in one transaction.
    public func record(_ rows: [ActivityRow], meta: [String: Double] = [:]) {
        guard !rows.isEmpty || !meta.isEmpty else { return }
        try? exec("BEGIN")
        for (k, v) in meta { setMeta(k, v) }
        for r in rows {
            run("INSERT INTO activity (at, session, kind, value, text) VALUES (?,?,?,?,?)") { st in
                sqlite3_bind_double(st, 1, r.at.timeIntervalSince1970)
                sqlite3_bind_text(st, 2, r.session, -1, Self.transient)
                sqlite3_bind_text(st, 3, r.kind.rawValue, -1, Self.transient)
                sqlite3_bind_double(st, 4, r.value)
                sqlite3_bind_text(st, 5, r.text, -1, Self.transient)
            }
        }
        try? exec("COMMIT")
    }

    /// Rows from `start` until `end`, and away rows that began earlier but reach into the range.
    public func activity(from start: Date, to end: Date) -> [ActivityRow] {
        var out: [ActivityRow] = []
        let sql = """
            SELECT at, session, kind, value, text FROM activity
            WHERE at < ?2 AND (at >= ?1 OR (kind = 'away' AND at + value > ?1)) ORDER BY at
            """
        query(sql, bind: { st in
            sqlite3_bind_double(st, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(st, 2, end.timeIntervalSince1970)
        }) { st in
            guard let kind = ActivityRow.Kind(rawValue: String(cString: sqlite3_column_text(st, 2))) else { return }
            out.append(ActivityRow(at: Date(timeIntervalSince1970: sqlite3_column_double(st, 0)),
                                   session: String(cString: sqlite3_column_text(st, 1)), kind: kind,
                                   value: sqlite3_column_double(st, 3), text: String(cString: sqlite3_column_text(st, 4))))
        }
        return out
    }

    /// Each session's last recorded lane before `date` (sessions that had left the lanes omitted).
    public func lanes(before date: Date = .distantFuture) -> [String: Lane] {
        var out: [String: Lane] = [:]
        // Ties on `at` resolve to the later insert.
        let sql = """
            SELECT session, text FROM activity a WHERE kind = 'lane' AND rowid = (
              SELECT rowid FROM activity b WHERE b.kind = 'lane' AND b.session = a.session AND b.at < ?1
              ORDER BY b.at DESC, b.rowid DESC LIMIT 1)
            """
        query(sql, bind: { sqlite3_bind_double($0, 1, min(date.timeIntervalSince1970, 1e12)) }) { st in
            if let lane = Lane(rawValue: String(cString: sqlite3_column_text(st, 1))) {
                out[String(cString: sqlite3_column_text(st, 0))] = lane
            }
        }
        return out
    }

    /// When the oldest recorded row was written.
    public func firstActivity() -> Date? {
        var t: Date?
        query("SELECT min(at) FROM activity", bind: { _ in }) {
            if sqlite3_column_type($0, 0) != SQLITE_NULL { t = Date(timeIntervalSince1970: sqlite3_column_double($0, 0)) }
        }
        return t
    }

    public func purgeActivity(now: Date = Date()) {
        run("DELETE FROM activity WHERE at < ?") {
            sqlite3_bind_double($0, 1, now.addingTimeInterval(-Self.activityRetention).timeIntervalSince1970)
        }
    }

    public func deleteMeta(_ key: String) {
        run("DELETE FROM meta WHERE key = ?") { sqlite3_bind_text($0, 1, key, -1, Self.transient) }
    }

    /// Small named values that outlive a launch (the last heartbeat).
    public func meta(_ key: String) -> Double? {
        var v: Double?
        query("SELECT value FROM meta WHERE key = ?", bind: { sqlite3_bind_text($0, 1, key, -1, Self.transient) }) {
            v = sqlite3_column_double($0, 0)
        }
        return v
    }

    public func setMeta(_ key: String, _ value: Double) {
        run("INSERT OR REPLACE INTO meta (key, value) VALUES (?,?)") { st in
            sqlite3_bind_text(st, 1, key, -1, Self.transient)
            sqlite3_bind_double(st, 2, value)
        }
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
