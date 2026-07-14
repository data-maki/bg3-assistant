import Foundation
import SQLite3

struct AssistantSettings: Codable, Equatable {
    var telemetryEnabled = false
    var visualMemoryEnabled = false
    var mapOverlayCaptureEnabled = false
    var overlayDensity = OverlayDensity.focus.rawValue

    static func migrating(_ defaults: UserDefaults = .standard) -> AssistantSettings {
        AssistantSettings(
            telemetryEnabled: defaults.bool(forKey: "telemetryEnabled"),
            visualMemoryEnabled: defaults.bool(forKey: "BG3VisualMemoryEnabled"),
            mapOverlayCaptureEnabled: defaults.bool(forKey: "BG3MapOverlayCaptureEnabled"),
            overlayDensity: defaults.string(forKey: "BG3OverlayDensity") ?? OverlayDensity.focus.rawValue
        )
    }
}

enum RunStoreError: LocalizedError {
    case sqlite(String)
    case invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .sqlite(let message): "Run database error: \(message)"
        case .invalidSnapshot: "The saved run snapshot could not be decoded."
        }
    }
}

/// One cross-process SQLite authority for the native overlay and localhost map.
/// The full Codable snapshot keeps schema evolution small; revisions prevent a
/// bad write from silently erasing a run. Legacy run.json is migration-only.
struct RunStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let baseDirectory: URL
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(baseDirectory: URL? = nil) {
        let isolatedPath = ProcessInfo.processInfo.environment["BG3_ASSISTANT_STATE_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.baseDirectory = baseDirectory ?? isolatedPath ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "BG3HonorAssistant", directoryHint: .isDirectory)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> HonorRun {
        do {
            if let data = try activeSnapshot(), let run = try? decoder.decode(HonorRun.self, from: data) {
                return run
            }
            for data in try revisionSnapshots() {
                if let run = try? decoder.decode(HonorRun.self, from: data) { return run }
            }
            if let data = try? Data(contentsOf: runURL), let run = try? decoder.decode(HonorRun.self, from: data) {
                try save(run)
                return run
            }
        } catch {
            if let data = try? Data(contentsOf: runURL), let run = try? decoder.decode(HonorRun.self, from: data) {
                return run
            }
        }
        return HonorRun()
    }

    func save(_ run: HonorRun) throws {
        let data = try encoder.encode(run)
        guard let snapshot = String(data: data, encoding: .utf8) else { throw RunStoreError.invalidSnapshot }
        try withDatabase { database in
            try execute("BEGIN IMMEDIATE", in: database)
            do {
                try execute("UPDATE runs SET is_active = 0 WHERE is_active = 1", in: database)
                let timestamp = Date().timeIntervalSince1970
                try bindAndRun(
                    """
                    INSERT INTO runs(run_id, snapshot_json, updated_at, is_active)
                    VALUES(?, ?, ?, 1)
                    ON CONFLICT(run_id) DO UPDATE SET
                        snapshot_json = excluded.snapshot_json,
                        updated_at = excluded.updated_at,
                        is_active = 1
                    """,
                    text: [run.id, snapshot], doubles: [timestamp], in: database
                )
                try bindAndRun(
                    "INSERT INTO run_revisions(run_id, snapshot_json, created_at) VALUES(?, ?, ?)",
                    text: [run.id, snapshot], doubles: [timestamp], in: database
                )
                try bindAndRun(
                    """
                    DELETE FROM run_revisions
                    WHERE run_id = ? AND id NOT IN (
                        SELECT id FROM run_revisions WHERE run_id = ? ORDER BY id DESC LIMIT 20
                    )
                    """,
                    text: [run.id, run.id], doubles: [], in: database
                )
                try execute("COMMIT", in: database)
            } catch {
                try? execute("ROLLBACK", in: database)
                throw error
            }
        }
    }

    func loadSettings() -> AssistantSettings {
        do {
            if let data = try settingData(for: "assistant"),
               let settings = try? decoder.decode(AssistantSettings.self, from: data) {
                return settings
            }
            let settings = AssistantSettings.migrating()
            try saveSettings(settings)
            return settings
        } catch {
            return AssistantSettings.migrating()
        }
    }

    func saveSettings(_ settings: AssistantSettings) throws {
        let data = try encoder.encode(settings)
        guard let value = String(data: data, encoding: .utf8) else { throw RunStoreError.invalidSnapshot }
        try withDatabase { database in
            try bindAndRun(
                """
                INSERT INTO settings(key, value, updated_at) VALUES('assistant', ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                """,
                text: [value], doubles: [Date().timeIntervalSince1970], in: database
            )
        }
    }

    var databaseURL: URL { baseDirectory.appending(path: "state.sqlite3") }
    var runURL: URL { baseDirectory.appending(path: "run.json") }

    private func activeSnapshot() throws -> Data? {
        try withDatabase { database in
            try queryText(
                "SELECT snapshot_json FROM runs WHERE is_active = 1 ORDER BY updated_at DESC LIMIT 1",
                in: database
            ).first.map { Data($0.utf8) }
        }
    }

    private func revisionSnapshots() throws -> [Data] {
        try withDatabase { database in
            try queryText(
                "SELECT snapshot_json FROM run_revisions ORDER BY id DESC LIMIT 20",
                in: database
            ).map { Data($0.utf8) }
        }
    }

    private func settingData(for key: String) throws -> Data? {
        try withDatabase { database in
            try queryText("SELECT value FROM settings WHERE key = ? LIMIT 1", bind: [key], in: database)
                .first.map { Data($0.utf8) }
        }
    }

    private func withDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let database = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open \(databaseURL.path)"
            if let handle { sqlite3_close(handle) }
            throw RunStoreError.sqlite(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)
        try execute("PRAGMA journal_mode = WAL", in: database)
        try execute("PRAGMA foreign_keys = ON", in: database)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS runs(
                run_id TEXT PRIMARY KEY,
                snapshot_json TEXT NOT NULL,
                updated_at REAL NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 0
            )
            """,
            in: database
        )
        try execute("CREATE UNIQUE INDEX IF NOT EXISTS one_active_run ON runs(is_active) WHERE is_active = 1", in: database)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS run_revisions(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                run_id TEXT NOT NULL,
                snapshot_json TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """,
            in: database
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS settings(
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """,
            in: database
        )
        return try operation(database)
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorPointer)
            throw RunStoreError.sqlite(message)
        }
    }

    private func bindAndRun(_ sql: String, text values: [String], doubles: [Double], in database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RunStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        var index: Int32 = 1
        for value in values {
            guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
                throw RunStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
            index += 1
        }
        for value in doubles {
            guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
                throw RunStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
            index += 1
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw RunStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func queryText(_ sql: String, bind values: [String] = [], in database: OpaquePointer) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RunStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            guard sqlite3_bind_text(statement, Int32(offset + 1), value, -1, transient) == SQLITE_OK else {
                throw RunStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
        }
        var output: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw RunStoreError.sqlite(String(cString: sqlite3_errmsg(database))) }
            if let value = sqlite3_column_text(statement, 0) { output.append(String(cString: value)) }
        }
    }
}
