import Foundation

public final class OllamaClient {
    public static let shared = OllamaClient()
    private let baseURL = URL(string: "http://127.0.0.1:11434")!
    
    private init() {}

    public func refineTranscript(_ rawText: String, completion: @escaping (String) -> Void) {
        var trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion("")
            return
        }

        let config = ConfigManager.shared.config

        // 1. Expand custom tags if spoken
        for (tagKey, tagReplacement) in config.tags {
            trimmed = trimmed.replacingOccurrences(of: tagKey, with: tagReplacement)
            let spokenTag = "colon " + tagKey.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            trimmed = trimmed.replacingOccurrences(of: spokenTag, with: tagReplacement, options: .caseInsensitive)
        }

        // 2. Build personalized context
        var personalContext = ""

        if !config.personal_dictionary.isEmpty {
            personalContext += "\nPersonal Dictionary (prioritize these exact spellings):\n"
            personalContext += config.personal_dictionary.joined(separator: ", ") + "\n"
        }

        let styleSamples = CorrectionStore.shared.loadPersonalStyleSamples()
        if !styleSamples.isEmpty {
            personalContext += "\nUser's Personal Messaging Style Samples:\n"
            personalContext += styleSamples + "\n"
        }

        let recentCorrections = CorrectionStore.shared.getRecentCorrections(limit: 3)
        if !recentCorrections.isEmpty {
            personalContext += "\nLearned Corrections from Past Dictations:\n"
            for c in recentCorrections {
                personalContext += "- Spoken: \"\(c.originalText)\" -> Preferred: \"\(c.correctedText)\"\n"
            }
        }

        if !config.style_instructions.isEmpty {
            personalContext += "\nTone Instruction: \(config.style_instructions)\n"
        }

        let systemPrompt = """
You are an automated voice dictation text cleanup engine, NOT an AI conversational assistant.
The user speaks to dictate text into their computer.
Your job:
1. Fix grammar, spelling, punctuation, capitalization, and self-corrections.
2. Remove filler words (um, uh, like, you know).
3. Do NOT converse, reply, or answer questions. If the user speaks a question, transcribe the question itself.
4. Output ONLY the cleaned-up transcript. Never output conversational responses, explanations, or quotes.
\(personalContext)
"""

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Clean up this raw transcript:\n<raw_transcript>hey um what time is the meeting tomorrow</raw_transcript>"],
            ["role": "assistant", "content": "What time is the meeting tomorrow?"],
            ["role": "user", "content": "Clean up this raw transcript:\n<raw_transcript>can you help me with this bug</raw_transcript>"],
            ["role": "assistant", "content": "Can you help me with this bug?"],
            ["role": "user", "content": "Clean up this raw transcript:\n<raw_transcript>i want to build one app like whisper flow</raw_transcript>"],
            ["role": "assistant", "content": "I want to build an app like Wispr Flow."],
            ["role": "user", "content": "Clean up this raw transcript:\n<raw_transcript>\(trimmed)</raw_transcript>"]
        ]

        let requestBody: [String: Any] = [
            "model": config.llm_model,
            "messages": messages,
            "stream": false,
            "options": [
                "temperature": 0.0
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion(trimmed)
            return
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 4.0

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let responseText = message["content"] as? String else {
                // Graceful fallback to raw text if Ollama times out
                DispatchQueue.main.async { completion(trimmed) }
                return
            }

            var clean = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            clean = clean.replacingOccurrences(of: "<raw_transcript>", with: "")
            clean = clean.replacingOccurrences(of: "</raw_transcript>", with: "")
            clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.hasPrefix("\"") && clean.hasSuffix("\"") && clean.count > 1 {
                clean = String(clean.dropFirst().dropLast())
            }

            DispatchQueue.main.async {
                completion(clean.isEmpty ? trimmed : clean)
            }
        }
        task.resume()
    }
}
