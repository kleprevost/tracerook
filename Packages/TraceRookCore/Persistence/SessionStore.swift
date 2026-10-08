import CryptoKit
import Darwin
import Foundation
import SQLite3
import TraceRookContracts
import TraceRookPrivacy

public enum StoreError: Error, Sendable { case sqlite(Int32), unavailable, unsafePath, alreadyRunning, migration, corrupt, conflict }

public enum PrivateStateDirectory {
    public static var standard: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TraceRook", isDirectory: true)
    }
    @discardableResult
    public static func prepare(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw StoreError.unsafePath }
        var status = stat()
        if lstat(url.path, &status) == 0 {
            guard status.st_mode & S_IFMT == S_IFDIR, status.st_uid == geteuid() else { throw StoreError.unsafePath }
        } else {
            guard errno == ENOENT else { throw StoreError.unsafePath }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard lstat(url.path, &status) == 0, status.st_mode & S_IFMT == S_IFDIR, status.st_uid == geteuid() else { throw StoreError.unsafePath }
        }
        guard chmod(url.path, 0o700) == 0 else { throw StoreError.unsafePath }
        // Foundation collapses /private/var back to /var on macOS. SQLite's
        // NOFOLLOW rejects that system alias, so use the actual POSIX path.
        guard let resolved = realpath(url.path, nil) else { throw StoreError.unsafePath }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }
    public static func rejectUnsafeFile(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_nlink == 1 else { throw StoreError.unsafePath }
        } else if errno != ENOENT { throw StoreError.unsafePath }
    }
}

/// The connection never escapes SessionStore. SQLite statements are confined to
/// that actor; NOMUTEX is safe because no UI or other actor receives this handle.
private final class SQLiteConnection: @unchecked Sendable {
    var handle: OpaquePointer?
    let lockFD: Int32
    init(directory: URL) throws {
        let directory = try PrivateStateDirectory.prepare(directory)
        let lock = directory.appendingPathComponent("writer.lock")
        try PrivateStateDirectory.rejectUnsafeFile(lock)
        lockFD = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw StoreError.unsafePath }
        guard fchmod(lockFD, 0o600) == 0 else { Darwin.close(lockFD); throw StoreError.unsafePath }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(lockFD); throw StoreError.alreadyRunning }
        let db = directory.appendingPathComponent("history.sqlite3")
        do {
            for name in ["history.sqlite3", "history.sqlite3-wal", "history.sqlite3-shm"] { try PrivateStateDirectory.rejectUnsafeFile(directory.appendingPathComponent(name)) }
            guard sqlite3_open_v2(db.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else { throw StoreError.sqlite(sqlite3_errcode(handle)) }
            guard chmod(db.path, 0o600) == 0 else { throw StoreError.unsafePath }
            sqlite3_busy_timeout(handle, 500)
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA trusted_schema=OFF")
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try migrate()
            // A restarted service has no proof that an original bridge wait lives.
            try execute("UPDATE approvals SET state='aborted', generation=generation+1 WHERE state='pending'")
            for name in ["history.sqlite3-wal", "history.sqlite3-shm"] {
                let url = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { guard chmod(url.path, 0o600) == 0 else { throw StoreError.unsafePath } }
            }
        } catch { sqlite3_close_v2(handle); handle = nil; Darwin.close(lockFD); throw error }
    }
    deinit { sqlite3_close_v2(handle); flock(lockFD, LOCK_UN); Darwin.close(lockFD) }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.sqlite(sqlite3_errcode(handle)) }
    }
    func statement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw StoreError.sqlite(sqlite3_errcode(handle)) }
        return statement
    }
    func migrate() throws {
        let query = try statement("PRAGMA user_version"); defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_ROW else { throw StoreError.migration }
        let version = sqlite3_column_int(query, 0)
        guard version <= 1 else { throw StoreError.migration }
        if version == 1 { return }
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("""
            CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at REAL NOT NULL);
            CREATE TABLE sessions(id TEXT PRIMARY KEY, session_digest TEXT UNIQUE NOT NULL, provider TEXT NOT NULL CHECK(provider IN ('claude_code','codex')),
                origin TEXT NOT NULL CHECK(origin='live'), provenance TEXT NOT NULL CHECK(provenance IN ('host_hook','service_simulation')), last_seen REAL NOT NULL, sanitized_json TEXT NOT NULL);
            CREATE TABLE events(id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                kind TEXT NOT NULL, tool_class TEXT NOT NULL, observed_at REAL NOT NULL, sanitized_json TEXT NOT NULL);
            CREATE TABLE incidents(id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                severity TEXT NOT NULL CHECK(severity IN ('critical','high','medium','low','unknown')), created_at REAL NOT NULL, sanitized_json TEXT NOT NULL);
            CREATE TABLE approvals(id TEXT PRIMARY KEY, incident_id TEXT NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
                request_id TEXT NOT NULL UNIQUE, nonce TEXT NOT NULL, fingerprint TEXT NOT NULL,
                state TEXT NOT NULL CHECK(state IN ('pending','approved_once','denied','expired','aborted')),
                generation INTEGER NOT NULL DEFAULT 1, created_at REAL NOT NULL, expires_at REAL NOT NULL, sanitized_json TEXT NOT NULL);
            CREATE TABLE integration_evidence(id TEXT PRIMARY KEY, provider TEXT NOT NULL, tool_class TEXT NOT NULL, tested_at REAL NOT NULL, sanitized_json TEXT NOT NULL);
            CREATE TABLE provider_calls(request_id TEXT PRIMARY KEY, session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
                model_id TEXT, tokens_in INTEGER, tokens_out INTEGER, elapsed_ms INTEGER, outcome_code TEXT NOT NULL, created_at REAL NOT NULL);
            CREATE TABLE audit_events(id TEXT PRIMARY KEY, code TEXT NOT NULL, occurred_at REAL NOT NULL);
            CREATE INDEX events_time ON events(observed_at); CREATE INDEX incidents_time ON incidents(created_at);
            INSERT INTO schema_migrations VALUES(1, strftime('%s','now')); PRAGMA user_version=1;
            """)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw StoreError.migration }
    }
}

public actor SessionStore {
    private var connection: SQLiteConnection?
    public init(directory: URL) throws { connection = try SQLiteConnection(directory: directory) }
    public func close() { connection = nil }
    private func database() throws -> SQLiteConnection { guard let connection else { throw StoreError.unavailable }; return connection }
    private func bind(_ values: [String], to statement: OpaquePointer) throws {
        for (index, value) in values.enumerated() {
            let result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw StoreError.unavailable }
        }
    }
    private func write(_ sql: String, _ values: [String]) throws {
        let db = try database(), statement = try db.statement(sql); defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.sqlite(sqlite3_errcode(db.handle)) }
    }
    private func rows<T: Decodable>(_ type: T.Type, sql: String, values: [String] = []) throws -> [T] {
        let statement = try database().statement(sql); defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        var records: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return records }
            guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0), sqlite3_column_bytes(statement, 0) <= 65_536 else { throw StoreError.corrupt }
            do { records.append(try JSONDecoder().decode(type, from: Data(String(cString: text).utf8))) }
            catch { throw StoreError.corrupt }
            guard records.count <= 1_000 else { throw StoreError.corrupt }
        }
    }
    private func json<T: Encodable>(_ record: T) throws -> String {
        try PersistedPrivacy.validate(record)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let result = String(data: try encoder.encode(record), encoding: .utf8) else { throw StoreError.corrupt }
        return result
    }
    @discardableResult
    public func record(_ event: AgentEvent, provenance: ActivityProvenance) throws -> SessionRecord {
        try event.validate()
        // Host arguments never reach this API. Keep source identity as a digest.
        let digest = SHA256.hash(data: Data("\(provenance.rawValue):\(event.agent.rawValue):\(event.sourceSessionID):\(event.agentSubID ?? "")".utf8)).map { String(format: "%02x", $0) }.joined()
        let prior = try rows(SessionRecord.self, sql: "SELECT sanitized_json FROM sessions WHERE session_digest=?", values: [digest]).first
        let safeSummary = Redactor().redact(event.argsSummary, limit: 512).text
        let entry = TimelineEntry(id: event.id, at: event.occurredAt, tool: event.actionType.rawValue, summary: safeSummary, severity: .low, execution: .executionUnknown)
        let session = SessionRecord(id: prior?.id ?? UUID(), origin: .live, provider: event.agent, project: "Local project",
            taskAnchor: event.kind == .userPrompt ? safeSummary : prior?.taskAnchor ?? "Task not observed",
            coverage: .notIntegrated, firstSeenAt: prior?.firstSeenAt ?? event.occurredAt, lastSeenAt: event.occurredAt,
            endedAt: event.kind == .sessionEnd ? event.occurredAt : prior?.endedAt, risk: prior?.risk ?? .low,
            events: Array(((prior?.events ?? []) + [entry]).suffix(20)))
        let db = try database(); try db.execute("BEGIN IMMEDIATE")
        do {
            try write("INSERT INTO sessions VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET last_seen=excluded.last_seen,sanitized_json=excluded.sanitized_json", [session.id.uuidString, digest, event.agent.rawValue, "live", provenance.rawValue, String(event.occurredAt.timeIntervalSince1970), try json(session)])
            try write("INSERT INTO events VALUES(?,?,?,?,?,?)", [event.id.uuidString, session.id.uuidString, event.kind.rawValue, event.actionType.rawValue, String(event.occurredAt.timeIntervalSince1970), try json(entry)])
            try db.execute("COMMIT"); return session
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    public func saveIncident(_ incident: IncidentRecord) throws {
        guard incident.origin == .live else { throw TraceRookError.notDemoData }
        try write("INSERT INTO incidents VALUES(?,?,?,?,?)", [incident.id.uuidString, incident.sessionID.uuidString, incident.severity.rawValue, String(incident.createdAt.timeIntervalSince1970), try json(incident)])
    }
    public func saveApproval(_ request: ReviewRequest, record: ApprovalRecord) throws {
        try request.validate()
        guard record.origin == .live, record.state == .pending, record.binding == request.binding,
              record.id == request.approvalID, record.incidentID == request.incidentID else { throw TraceRookError.wrongBinding }
        try write("INSERT INTO approvals(id,incident_id,request_id,nonce,fingerprint,state,created_at,expires_at,sanitized_json) VALUES(?,?,?,?,?,?,?,?,?)",
            [record.id.uuidString, record.incidentID.uuidString, request.requestID.uuidString, request.invocationNonce, record.binding.fingerprint,
             "pending", String(record.requestedAt.timeIntervalSince1970), String(record.expiresAt.timeIntervalSince1970), try json(record)])
    }
    public func resolveApproval(_ request: ReviewRequest, record: ApprovalRecord) throws {
        try request.validate()
        guard record.incidentID == request.incidentID, record.origin == .live, record.state != .pending, record.id == request.approvalID, record.binding == request.binding else { throw TraceRookError.wrongBinding }
        try write("UPDATE approvals SET state=?,generation=generation+1,sanitized_json=? WHERE id=? AND state='pending' AND request_id=? AND nonce=? AND fingerprint=?",
            [record.state.rawValue, try json(record), record.id.uuidString, request.requestID.uuidString, request.invocationNonce, request.binding.fingerprint])
        guard sqlite3_changes(try database().handle) == 1 else { throw StoreError.conflict }
    }
    public func snapshot(mode: ServiceSecurityMode, limit: Int = 25, requests: [ReviewRequest] = []) throws -> ServiceSnapshot {
        guard (1...25).contains(limit) else { throw TraceRookError.malformedInput }
        let sessions = try rows(SessionRecord.self, sql: "SELECT sanitized_json FROM sessions ORDER BY last_seen DESC LIMIT ?", values: [String(limit)])
        let incidents = try rows(IncidentRecord.self, sql: "SELECT sanitized_json FROM incidents ORDER BY created_at DESC LIMIT ?", values: [String(limit)])
        var approvals = try rows(ApprovalRecord.self, sql: "SELECT sanitized_json FROM approvals ORDER BY created_at DESC LIMIT ?", values: [String(limit)])
        // Persisted JSON is never authority for an approval revived after restart.
        for index in approvals.indices {
            let statement = try database().statement("SELECT state FROM approvals WHERE id=?"); defer { sqlite3_finalize(statement) }
            try bind([approvals[index].id.uuidString], to: statement)
            guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0), let state = ApprovalState(rawValue: String(cString: text)) else { throw StoreError.corrupt }
            approvals[index].state = state
        }
        let simulated = try rows(String.self, sql: "SELECT json_quote(id) FROM sessions WHERE provenance='service_simulation' ORDER BY last_seen DESC LIMIT ?", values: [String(limit)]).compactMap(UUID.init(uuidString:))
        let snapshot = ServiceSnapshot(securityMode: mode, sessions: sessions, incidents: incidents, approvals: approvals,
            reviewRequests: Array(requests.prefix(25)), simulatedSessionIDs: simulated, hasMore: try count("sessions") > limit || count("incidents") > limit)
        try snapshot.validate(); return snapshot
    }
    public func abortApproved(_ request: ReviewRequest, record: ApprovalRecord) throws {
        try request.validate()
        guard record.state == .aborted, record.id == request.approvalID, record.binding == request.binding,
              record.incidentID == request.incidentID, record.origin == .live else { throw TraceRookError.wrongBinding }
        try write("UPDATE approvals SET state='aborted',generation=generation+1,sanitized_json=? WHERE id=? AND state='approved_once' AND request_id=? AND nonce=? AND fingerprint=?",
            [try json(record), record.id.uuidString, request.requestID.uuidString, request.invocationNonce, request.binding.fingerprint])
        guard sqlite3_changes(try database().handle) == 1 else { throw StoreError.conflict }
    }
    private func count(_ table: String) throws -> Int {
        guard ["sessions", "incidents", "events", "approvals"].contains(table) else { throw StoreError.corrupt }
        let statement = try database().statement("SELECT count(*) FROM \(table)"); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw StoreError.corrupt }; return Int(sqlite3_column_int(statement, 0))
    }
    public func clearHistory() throws {
        let db = try database(); try db.execute("BEGIN IMMEDIATE")
        do {
            try db.execute("DELETE FROM approvals; DELETE FROM incidents; DELETE FROM events; DELETE FROM sessions; DELETE FROM provider_calls; DELETE FROM audit_events;")
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    public func retain(now: Date = .now, eventDays: Int = 14, incidentDays: Int = 30) throws {
        guard (1...14).contains(eventDays), (1...30).contains(incidentDays) else { throw TraceRookError.malformedInput }
        let db = try database(); try db.execute("BEGIN IMMEDIATE")
        do {
            try write("DELETE FROM events WHERE observed_at < ?", [String(now.addingTimeInterval(-Double(eventDays) * 86_400).timeIntervalSince1970)])
            try write("DELETE FROM incidents WHERE created_at < ? AND id NOT IN (SELECT incident_id FROM approvals WHERE state='pending')", [String(now.addingTimeInterval(-Double(incidentDays) * 86_400).timeIntervalSince1970)])
            var cursor = ""
            while true {
                let sessions = try rows(SessionRecord.self, sql: "SELECT sanitized_json FROM sessions WHERE id>? ORDER BY id LIMIT 100", values: [cursor])
                guard !sessions.isEmpty else { break }
                for session in sessions {
                let recent = session.events.filter { $0.at >= now.addingTimeInterval(-Double(eventDays) * 86_400) }
                let cleaned = SessionRecord(id: session.id, origin: .live, provider: session.provider, project: session.project,
                    taskAnchor: recent.isEmpty ? "Task context expired" : session.taskAnchor, coverage: .notIntegrated,
                    firstSeenAt: session.firstSeenAt, lastSeenAt: session.lastSeenAt, endedAt: session.endedAt, risk: session.risk, events: recent)
                try write("UPDATE sessions SET sanitized_json=? WHERE id=?", [try json(cleaned), session.id.uuidString])
                }
                cursor = sessions.last!.id.uuidString
            }
            try write("DELETE FROM sessions WHERE last_seen < ? AND id NOT IN (SELECT session_id FROM incidents)", [String(now.addingTimeInterval(-Double(incidentDays) * 86_400).timeIntervalSince1970)])
            try write("DELETE FROM provider_calls WHERE created_at < ?", [String(now.addingTimeInterval(-Double(incidentDays) * 86_400).timeIntervalSince1970)])
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
}
