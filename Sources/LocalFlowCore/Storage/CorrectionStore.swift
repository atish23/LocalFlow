import Foundation
import SQLite3

public struct HistoryEntry: Identifiable, Hashable {
    public let id: Int64
    public let rawTranscript: String
    public let polishedText: String
    public let appName: String
    public let timestamp: Date

    public init(id: Int64, rawTranscript: String, polishedText: String, appName: String, timestamp: Date) {
        self.id = id
        self.rawTranscript = rawTranscript
        self.polishedText = polishedText
        self.appName = appName
        self.timestamp = timestamp
    }
}

public struct CorrectionEntry: Identifiable, Hashable {
    public let id: Int64
    public let originalText: String
    public let correctedText: String
    public let timestamp: Date

    public init(id: Int64, originalText: String, correctedText: String, timestamp: Date) {
        self.id = id
        self.originalText = originalText
        self.correctedText = correctedText
        self.timestamp = timestamp
    }
}

public struct VocabularyEntry: Identifiable, Hashable, Codable {
    public let id: Int64
    public let triggerPhrase: String
    public let replacement: String
    public let category: String
    public let useCount: Int
    public let createdAt: Date

    public init(id: Int64 = 0, triggerPhrase: String, replacement: String, category: String = "general", useCount: Int = 1, createdAt: Date = Date()) {
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

    public init(inMemory: Bool = false) {
        if inMemory {
            self.dbPath = ":memory:"
            self.styleFilePath = ""
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let baseDir = home.appendingPathComponent(".config/localflow")
            if !FileManager.default.fileExists(atPath: baseDir.path) {
                try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            }
            self.dbPath = baseDir.appendingPathComponent("history.db").path
            self.styleFilePath = baseDir.appendingPathComponent("my_style.txt").path
        }

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
        guard !styleFilePath.isEmpty else { return "" }
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

    public func searchVocabulary(query: String) -> [VocabularyEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return getAllVocabulary() }

        let sql = "SELECT id, trigger_phrase, replacement, category, use_count, created_at FROM vocabulary WHERE trigger_phrase LIKE ? OR replacement LIKE ? OR category LIKE ? ORDER BY use_count DESC, id DESC;"
        var stmt: OpaquePointer?
        var entries: [VocabularyEntry] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let wildcard = "%\(q)%"
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, wildcard, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, wildcard, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, wildcard, -1, SQLITE_TRANSIENT)

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

    public func exportVocabularyJSON() -> String {
        let entries = getAllVocabulary()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    public func exportVocabularyCSV() -> String {
        let entries = getAllVocabulary()
        var csv = "TriggerPhrase,Replacement,Category,UseCount\n"
        for entry in entries {
            let trigger = entry.triggerPhrase.replacingOccurrences(of: "\"", with: "\"\"")
            let repl = entry.replacement.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(trigger)\",\"\(repl)\",\"\(entry.category)\",\(entry.useCount)\n"
        }
        return csv
    }

    public func importVocabulary(fromJSON jsonString: String) throws -> Int {
        guard let data = jsonString.data(using: .utf8) else { return 0 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([VocabularyEntry].self, from: data)
        for entry in entries {
            saveVocabulary(triggerPhrase: entry.triggerPhrase, replacement: entry.replacement, category: entry.category)
        }
        return entries.count
    }

    public func importVocabulary(fromCSV csvString: String) -> Int {
        let lines = csvString.components(separatedBy: .newlines)
        var count = 0
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: ",")
            if parts.count >= 2 {
                let trigger = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                let repl = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                let cat = parts.count >= 3 ? parts[2].trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) : "general"
                if !trigger.isEmpty && !repl.isEmpty {
                    saveVocabulary(triggerPhrase: trigger, replacement: repl, category: cat)
                    count += 1
                }
            }
        }
        return count
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
            ("atish maske", "Atish Maske", "person"),
            ("atish", "Atish", "person"),
            ("ruchita maske", "Ruchita Maske", "person"),
            ("ruchita", "Ruchita", "person"),
            ("andrej karpathy", "Andrej Karpathy", "person"),
            ("karpathy", "Karpathy", "person"),
            ("vannevar bush", "Vannevar Bush", "person"),
            ("pune", "Pune", "location"),
            ("kalyani nagar", "Kalyani Nagar", "location"),
            ("dattwadi", "Dattwadi", "location"),
            ("dattawadi", "Dattwadi", "location"),
            ("nagpur", "Nagpur", "location"),
            ("mumbai", "Mumbai", "location"),
            ("anp ultimus", "ANP Ultimus", "property"),
            ("ultimus", "ANP Ultimus", "property"),
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

    public func searchHistory(query: String, limit: Int = 100) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return getAllHistory(limit: limit) }

        let sql = "SELECT id, raw_transcript, polished_text, app_name, created_at FROM dictation_history WHERE polished_text LIKE ? OR raw_transcript LIKE ? OR app_name LIKE ? ORDER BY id DESC LIMIT ?;"
        var stmt: OpaquePointer?
        var entries: [HistoryEntry] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let wildcard = "%\(q)%"
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, wildcard, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, wildcard, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, wildcard, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 4, Int32(limit))

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

    public func getHistoryStats() -> (totalCount: Int, totalWords: Int) {
        let sql = "SELECT raw_transcript, polished_text FROM dictation_history;"
        var stmt: OpaquePointer?
        var count = 0
        var totalWords = 0

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                count += 1
                let text = String(cString: sqlite3_column_text(stmt, 1))
                let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                totalWords += words.count
            }
        }
        sqlite3_finalize(stmt)
        return (count, totalWords)
    }

    public func exportHistoryJSON() -> String {
        let entries = getAllHistory(limit: 1000)
        var array: [[String: Any]] = []
        let formatter = ISO8601DateFormatter()
        for e in entries {
            array.append([
                "id": e.id,
                "raw_transcript": e.rawTranscript,
                "polished_text": e.polishedText,
                "app_name": e.appName,
                "timestamp": formatter.string(from: e.timestamp)
            ])
        }
        if let data = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    public func exportHistoryCSV() -> String {
        let entries = getAllHistory(limit: 1000)
        var csv = "ID,Timestamp,AppName,RawTranscript,PolishedText\n"
        let formatter = ISO8601DateFormatter()
        for e in entries {
            let app = e.appName.replacingOccurrences(of: "\"", with: "\"\"")
            let raw = e.rawTranscript.replacingOccurrences(of: "\"", with: "\"\"")
            let pol = e.polishedText.replacingOccurrences(of: "\"", with: "\"\"")
            let time = formatter.string(from: e.timestamp)
            csv += "\(e.id),\"\(time)\",\"\(app)\",\"\(raw)\",\"\(pol)\"\n"
        }
        return csv
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

    public func clearAllHistory() {
        executeSQL("DELETE FROM dictation_history;")
    }
}
