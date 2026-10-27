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

public struct VocabularyEntry: Identifiable, Hashable {
    public let id: Int64
    public let triggerPhrase: String
    public let replacement: String
    public let category: String
    public let useCount: Int
    public let createdAt: Date

    public init(id: Int64, triggerPhrase: String, replacement: String, category: String = "general", useCount: Int = 1, createdAt: Date = Date()) {
        self.id = id
        self.triggerPhrase = triggerPhrase
        self.replacement = replacement
        self.category = category
        self.useCount = useCount
        self.createdAt = createdAt
    }
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

        let createVocabularySQL = """
        CREATE TABLE IF NOT EXISTS vocabulary (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trigger_phrase TEXT NOT NULL UNIQUE,
            replacement TEXT NOT NULL,
            category TEXT DEFAULT 'general',
            use_count INTEGER DEFAULT 1,
            created_at REAL NOT NULL
        );
        """

        executeSQL(createHistorySQL)
        executeSQL(createCorrectionsSQL)
        executeSQL(createVocabularySQL)
        seedDefaultVocabularyIfEmpty()
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

    // MARK: - Vocabulary Management

    public func getAllVocabulary() -> [VocabularyEntry] {
        let sql = "SELECT id, trigger_phrase, replacement, category, use_count, created_at FROM vocabulary ORDER BY use_count DESC, id DESC;"
        var stmt: OpaquePointer?
        var entries: [VocabularyEntry] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let trigger = String(cString: sqlite3_column_text(stmt, 1))
                let repl = String(cString: sqlite3_column_text(stmt, 2))
                let cat = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "general"
                let count = Int(sqlite3_column_int(stmt, 4))
                let date = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))

                entries.append(VocabularyEntry(id: id, triggerPhrase: trigger, replacement: repl, category: cat, useCount: count, createdAt: date))
            }
        }
        sqlite3_finalize(stmt)
        return entries
    }

    public func saveVocabulary(triggerPhrase: String, replacement: String, category: String = "general") {
        let sql = """
        INSERT INTO vocabulary (trigger_phrase, replacement, category, use_count, created_at)
        VALUES (?, ?, ?, 1, ?)
        ON CONFLICT(trigger_phrase) DO UPDATE SET replacement=excluded.replacement, category=excluded.category, use_count=use_count+1;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, triggerPhrase.trimmingCharacters(in: .whitespacesAndNewlines), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, replacement.trimmingCharacters(in: .whitespacesAndNewlines), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    public func deleteVocabulary(id: Int64) {
        let sql = "DELETE FROM vocabulary WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    public func seedDefaultVocabularyIfEmpty() {
        let countSQL = "SELECT COUNT(*) FROM vocabulary;"
        var stmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)

        guard count == 0 else { return }

        let defaults: [(String, String, String)] = [
            // Personal & Family
            ("atish maske", "Atish Maske", "person"),
            ("atish", "Atish", "person"),
            ("ruchita maske", "Ruchita Maske", "person"),
            ("ruchita", "Ruchita", "person"),
            ("andrej karpathy", "Andrej Karpathy", "person"),
            ("karpathy", "Karpathy", "person"),
            ("vannevar bush", "Vannevar Bush", "person"),

            // Locations
            ("pune", "Pune", "location"),
            ("kalyani nagar", "Kalyani Nagar", "location"),
            ("dattwadi", "Dattwadi", "location"),
            ("dattawadi", "Dattwadi", "location"),
            ("nagpur", "Nagpur", "location"),
            ("mumbai", "Mumbai", "location"),
            ("anp ultimus", "ANP Ultimus", "property"),
            ("ultimus", "ANP Ultimus", "property"),

            // Companies & Orgs
            ("edcast", "EdCast", "company"),
            ("ed cast", "EdCast", "company"),
            ("cornerstone ondemand", "Cornerstone OnDemand", "company"),
            ("cornerstone", "Cornerstone", "company"),
            ("modulr", "Modulr", "company"),
            ("modulr payments", "Modulr Payments", "company"),
            ("delaplex", "DelaPlex", "company"),
            ("kunal infotech", "Kunal Infotech", "company"),
            ("cgmeetup", "CGMeetUp", "company"),
            ("tcs", "TCS", "company"),
            ("artcraft", "ArtCraft", "company"),

            // AI & Core Tools
            ("llm wiki", "LLM wiki", "tech"),
            ("llm", "LLM", "acronym"),
            ("local flow", "LocalFlow", "tool"),
            ("localflow", "LocalFlow", "tool"),
            ("whisper flow", "Wispr Flow", "tool"),
            ("wispr flow", "Wispr Flow", "tool"),
            ("whisperflow", "Wispr Flow", "tool"),
            ("wisper", "Wispr", "tool"),
            ("whisper", "Whisper", "tech"),
            ("ollama", "Ollama", "tech"),
            ("antigravity", "Antigravity", "tool"),
            ("claude code", "Claude Code", "tool"),
            ("claude", "Claude", "tool"),
            ("remotion", "Remotion", "tool"),
            ("n8n", "n8n", "tool"),
            ("obsidian", "Obsidian", "tool"),
            ("github", "GitHub", "tool"),
            ("warp", "Warp", "tool"),
            ("oh my zsh", "Oh My Zsh", "tool"),
            ("zsh", "Zsh", "tool"),
            ("patrika", "Patrika", "tool"),
            ("notion", "Notion", "tool"),
            ("rea", "REA", "tool"),
            ("reverse engineer anything", "Reverse Engineer Anything", "tool"),
            ("squad review", "squad-review", "tool"),
            ("linkedin style writer", "linkedin-style-writer", "tool"),

            // Architecture & Concepts
            ("model context protocol", "Model Context Protocol", "tech"),
            ("mcp", "MCP", "acronym"),
            ("memex", "Memex", "concept"),
            ("system one", "System One", "concept"),
            ("dgm rule engine", "DGM Rule Engine", "tech"),
            ("dgm", "DGM", "acronym"),
            ("heritage vault", "Heritage Vault", "concept"),
            ("lx microservice", "LX Microservice", "tech"),
            ("lx", "LX", "acronym"),
            ("copydown", "Copydown", "tech"),
            ("platform engineering", "Platform Engineering", "concept"),
            ("feature moat", "Feature Moat", "concept"),
            ("config service", "Config Service", "tech"),
            ("ruby on rails", "Ruby on Rails", "tech"),
            ("rails", "Rails", "tech"),
            ("sidekiq", "Sidekiq", "tech"),
            ("redis", "Redis", "tech"),
            ("jvm", "JVM", "acronym"),
            ("json rpc", "JSON-RPC", "tech"),
            ("jsonrpc", "JSON-RPC", "tech"),
            ("sso", "SSO", "acronym"),
            ("idp", "IdP", "acronym"),
            ("graphql", "GraphQL", "tech"),
            ("kubernetes", "Kubernetes", "tech"),
            ("next js", "Next.js", "tech"),
            ("nextjs", "Next.js", "tech"),

            // Apple & Native macOS
            ("macos", "macOS", "tech"),
            ("ios", "iOS", "tech"),
            ("apple silicon", "Apple Silicon", "tech"),
            ("apple neural engine", "Apple Neural Engine", "tech"),
            ("neural engine", "Neural Engine", "tech"),
            ("ane", "ANE", "acronym"),
            ("av audio engine", "AVAudioEngine", "tech"),
            ("avaudioengine", "AVAudioEngine", "tech"),
            ("cg event tap", "CGEventTap", "tech"),
            ("cgeventtap", "CGEventTap", "tech"),
            ("sf speech recognizer", "SFSpeechRecognizer", "tech"),
            ("sfspeechrecognizer", "SFSpeechRecognizer", "tech"),

            // Indian Finance, Government & Life
            ("upi", "UPI", "acronym"),
            ("aadhaar", "Aadhaar", "name"),
            ("aadhar", "Aadhaar", "name"),
            ("devrel", "DevRel", "tech"),
            ("dev rel", "DevRel", "tech"),
            ("max life", "Max Life", "finance"),
            ("maxlife", "Max Life", "finance"),
            ("tata aig", "Tata AIG", "finance"),
            ("care health", "Care Health", "finance"),
            ("clearyourdoubt", "clearyourdoubt.in", "website"),
            ("hyundai i20", "Hyundai i20", "vehicle"),
            ("i20", "Hyundai i20", "vehicle"),

            // Acoustic Misrecognitions (Speech Fixes)
            ("earliest scale", "earlier skill", "speech_fix"),
            ("earlier scale", "earlier skill", "speech_fix"),
            ("netherland", "LLM wiki", "speech_fix"),
            ("netherlands", "LLM wiki", "speech_fix"),
            ("skill", "skill", "tech"),
            ("skills", "skills", "tech"),
            ("warm bento", "Warm Bento", "design"),
            ("bento", "Bento", "design")
        ]

        for (trigger, repl, cat) in defaults {
            saveVocabulary(triggerPhrase: trigger, replacement: repl, category: cat)
        }
    }

    // MARK: - Extended History Queries

    public func getAllHistory(limit: Int = 100) -> [HistoryEntry] {
        let sql = "SELECT id, raw_transcript, polished_text, app_name, created_at FROM dictation_history ORDER BY id DESC LIMIT ?;"
        var stmt: OpaquePointer?
        var entries: [HistoryEntry] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let raw = String(cString: sqlite3_column_text(stmt, 1))
                let pol = String(cString: sqlite3_column_text(stmt, 2))
                let app = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "Unknown"
                let date = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))

                entries.append(HistoryEntry(id: id, rawTranscript: raw, polishedText: pol, appName: app, timestamp: date))
            }
        }
        sqlite3_finalize(stmt)
        return entries
    }

    public func deleteHistory(id: Int64) {
        let sql = "DELETE FROM dictation_history WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
}
