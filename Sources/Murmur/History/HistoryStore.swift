import Foundation
import OSLog
import SQLite3

/// SQLite-backed transcript history. Schema deliberately matches the
/// Python prototype (`transcripts` table with `id, ts, text, model,
/// duration_s, pasted, error`) so a migration path remains open.
///
/// Why not SwiftData? The SwiftData macro plugin ships only with full
/// Xcode, not with Command Line Tools — and this project builds via SPM
/// + Command Line Tools. SQLite3 is stdlib on macOS, zero-dependency,
/// and entirely sufficient for a single-writer append-only log.
@MainActor
final class HistoryStore {
    static let defaultStoreURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appending(path: "Murmur", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "history.sqlite3")
    }()

    /// Sentinel used by in-memory tests via `HistoryStore.inMemory()`.
    static let inMemoryPath = ":memory:"

    enum HistoryError: Error, CustomStringConvertible {
        case open(String)
        case prepare(String)
        case step(String)

        var description: String {
            switch self {
            case .open(let m):    return "HistoryStore.open: \(m)"
            case .prepare(let m): return "HistoryStore.prepare: \(m)"
            case .step(let m):    return "HistoryStore.step: \(m)"
            }
        }
    }

    private let log = Logger(subsystem: "com.local.murmur", category: "history")
    private var db: OpaquePointer?
    private let path: String

    convenience init() throws {
        try self.init(path: Self.defaultStoreURL.path)
    }

    /// File path, or `":memory:"` for tests.
    init(path: String) throws {
        self.path = path
        var handle: OpaquePointer?
        let status = sqlite3_open(path, &handle)
        guard status == SQLITE_OK, let h = handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "code \(status)"
            sqlite3_close(handle)
            throw HistoryError.open(msg)
        }
        self.db = h
        try createSchema()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    /// Convenience for tests.
    static func inMemory() throws -> HistoryStore {
        try HistoryStore(path: inMemoryPath)
    }

    // MARK: - Schema

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS transcripts (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            ts         REAL NOT NULL,
            text       TEXT NOT NULL,
            model      TEXT NOT NULL,
            duration_s REAL,
            pasted     INTEGER NOT NULL DEFAULT 0,
            error      TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_transcripts_ts ON transcripts(ts DESC);
        """
        var errmsg: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &errmsg)
        if status != SQLITE_OK {
            let msg = errmsg.map { String(cString: $0) } ?? "code \(status)"
            sqlite3_free(errmsg)
            throw HistoryError.step(msg)
        }
    }

    // MARK: - Mutations

    @discardableResult
    func append(
        text: String,
        model: String,
        durationS: Double? = nil,
        error: String? = nil,
        timestamp: Date = .now
    ) -> Int64 {
        let sql = """
        INSERT INTO transcripts (ts, text, model, duration_s, pasted, error)
        VALUES (?, ?, ?, ?, 0, ?)
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("prepare append")
            return -1
        }
        sqlite3_bind_double(stmt, 1, timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, model, -1, SQLITE_TRANSIENT)
        if let d = durationS { sqlite3_bind_double(stmt, 4, d) } else { sqlite3_bind_null(stmt, 4) }
        if let e = error { sqlite3_bind_text(stmt, 5, e, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 5) }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            logError("step append")
            return -1
        }
        return sqlite3_last_insert_rowid(db)
    }

    func markPasted(_ id: Int64) {
        let sql = "UPDATE transcripts SET pasted = 1 WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("prepare markPasted"); return
        }
        sqlite3_bind_int64(stmt, 1, id)
        if sqlite3_step(stmt) != SQLITE_DONE { logError("step markPasted") }
    }

    // MARK: - Queries

    func recent(limit: Int) -> [Transcript] {
        let sql = """
        SELECT id, ts, text, model, duration_s, pasted, error
        FROM transcripts
        ORDER BY ts DESC, id DESC
        LIMIT ?
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("prepare recent"); return []
        }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var rows: [Transcript] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(readRow(stmt!))
        }
        return rows
    }

    func count() -> Int {
        let sql = "SELECT COUNT(*) FROM transcripts"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Per-model rollup used by the Settings → Usage tab.
    /// Only counts rows where the upload succeeded (`error IS NULL` and
    /// `duration_s IS NOT NULL`) — failed uploads don't incur API spend.
    /// Note: this is bounded by `historyRetentionDays` — rows older than
    /// the retention window have already been pruned and won't show up.
    struct UsageRow: Equatable {
        let model: String
        let count: Int
        let totalSeconds: Double
    }

    /// OpenAI's published per-minute pricing (USD, 2026-04). Unknown
    /// models return 0 so the UI just renders "$0.0000".
    static func pricePerMinute(model: String) -> Double {
        switch model {
        case "whisper-1":              return 0.006
        case "gpt-4o-transcribe":      return 0.006
        case "gpt-4o-mini-transcribe": return 0.003
        default:                       return 0
        }
    }

    static func estimatedCost(for row: UsageRow) -> Double {
        pricePerMinute(model: row.model) * (row.totalSeconds / 60.0)
    }

    func usageByModel() -> [UsageRow] {
        let sql = """
        SELECT model, COUNT(*), COALESCE(SUM(duration_s), 0)
        FROM transcripts
        WHERE error IS NULL AND duration_s IS NOT NULL
        GROUP BY model
        ORDER BY model
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("prepare usageByModel"); return []
        }
        var rows: [UsageRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(UsageRow(
                model: String(cString: sqlite3_column_text(stmt, 0)),
                count: Int(sqlite3_column_int(stmt, 1)),
                totalSeconds: sqlite3_column_double(stmt, 2)
            ))
        }
        return rows
    }

    /// Delete rows older than `retentionDays`. `retentionDays <= 0` is a
    /// no-op. Returns the number of rows deleted.
    @discardableResult
    func prune(retentionDays: Int) -> Int {
        guard retentionDays > 0 else { return 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now)
            ?? .now
        let sql = "DELETE FROM transcripts WHERE ts < ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("prepare prune"); return 0
        }
        sqlite3_bind_double(stmt, 1, cutoff.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            logError("step prune"); return 0
        }
        return Int(sqlite3_changes(db))
    }

    // MARK: - Helpers

    private func readRow(_ stmt: OpaquePointer) -> Transcript {
        let id = sqlite3_column_int64(stmt, 0)
        let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        let text = String(cString: sqlite3_column_text(stmt, 2))
        let model = String(cString: sqlite3_column_text(stmt, 3))
        let duration: Double? = (sqlite3_column_type(stmt, 4) == SQLITE_NULL)
            ? nil
            : sqlite3_column_double(stmt, 4)
        let pasted = sqlite3_column_int(stmt, 5) != 0
        let error: String? = (sqlite3_column_type(stmt, 6) == SQLITE_NULL)
            ? nil
            : String(cString: sqlite3_column_text(stmt, 6))
        return Transcript(
            id: id, timestamp: ts, text: text, model: model,
            durationS: duration, pasted: pasted, error: error
        )
    }

    private func logError(_ context: String) {
        let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "no db"
        log.error("\(context, privacy: .public): \(msg, privacy: .public)")
    }
}

// SQLITE_TRANSIENT tells SQLite to copy the string — critical for Swift
// strings whose underlying storage may not outlive the prepare/bind.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
