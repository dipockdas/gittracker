import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum StoreError: Error, CustomStringConvertible {
    case open(String)
    case exec(String)
    case prepare(String)

    var description: String {
        switch self {
        case .open(let m): return "open failed: \(m)"
        case .exec(let m): return "exec failed: \(m)"
        case .prepare(let m): return "prepare failed: \(m)"
        }
    }
}

final class RunStore {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "gittracker.receiver.store")

    init(path: String) throws {
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &pointer, flags, nil) == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(pointer)
            throw StoreError.open(message)
        }
        handle = pointer
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("PRAGMA busy_timeout=5000;")
        try migrate()
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    private var errorMessage: String {
        guard let handle else { return "no handle" }
        return String(cString: sqlite3_errmsg(handle))
    }

    private func exec(_ sql: String) throws {
        guard let handle else { throw StoreError.exec("no handle") }
        var errorPointer: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(errorPointer)
            throw StoreError.exec(message)
        }
    }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS runs (
            repo TEXT NOT NULL,
            run_id INTEGER NOT NULL,
            workflow_id INTEGER,
            name TEXT,
            head_branch TEXT,
            head_sha TEXT,
            status TEXT,
            conclusion TEXT,
            event TEXT,
            run_number INTEGER,
            html_url TEXT,
            created_at TEXT,
            updated_at TEXT,
            last_action TEXT,
            received_at TEXT NOT NULL,
            PRIMARY KEY (repo, run_id)
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_runs_repo_created ON runs(repo, created_at DESC);")
        try exec("""
        CREATE TABLE IF NOT EXISTS deliveries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            delivery_id TEXT,
            event TEXT,
            action TEXT,
            repo TEXT,
            run_id INTEGER,
            outcome TEXT NOT NULL,
            detail TEXT,
            received_at TEXT NOT NULL
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_deliveries_received ON deliveries(received_at DESC);")
    }

    func recordDelivery(
        deliveryID: String?,
        event: String?,
        action: String?,
        repo: String?,
        runID: Int64?,
        outcome: String,
        detail: String?
    ) {
        queue.sync {
            let sql = """
            INSERT INTO deliveries (delivery_id, event, action, repo, run_id, outcome, detail, received_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            guard let handle else { return }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            Self.bindText(deliveryID, at: 1, in: statement)
            Self.bindText(event, at: 2, in: statement)
            Self.bindText(action, at: 3, in: statement)
            Self.bindText(repo, at: 4, in: statement)
            if let runID {
                sqlite3_bind_int64(statement, 5, runID)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            Self.bindText(outcome, at: 6, in: statement)
            Self.bindText(detail, at: 7, in: statement)
            Self.bindText(ReceiverConfig.isoNow, at: 8, in: statement)
            _ = sqlite3_step(statement)
        }
    }

    func upsertRun(repo: String, run: WebhookEnvelope.WorkflowRunPayload, action: String?) {
        queue.sync {
            let sql = """
            INSERT INTO runs (
                repo, run_id, workflow_id, name, head_branch, head_sha, status, conclusion,
                event, run_number, html_url, created_at, updated_at, last_action, received_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(repo, run_id) DO UPDATE SET
                status = excluded.status,
                conclusion = excluded.conclusion,
                updated_at = excluded.updated_at,
                last_action = excluded.last_action,
                received_at = excluded.received_at;
            """
            guard let handle else { return }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }

            Self.bindText(repo, at: 1, in: statement)
            sqlite3_bind_int64(statement, 2, run.id)
            Self.bindOptionalInt(run.workflowId, at: 3, in: statement)
            Self.bindText(run.name, at: 4, in: statement)
            Self.bindText(run.headBranch, at: 5, in: statement)
            Self.bindText(run.headSha, at: 6, in: statement)
            Self.bindText(run.status, at: 7, in: statement)
            Self.bindText(run.conclusion, at: 8, in: statement)
            Self.bindText(run.event, at: 9, in: statement)
            Self.bindOptionalInt(run.runNumber.map(Int64.init), at: 10, in: statement)
            Self.bindText(run.htmlUrl, at: 11, in: statement)
            Self.bindText(run.createdAt, at: 12, in: statement)
            Self.bindText(run.updatedAt, at: 13, in: statement)
            Self.bindText(action, at: 14, in: statement)
            Self.bindText(ReceiverConfig.isoNow, at: 15, in: statement)
            _ = sqlite3_step(statement)
        }
    }

    func activeRepoCount() -> Int {
        queue.sync {
            guard let handle else { return 0 }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT COUNT(DISTINCT repo) FROM runs;", -1, &statement, nil) == SQLITE_OK else {
                return 0
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    func runCount() -> Int {
        queue.sync {
            guard let handle else { return 0 }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM runs;", -1, &statement, nil) == SQLITE_OK else {
                return 0
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private static func bindText(_ value: String?, at index: Int32, in statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private static func bindOptionalInt(_ value: Int64?, at index: Int32, in statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}
