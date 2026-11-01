import Foundation
import CSQLite

/// All access is serialized on the app actor. Intent claims are SQLite transactions.
@MainActor public final class Repository {
    private var db: OpaquePointer?
    public init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw BBError.setup("Could not open local database.") }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("CREATE TABLE IF NOT EXISTS records (kind TEXT NOT NULL, id TEXT NOT NULL, body BLOB NOT NULL, ordinal INTEGER PRIMARY KEY AUTOINCREMENT, UNIQUE(kind,id));")
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw BBError.wire("Local database operation failed.") }
    }
    public func save<T: Encodable>(_ value: T, kind: String, id: String) throws {
        let data = try JSONEncoder().encode(value)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO records(kind,id,body) VALUES(?,?,?) ON CONFLICT(kind,id) DO UPDATE SET body=excluded.body", -1, &stmt, nil) == SQLITE_OK else { throw BBError.wire("Database prepare failed.") }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, kind, -1, transient); sqlite3_bind_text(stmt, 2, id, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw BBError.wire("Database write failed.") }
    }
    public func all<T: Decodable>(_ type: T.Type, kind: String) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT body FROM records WHERE kind=? ORDER BY ordinal", -1, &stmt, nil) == SQLITE_OK else { throw BBError.wire("Database read prepare failed.") }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, kind, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var values: [T] = []; var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            let d = Data(bytes: sqlite3_column_blob(stmt, 0)!, count: Int(sqlite3_column_bytes(stmt, 0)))
            values.append(try JSONDecoder().decode(T.self, from: d)); status = sqlite3_step(stmt)
        }
        guard status == SQLITE_DONE else { throw BBError.wire("Database read failed.") }
        return values
    }
    public func delete(kind: String, id: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM records WHERE kind=? AND id=?", -1, &stmt, nil) == SQLITE_OK else { throw BBError.wire("Database delete prepare failed.") }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, kind, -1, transient); sqlite3_bind_text(stmt, 2, id, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw BBError.wire("Database delete failed.") }
    }
    public func task(_ id: String) throws -> TaskRecord {
        guard let t = try all(TaskRecord.self, kind: "task").first(where: { $0.id == id }) else { throw BBError.invalid("Task no longer exists.") }
        return t
    }
    public func commit(input: String, deviceID: String?) throws -> TaskRecord {
        let t = TaskRecord(id: UUID().uuidString, input: input, state: .queued, detail: "Committed on this phone", date: Date(), deviceID: deviceID,
                           wireHistory: [["role": "user", "parts": [["text": .string(input)]]]])
        let m = ChatMessage(id: UUID().uuidString, taskID: t.id, role: "user", text: input, date: Date())
        try execute("BEGIN IMMEDIATE")
        do { try save(t, kind: "task", id: t.id); try save(m, kind: "message", id: m.id); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
        return t
    }
    public func state(_ id: String, _ state: WorkState, detail: String) throws {
        var t = try task(id); t.state = state; t.detail = detail; try save(t, kind: "task", id: id)
    }
    public func cancel(_ id: String) throws { try state(id, .cancelled, detail: "Cancelled. Completed actions are not undone.") }
    public func claim(_ action: ActionRecord) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            guard try task(action.taskID).state == .running else { throw CancellationError() }
            let existing = try all(ActionRecord.self, kind: "action")
            guard !existing.contains(where: { a in
                a.taskID == action.taskID && (a.functionID == action.functionID || (a.name == action.name && a.arguments == action.arguments && a.deviceID == action.deviceID))
            }) else { throw BBError.invalid("Duplicate action was prevented. Inspect the recorded result.") }
            try save(action, kind: "action", id: action.id); try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func recover() throws {
        let actions = try all(ActionRecord.self, kind: "action")
        for var a in actions where a.state == .running {
            a.state = .unknown; try save(a, kind: "action", id: a.id)
        }
        for var t in try all(TaskRecord.self, kind: "task") where [.queued, .running, .waitingForUser].contains(t.state) {
            t.state = actions.contains(where: { $0.taskID == t.id && [.running, .unknown].contains($0.state) }) ? .unknown : .blocked
            t.detail = "Interrupted. Nothing will be dispatched automatically; inspect activity before a new request."
            try save(t, kind: "task", id: t.id)
        }
    }
}
