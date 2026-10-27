import Foundation

public enum AppStyle: String {
    case standard
    case casual
    case formal
    case code
}

public final class TextPolisher {
    public static let shared = TextPolisher()

    private init() {}

    public func polish(text: String, style: AppStyle = .standard, tags: [String: String] = [:]) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        // 1. Shorthand and custom tag expansion
        for (tagKey, tagReplacement) in tags {
            result = result.replacingOccurrences(of: tagKey, with: tagReplacement)
            let spokenTag = "colon " + tagKey.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            result = result.replacingOccurrences(of: spokenTag, with: tagReplacement, options: .caseInsensitive)
        }

        // 2. Vocabulary & phonetic jargon replacement from SQLite
        result = applyVocabulary(result)

        // 3. Resolve mid-sentence self-corrections ("actually", "wait no", "I mean")
        result = resolveSelfCorrections(result)

        // 4. Remove conversational filler words and stammers
        result = removeFillerWords(result)

        // 4b. Remove duplicate repeated sentences
        result = deduplicateSentences(result)

        // 5. Format numbers, percentages, and currencies
        result = formatNumbersAndCurrencies(result)

        // 6. Format spoken punctuation and newlines
        result = formatSpokenPunctuationAndNewlines(result)

        // 7. Format structured lists ("point one... point two...")
        result = formatStructuredLists(result)

        // 8. Apply App-Aware style tweaks
        result = applyAppStyle(result, style: style)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 1. Vocabulary Replacement
    private func applyVocabulary(_ text: String) -> String {
        var processed = text
        let vocabList = CorrectionStore.shared.getAllVocabulary()

        for entry in vocabList {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.triggerPhrase))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                processed = regex.stringByReplacingMatches(
                    in: processed,
                    options: [],
                    range: NSRange(location: 0, length: processed.utf16.count),
                    withTemplate: entry.replacement
                )
            }
        }

        // Contextual phonetic substitutions (speech recognizer acoustic confusion)
        let contextualCorrections = [
            ("(?i)\\b(earlier|earliest|my|agent|this|new|old|antigravity)\\s+scale\\b", "$1 skill"),
            ("(?i)\\b(in|at|our|the)\\s+Netherland(s)?\\b", "$1 LLM wiki"),
            ("(?i)\\bNetherland(s)?\\s+(wiki|folder|repo|directory|notes)\\b", "LLM wiki $2")
        ]
        for (pattern, templ) in contextualCorrections {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                processed = regex.stringByReplacingMatches(
                    in: processed,
                    options: [],
                    range: NSRange(location: 0, length: processed.utf16.count),
                    withTemplate: templ
                )
            }
        }

        return processed
    }

    // MARK: - 2. Self-Correction Resolver
    private func resolveSelfCorrections(_ text: String) -> String {
        var processed = text
        // Patterns like: "let's do Monday, actually Tuesday" -> "let's do Tuesday"
        // "at 5 PM, wait no 6 PM" -> "at 6 PM"
        let backtrackPatterns = [
            ",?\\s*\\bwait\\s+no\\b\\s*",
            ",?\\s*\\bactually\\b\\s*",
            ",?\\s*\\bI\\s+mean\\b\\s*",
            ",?\\s*\\bor\\s+rather\\b\\s*"
        ]

        for pattern in backtrackPatterns {
            if let regex = try? NSRegularExpression(pattern: "([^,.!?]+?)" + pattern + "([^,.!?]+)", options: .caseInsensitive) {
                // If the phrase after the backtrack is similar in category/length, replace the first clause
                let matches = regex.matches(in: processed, options: [], range: NSRange(location: 0, length: processed.utf16.count))
                for match in matches.reversed() {
                    if let correctionRange = Range(match.range(at: 2), in: processed) {
                        let correction = String(processed[correctionRange])
                        if let fullRange = Range(match.range, in: processed) {
                            processed.replaceSubrange(fullRange, with: correction)
                        }
                    }
                }
            }
        }
        return processed
    }

    // MARK: - 3. Filler Word & Stammer Removal
    private func removeFillerWords(_ text: String) -> String {
        var processed = text

        // Remove filler words (um, uh, er, ah)
        let fillerPattern = "\\b(?:um|uh|er|ah)\\b,?\\s*"
        if let regex = try? NSRegularExpression(pattern: fillerPattern, options: .caseInsensitive) {
            processed = regex.stringByReplacingMatches(
                in: processed,
                options: [],
                range: NSRange(location: 0, length: processed.utf16.count),
                withTemplate: ""
            )
        }

        // Remove immediate duplicate repeated words (e.g., "I I think" -> "I think", "the the" -> "the")
        let stammerPattern = "\\b([a-zA-Z]+)\\s+\\1\\b"
        if let regex = try? NSRegularExpression(pattern: stammerPattern, options: .caseInsensitive) {
            processed = regex.stringByReplacingMatches(
                in: processed,
                options: [],
                range: NSRange(location: 0, length: processed.utf16.count),
                withTemplate: "$1"
            )
        }

        // Remove repeated phrases (e.g., "Atish Maske Atish Maske" -> "Atish Maske")
        let phrasePattern = "\\b([a-zA-Z]+(?:\\s+[a-zA-Z]+){1,3})\\s+\\1\\b"
        if let regex = try? NSRegularExpression(pattern: phrasePattern, options: .caseInsensitive) {
            processed = regex.stringByReplacingMatches(
                in: processed,
                options: [],
                range: NSRange(location: 0, length: processed.utf16.count),
                withTemplate: "$1"
            )
        }

        return processed
    }

    private func deduplicateSentences(_ text: String) -> String {
        let pattern = "([A-Z0-9][^.!?]*[.!?](?:\\s+[A-Z0-9][^.!?]*[.!?])?)\\s+\\1"
        var processed = text
        if let regex = try? NSRegularExpression(pattern: pattern) {
            processed = regex.stringByReplacingMatches(
                in: processed,
                options: [],
                range: NSRange(location: 0, length: processed.utf16.count),
                withTemplate: "$1"
            )
        }
        return processed
    }

    // MARK: - 4. Numbers & Currency
    private func formatNumbersAndCurrencies(_ text: String) -> String {
        var processed = text

        // Percentages: "25 percent" -> "25%"
        let percentPattern = "(\\d+)\\s+percent\\b"
        if let regex = try? NSRegularExpression(pattern: percentPattern, options: .caseInsensitive) {
            processed = regex.stringByReplacingMatches(
                in: processed,
                options: [],
                range: NSRange(location: 0, length: processed.utf16.count),
                withTemplate: "$1%"
            )
        }

        // Currencies: "50 dollars" -> "$50", "100 rupees" -> "₹100"
        let dollarPattern = "(\\d+)\\s+dollars?\\b"
        if let regex = try? NSRegularExpression(pattern: dollarPattern, options: .caseInsensitive) {
            processed = regex.stringByReplacingMatches(
                in: processed,
                options: [],
                range: NSRange(location: 0, length: processed.utf16.count),
                withTemplate: "\\$$1"
            )
        }

        let rupeePattern = "(\\d+)\\s+rupees?\\b"
        if let regex = try? NSRegularExpression(pattern: rupeePattern, options: .caseInsensitive) {
            processed = regex.stringByReplacingMatches(
                in: processed,
                options: [],
                range: NSRange(location: 0, length: processed.utf16.count),
                withTemplate: "₹$1"
            )
        }

        // Fiscal Years: "FY 2627", "year 2627", "three year 2627" -> "FY 26-27"
        processed = formatFiscalYears(processed)

        return processed
    }

    private func formatFiscalYears(_ text: String) -> String {
        var processed = text
        // Acoustic mishearings
        let acousticFixes = [
            ("(?i)\\bfinancial leader\\b", "financial ledger"),
            ("(?i)\\b(?:for\\s+)?three\\s+year\\s+(\\d{4})\\b", "for FY $1"),
            ("(?i)\\bthree\\s+year\\b", "FY")
        ]
        for (pattern, templ) in acousticFixes {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                processed = regex.stringByReplacingMatches(in: processed, options: [], range: NSRange(location: 0, length: processed.utf16.count), withTemplate: templ)
            }
        }

        // Pattern: "(year|FY|financial year)? 2627" -> "FY 26-27" when year digits are sequential
        let fyPattern = "(?i)\\b(FY\\s*|financial\\s+year\\s*|fiscal\\s+year\\s*|year\\s*)?(\\d{2})(\\d{2})\\b"
        if let regex = try? NSRegularExpression(pattern: fyPattern) {
            let matches = regex.matches(in: processed, options: [], range: NSRange(location: 0, length: processed.utf16.count))
            for match in matches.reversed() {
                guard let r2 = Range(match.range(at: 2), in: processed),
                      let r3 = Range(match.range(at: 3), in: processed),
                      let y1 = Int(processed[r2]),
                      let y2 = Int(processed[r3]) else { continue }

                if y2 == (y1 + 1) % 100 {
                    var prefix = ""
                    if match.range(at: 1).location != NSNotFound, let r1 = Range(match.range(at: 1), in: processed) {
                        prefix = String(processed[r1]).trimmingCharacters(in: .whitespaces)
                    }
                    let cleanPrefix = prefix.isEmpty ? "" : "FY "
                    let replacement = "\(cleanPrefix)\(String(format: "%02d-%02d", y1, y2))".trimmingCharacters(in: .whitespaces)
                    if let fullRange = Range(match.range, in: processed) {
                        processed.replaceSubrange(fullRange, with: replacement)
                    }
                }
            }
        }

        return processed
    }

    // MARK: - 5. Spoken Punctuation & Newlines
    private func formatSpokenPunctuationAndNewlines(_ text: String) -> String {
        var result = text

        // Double newlines
        let paragraphRegexes = ["\\b(?:new|next) paragraph\\b"]
        for pattern in paragraphRegexes {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "\n\n")
            }
        }

        // Single newlines
        let newlineRegexes = ["\\b(?:new|next) line\\b"]
        for pattern in newlineRegexes {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "\n")
            }
        }

        // Spoken punctuation words
        let punctuationMap: [(String, String)] = [
            ("\\s*\\bperiod\\b", "."),
            ("\\s*\\bfull stop\\b", "."),
            ("\\s*\\bcomma\\b", ","),
            ("\\s*\\bquestion mark\\b", "?"),
            ("\\s*\\bexclamation mark\\b", "!"),
            ("\\s*\\bexclamation point\\b", "!")
        ]

        for (pattern, symbol) in punctuationMap {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: symbol)
            }
        }

        // Capitalize character after newline
        let lines = result.components(separatedBy: "\n")
        let formattedLines = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first else { return "" }
            return String(first).uppercased() + String(trimmed.dropFirst())
        }
        return formattedLines.joined(separator: "\n")
    }

    // MARK: - 6. Structured Lists
    private func formatStructuredLists(_ text: String) -> String {
        var processed = text
        // Convert "point 1 do this point 2 do that" or "number 1 ... number 2 ..."
        let listPattern = "(?:^|\\s)(?:point|number)\\s+(\\d+)[.:]?\\s+"
        if let regex = try? NSRegularExpression(pattern: listPattern, options: .caseInsensitive) {
            processed = regex.stringByReplacingMatches(
                in: processed,
                options: [],
                range: NSRange(location: 0, length: processed.utf16.count),
                withTemplate: "\n$1. "
            )
        }
        return processed
    }

    // MARK: - 7. App-Aware Styles
    private func applyAppStyle(_ text: String, style: AppStyle) -> String {
        switch style {
        case .casual:
            // Friendly contractions and clean spacing
            return text
        case .formal:
            // Ensure first letter of sentences is capitalized and clean period at end
            var formal = text
            if let first = formal.first {
                formal = String(first).uppercased() + String(formal.dropFirst())
            }
            if !formal.isEmpty && !formal.hasSuffix(".") && !formal.hasSuffix("?") && !formal.hasSuffix("!") && !formal.contains("\n") {
                formal += "."
            }
            return formal
        case .code:
            return text
        case .standard:
            return text
        }
    }
}
