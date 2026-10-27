import XCTest
import SwiftUI
@testable import LocalFlowCore

final class LocalFlowTests: XCTestCase {

    // MARK: - 1. TextPolisher Tests

    func testFillerWordRemoval() {
        let polisher = TextPolisher.shared
        let raw = "Um, I think uh we should er go ah now."
        let cleaned = polisher.removeFillerWords(raw)
        XCTAssertFalse(cleaned.contains("Um,"))
        XCTAssertFalse(cleaned.contains("uh"))
        XCTAssertFalse(cleaned.contains("er"))
        XCTAssertFalse(cleaned.contains("ah"))
        XCTAssertTrue(cleaned.contains("I think"))
    }

    func testStammerRemoval() {
        let polisher = TextPolisher.shared
        let raw = "I I think the the issue is is resolved."
        let cleaned = polisher.removeFillerWords(raw)
        XCTAssertEqual(cleaned, "I think the issue is resolved.")
    }

    func testClauseAndSentenceDeduplication() {
        let polisher = TextPolisher.shared
        let raw = "Try speaking a sentence. Try speaking a sentence."
        let cleaned = polisher.deduplicateSentences(raw)
        XCTAssertEqual(cleaned, "Try speaking a sentence.")
    }

    func testNumbersAndCurrencies() {
        let polisher = TextPolisher.shared
        let text1 = "The price is 50 dollars."
        XCTAssertEqual(polisher.formatNumbersAndCurrencies(text1), "The price is $50.")

        let text2 = "Budget is 100 rupees and growth is 25 percent."
        XCTAssertEqual(polisher.formatNumbersAndCurrencies(text2), "Budget is ₹100 and growth is 25%.")
    }

    func testFiscalYearFormatting() {
        let polisher = TextPolisher.shared
        let text1 = "Review financial ledger for FY 2627."
        XCTAssertEqual(polisher.formatFiscalYears(text1), "Review financial ledger for FY 26-27.")

        let text2 = "Reports for three year 2627."
        XCTAssertEqual(polisher.formatFiscalYears(text2), "Reports for FY 26-27.")
    }

    func testSpokenPunctuationAndNewlines() {
        let polisher = TextPolisher.shared
        let raw = "Hello world period How are you question mark new line I am fine period"
        let formatted = polisher.formatSpokenPunctuationAndNewlines(raw)
        XCTAssertTrue(formatted.contains("Hello world."))
        XCTAssertTrue(formatted.contains("How are you?"))
        XCTAssertTrue(formatted.contains("\nI am fine."))
    }

    func testStructuredLists() {
        let polisher = TextPolisher.shared
        let raw = "Action items point 1 run build point 2 test app"
        let formatted = polisher.formatStructuredLists(raw)
        XCTAssertTrue(formatted.contains("\n1. run build"))
        XCTAssertTrue(formatted.contains("\n2. test app"))
    }

    func testSelfCorrections() {
        let polisher = TextPolisher.shared
        let raw = "Let's meet on Monday, actually Tuesday at the office."
        let resolved = polisher.resolveSelfCorrections(raw)
        XCTAssertTrue(resolved.contains("Tuesday at the office"))
        XCTAssertFalse(resolved.contains("Monday"))
    }

    func testTagExpansion() {
        let polisher = TextPolisher.shared
        let tags = [":standup": "Today I am focusing on", ":email": "team@example.com"]
        let raw = ":standup completing LocalFlow release. Send to :email."
        let polished = polisher.polish(text: raw, tags: tags)
        XCTAssertTrue(polished.contains("Today I am focusing on completing LocalFlow release."))
        XCTAssertTrue(polished.contains("Send to team@example.com."))
    }

    func testAppAwareStyle() {
        let polisher = TextPolisher.shared
        let raw = "hello world"
        let formal = polisher.applyAppStyle(raw, style: .formal)
        XCTAssertEqual(formal, "Hello world.")

        let casual = polisher.applyAppStyle(raw, style: .casual)
        XCTAssertEqual(casual, "hello world")
    }

    // MARK: - 2. CorrectionStore SQLite Tests

    func testInMemoryDatabaseAndVocabularySeeding() {
        let store = CorrectionStore(inMemory: true)
        let vocab = store.getAllVocabulary()
        XCTAssertGreaterThan(vocab.count, 0, "Default vocabulary should be seeded into database")
        XCTAssertTrue(vocab.contains(where: { $0.triggerPhrase == "local flow" }))
    }

    func testSaveAndSearchVocabulary() {
        let store = CorrectionStore(inMemory: true)
        store.saveVocabulary(triggerPhrase: "swift ui", replacement: "SwiftUI", category: "tech")

        let search = store.searchVocabulary(query: "SwiftUI")
        XCTAssertEqual(search.count, 1)
        XCTAssertEqual(search.first?.replacement, "SwiftUI")

        if let first = search.first {
            store.deleteVocabulary(id: first.id)
            let afterDelete = store.searchVocabulary(query: "SwiftUI")
            XCTAssertEqual(afterDelete.count, 0)
        }
    }

    func testVocabularyExportAndImport() {
        let store = CorrectionStore(inMemory: true)
        store.saveVocabulary(triggerPhrase: "test phrase", replacement: "Test Replacement", category: "testing")

        let json = store.exportVocabularyJSON()
        XCTAssertTrue(json.contains("test phrase"))
        XCTAssertTrue(json.contains("Test Replacement"))

        let csv = store.exportVocabularyCSV()
        XCTAssertTrue(csv.contains("test phrase"))
        XCTAssertTrue(csv.contains("Test Replacement"))

        let store2 = CorrectionStore(inMemory: true)
        let importedCount = (try? store2.importVocabulary(fromJSON: json)) ?? 0
        XCTAssertGreaterThan(importedCount, 0)
        let found = store2.searchVocabulary(query: "Test Replacement")
        XCTAssertEqual(found.count, 1)
    }

    func testHistorySavingAndStats() {
        let store = CorrectionStore(inMemory: true)
        store.saveHistory(rawTranscript: "this is a test transcript", polishedText: "This is a test transcript.", appName: "Terminal")

        let history = store.getAllHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.appName, "Terminal")
        XCTAssertEqual(history.first?.polishedText, "This is a test transcript.")

        let stats = store.getHistoryStats()
        XCTAssertEqual(stats.totalCount, 1)
        XCTAssertEqual(stats.totalWords, 5)

        let search = store.searchHistory(query: "Terminal")
        XCTAssertEqual(search.count, 1)

        let json = store.exportHistoryJSON()
        XCTAssertTrue(json.contains("Terminal"))
        XCTAssertTrue(json.contains("This is a test transcript."))

        let csv = store.exportHistoryCSV()
        XCTAssertTrue(csv.contains("Terminal"))

        store.clearAllHistory()
        XCTAssertEqual(store.getAllHistory().count, 0)
    }

    // MARK: - 3. ConfigManager Tests

    func testDefaultConfig() {
        let config = LocalFlowConfig.default
        XCTAssertEqual(config.llm_model, "qwen2.5-coder:1.5b")
        XCTAssertEqual(config.hotkey_mode, .toggle)
        XCTAssertEqual(config.trigger_key, .control)
        XCTAssertEqual(config.double_tap_threshold_ms, 400)
        XCTAssertEqual(config.llm_url, "http://127.0.0.1:11434")
        XCTAssertTrue(config.sound_effects)
        XCTAssertTrue(config.haptic_feedback)
    }

    func testConfigBackwardCompatibilityDecoding() throws {
        // Minimal JSON from older versions without new fields
        let oldJson = """
        {
            "llm_model": "llama3.2:1b",
            "headless": true,
            "sound_effects": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(LocalFlowConfig.self, from: oldJson)
        XCTAssertEqual(decoded.llm_model, "llama3.2:1b")
        XCTAssertTrue(decoded.headless)
        XCTAssertFalse(decoded.sound_effects)
        // Check default fallbacks for new fields
        XCTAssertEqual(decoded.hotkey_mode, .toggle)
        XCTAssertEqual(decoded.trigger_key, .control)
        XCTAssertEqual(decoded.llm_url, "http://127.0.0.1:11434")
        XCTAssertTrue(decoded.haptic_feedback)
    }

    func testConfigAppStyleLookup() {
        let config = LocalFlowConfig.default
        XCTAssertEqual(config.styleForApp(bundleId: "com.apple.mail"), .formal)
        XCTAssertEqual(config.styleForApp(bundleId: "com.microsoft.VSCode"), .code)
        XCTAssertEqual(config.styleForApp(bundleId: "com.apple.MobileSMS"), .casual)
        XCTAssertEqual(config.styleForApp(bundleId: "unknown.app"), .standard)
    }

    // MARK: - 4. AudioDeviceManager Tests

    func testAudioDeviceDiscovery() {
        let manager = AudioDeviceManager.shared
        manager.refreshDevices()
        XCTAssertFalse(manager.availableDevices.isEmpty, "Should discover at least one audio input device or fallback")
    }

    func testAudioDeviceIDResolution() {
        // Test system default or nil ID handling
        let nilDev = AudioDeviceManager.audioDeviceID(from: "non_existent_uid_12345")
        XCTAssertNil(nilDev, "Unknown device UID should resolve to nil")
    }

    // MARK: - 5. URL Sanitization Tests

    func testOllamaURLSanitization() {
        let u1 = OllamaClient.sanitizeURL("127.0.0.1:11434")
        XCTAssertEqual(u1.absoluteString, "http://127.0.0.1:11434")

        let u2 = OllamaClient.sanitizeURL("http://localhost:11434///")
        XCTAssertEqual(u2.absoluteString, "http://localhost:11434")

        let u3 = OllamaClient.sanitizeURL("https://custom-ollama.internal:8443")
        XCTAssertEqual(u3.absoluteString, "https://custom-ollama.internal:8443")

        let u4 = OllamaClient.sanitizeURL("")
        XCTAssertEqual(u4.absoluteString, "http://127.0.0.1:11434")
    }

    // MARK: - 6. CSV Parsing with Quoted Commas

    func testCSVLineParsingWithQuotedCommas() {
        let rawLine = "\"hello, world\",\"hi, there\",\"general\",1"
        let fields = CorrectionStore.parseCSVLine(rawLine)
        XCTAssertEqual(fields.count, 4)
        XCTAssertEqual(fields[0], "hello, world")
        XCTAssertEqual(fields[1], "hi, there")
        XCTAssertEqual(fields[2], "general")
        XCTAssertEqual(fields[3], "1")

        let escapedQuoteLine = "\"phrase with \"\"quotes\"\"\",\"replacement\",\"tech\",5"
        let fields2 = CorrectionStore.parseCSVLine(escapedQuoteLine)
        XCTAssertEqual(fields2[0], "phrase with \"quotes\"")
        XCTAssertEqual(fields2[1], "replacement")
    }

    func testImportVocabularyWithQuotedCommas() {
        let store = CorrectionStore(inMemory: true)
        let csv = """
        TriggerPhrase,Replacement,Category,UseCount
        "welcome, user","Welcome User!","greeting",1
        "simple test","Simple Test","tech",2
        """
        let imported = store.importVocabulary(fromCSV: csv)
        XCTAssertEqual(imported, 2)

        let found = store.searchVocabulary(query: "Welcome User!")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.triggerPhrase, "welcome, user")
    }

    // MARK: - 7. TextPolisher Edge Cases

    func testPolisherEdgeCases() {
        let polisher = TextPolisher.shared
        XCTAssertEqual(polisher.polish(text: ""), "")
        XCTAssertEqual(polisher.polish(text: "   \n\t  "), "")

        let alreadyClean = "The pull request has been approved and merged."
        XCTAssertEqual(polisher.polish(text: alreadyClean), alreadyClean)
    }

    func testPermissionsQuery() {
        // Verify hasPermissions evaluates without crashing
        _ = SpeechManager.hasPermissions()
    }

    // MARK: - 8. UI and Settings Tests

    func testSettingsTabsMetadata() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.rawValue.isEmpty)
            XCTAssertFalse(tab.iconName.isEmpty)
            XCTAssertFalse(tab.subtitle.isEmpty)
            // Ensure no em-dash or en-dash in any tab string
            XCTAssertFalse(tab.rawValue.contains("\u{2014}"))
            XCTAssertFalse(tab.rawValue.contains("\u{2013}"))
            XCTAssertFalse(tab.subtitle.contains("\u{2014}"))
            XCTAssertFalse(tab.subtitle.contains("\u{2013}"))
        }
    }

    func testSettingsWindowManagerPresentation() {
        let expectation = self.expectation(description: "Show settings window")
        DispatchQueue.main.async {
            SettingsWindowManager.shared.showSettings()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testConfigToneAndTagsPersistence() {
        var cfg = ConfigManager.shared.config
        let originalPrompt = cfg.style_instructions
        let originalTags = cfg.tags

        cfg.style_instructions = "Custom test style instructions."
        cfg.tags[":testtag"] = "Expansion result"
        ConfigManager.shared.config = cfg
        ConfigManager.shared.save()

        // Reload
        let reloaded = ConfigManager.shared.config
        XCTAssertEqual(reloaded.style_instructions, "Custom test style instructions.")
        XCTAssertEqual(reloaded.tags[":testtag"], "Expansion result")

        // Cleanup
        cfg.style_instructions = originalPrompt
        cfg.tags = originalTags
        ConfigManager.shared.config = cfg
        ConfigManager.shared.save()
    }

    func testOllamaClientFetchModels() {
        let expectation = self.expectation(description: "Fetch installed models")
        OllamaClient.shared.fetchInstalledModels { models in
            // Should return an array without crashing regardless of whether Ollama is online
            XCTAssertNotNil(models)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 4.0)
    }

    func testSettingsWindowManagerReopenLifecycle() {
        let expectation = self.expectation(description: "Window lifecycle reopen")
        DispatchQueue.main.async {
            // First open
            SettingsWindowManager.shared.showSettings()
            // Simulate window close
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: nil)
            // Reopen after close
            SettingsWindowManager.shared.showSettings()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }
}

