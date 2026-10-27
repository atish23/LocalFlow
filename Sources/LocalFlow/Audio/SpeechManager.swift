import Foundation
import Speech
import AVFoundation

public final class SpeechManager: NSObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    public var onPartialTranscript: ((String) -> Void)?
    public var onAudioLevel: ((Float) -> Void)?
    public private(set) var isRecording = false
    
    private var committedText = ""
    private var currentUtteranceText = ""
    private var lastLevelDispatchTime: TimeInterval = 0
    private var lastVoiceDetectedTime: TimeInterval = 0

    public override init() {
        super.init()
        if let recognizer = speechRecognizer {
            recognizer.defaultTaskHint = .dictation
        }
    }

    public static func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                DispatchQueue.main.async {
                    let speechGranted = (authStatus == .authorized)
                    completion(speechGranted && audioGranted)
                }
            }
        }
    }

    public func currentFullTranscript() -> String {
        let committed = committedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = currentUtteranceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if committed.isEmpty { return current }
        if current.isEmpty { return committed }
        if current.lowercased().hasPrefix(committed.lowercased()) {
            return current
        }
        return "\(committed) \(current)"
    }

    private func commitCurrentUtterance() {
        let trimmed = currentUtteranceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if committedText.isEmpty {
            committedText = trimmed
        } else {
            if !committedText.hasSuffix(trimmed) {
                committedText += " " + trimmed
            }
        }
        currentUtteranceText = ""
    }

    public func startRecording(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isRecording else { return }
        
        cleanupRecording()
        committedText = ""
        currentUtteranceText = ""
        lastVoiceDetectedTime = Date().timeIntervalSince1970

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            completion(.failure(NSError(domain: "LocalFlow", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])))
            return
        }

        configureRecognitionRequest(recognitionRequest)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            self.dispatchAudioLevelIfNeeded(from: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            completion(.failure(error))
            return
        }

        setupRecognitionTask()
        completion(.success(()))
    }

    private func setupRecognitionTask() {
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                let now = Date().timeIntervalSince1970

                // Detect if Apple's recognizer reset its formattedString after a silence pause
                // (i.e. New utterance started, text is disjoint from previous utterance)
                let isDisjoint = !self.currentUtteranceText.isEmpty &&
                                 !text.lowercased().hasPrefix(self.currentUtteranceText.lowercased()) &&
                                 !self.currentUtteranceText.lowercased().hasPrefix(text.lowercased())

                // Disjoint text after a pause of silence (>0.5s) or massive length drop means previous sentence completed
                if isDisjoint && (now - self.lastVoiceDetectedTime > 0.5 || text.count < max(1, self.currentUtteranceText.count / 2)) {
                    self.commitCurrentUtterance()
                }

                if result.isFinal {
                    if !text.isEmpty {
                        self.currentUtteranceText = text
                        self.commitCurrentUtterance()
                    }
                } else {
                    self.currentUtteranceText = text
                }

                let full = self.currentFullTranscript()
                DispatchQueue.main.async {
                    self.onPartialTranscript?(full)
                }
            }

            // If the recognition task ended (due to pause isFinal or temporary error)
            // but the user is STILL recording, seamlessly spin up a new task without stopping audio
            if self.isRecording && (result?.isFinal == true || error != nil) {
                if !self.currentUtteranceText.isEmpty {
                    self.commitCurrentUtterance()
                }

                let delay = (error != nil) ? 0.1 : 0.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, self.isRecording else { return }
                    self.restartRecognitionTask()
                }
            }
        }
    }

    private func restartRecognitionTask() {
        guard isRecording else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        configureRecognitionRequest(newRequest)
        self.recognitionRequest = newRequest

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            self.dispatchAudioLevelIfNeeded(from: buffer)
        }

        setupRecognitionTask()
    }

    private func configureRecognitionRequest(_ request: SFSpeechAudioBufferRecognitionRequest) {
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }

        // Bias Apple Neural Engine acoustic decoder with custom vocabulary & domain terms
        let vocab = CorrectionStore.shared.getAllVocabulary()
        var hints = vocab.map { $0.triggerPhrase } + vocab.map { $0.replacement }
        hints.append(contentsOf: [
            "LLM wiki", "LLM", "wiki", "skill", "skills", "Antigravity",
            "Wispr Flow", "LocalFlow", "Ollama", "Whisper", "Remotion", "n8n", "GitHub", "macOS",
            "Majha", "naav", "aahe", "Atish Maske"
        ])
        request.contextualStrings = Array(Set(hints.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }))
    }

    private func dispatchAudioLevelIfNeeded(from buffer: AVAudioPCMBuffer) {
        let level = computeRMSLevel(buffer: buffer)
        let now = Date().timeIntervalSince1970
        if level > 0.08 {
            lastVoiceDetectedTime = now
        }

        guard let onLevel = onAudioLevel else { return }
        // Throttle updates to ~40fps (every 25ms) to prevent UI thread thrashing
        guard now - lastLevelDispatchTime > 0.025 else { return }
        lastLevelDispatchTime = now

        DispatchQueue.main.async {
            onLevel(level)
        }
    }

    private func computeRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }

        var sum: Float = 0.0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // Decibel conversion with normalization: -50 dB to -10 dB -> 0.0 to 1.0
        let db = 20 * log10(max(rms, 0.00001))
        let minDb: Float = -50.0
        let maxDb: Float = -12.0
        let normalized = max(0.0, min(1.0, (db - minDb) / (maxDb - minDb)))
        return normalized
    }

    public func stopRecording(completion: @escaping (String) -> Void) {
        guard isRecording else {
            completion(currentFullTranscript())
            return
        }

        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        // Wait briefly for final recognition results to flush
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else {
                completion("")
                return
            }
            let finalText = self.currentFullTranscript()
            self.cleanupRecording()
            completion(finalText)
        }
    }

    private func cleanupRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }
}
