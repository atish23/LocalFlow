import Foundation
import SQLite3

public struct HistoryEntry {
    public let id: Int64
    public let rawTranscript: String
    public let polishedText: String
    public let appName: String
    public let timestamp: Date
}

public struct CorrectionEntry {
    public let id: Int64
    public let originalText: String
    public let correctedText: String
    public let timestamp: Date
}

public final class CorrectionStore {
    public static let shared = CorrectionStore()
    
    private var db: OpaquePointer?
    private let dbPath: String
    private let styleFilePath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let baseDir = home.appendingPathComponent(".config/localflow")
        dbPath = baseDir.appendingPathComponent("history.db").path
        styleFilePath = baseDir.appendingPathComponent("my_style.txt").path

        openDatabase()
        createTables()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening SQLite database at \(dbPath)")
        }
    }

    private func createTables() {
        let createHistorySQL = """
        CREATE TABLE IF NOT EXISTS dictation_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            raw_transcript TEXT NOT NULL,
            polished_text TEXT NOT NULL,
            app_name TEXT,
            created_at REAL NOT NULL
        );
        """

        let createCorrectionsSQL = """
        CREATE TABLE IF NOT EXISTS corrections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            original_text TEXT NOT NULL,
            corrected_text TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """

        executeSQL(createHistorySQL)
        executeSQL(createCorrectionsSQL)
    }

    private func executeSQL(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let err = errMsg {
                print("SQLite error: \(String(cString: err))")
                sqlite3_free(errMsg)
            }
        }
    }

    public func saveHistory(rawTranscript: String, polishedText: String, appName: String) {
        let sql = "INSERT INTO dictation_history (raw_transcript, polished_text, app_name, created_at) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, rawTranscript, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, polishedText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, appName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("Failed to insert dictation history.")
            }
        }
        sqlite3_finalize(stmt)
    }

    public func saveCorrection(originalText: String, correctedText: String) {
        let sql = "INSERT INTO corrections (original_text, corrected_text, created_at) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, originalText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, correctedText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)

            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    public func getRecentCorrections(limit: Int = 4) -> [CorrectionEntry] {
        let sql = "SELECT id, original_text, corrected_text, created_at FROM corrections ORDER BY created_at DESC LIMIT ?;"
        var stmt: OpaquePointer?
        var entries: [CorrectionEntry] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let orig = String(cString: sqlite3_column_text(stmt, 1))
                let corr = String(cString: sqlite3_column_text(stmt, 2))
                let time = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))

                entries.append(CorrectionEntry(id: id, originalText: orig, correctedText: corr, timestamp: time))
            }
        }
        sqlite3_finalize(stmt)
        return entries
    }

    public func loadPersonalStyleSamples() -> String {
        if let content = try? String(contentsOfFile: styleFilePath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            return lines.joined(separator: "\n")
        }
        return ""
    }
}
