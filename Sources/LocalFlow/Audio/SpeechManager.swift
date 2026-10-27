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
    
    private var committedSegments: [String] = []
    private var currentTaskText: String = ""
    private var lastLevelDispatchTime: TimeInterval = 0
    private var lastVoiceDetectedTime: TimeInterval = 0
    private var stopCompletion: ((String) -> Void)?

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
        var segments = committedSegments
        let current = currentTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            if let last = segments.last, current.hasPrefix(last) {
                segments[segments.count - 1] = current
            } else if segments.last != current {
                segments.append(current)
            }
        }
        return segments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitSegment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let last = committedSegments.last, trimmed.hasPrefix(last) {
            committedSegments[committedSegments.count - 1] = trimmed
        } else if committedSegments.last != trimmed {
            committedSegments.append(trimmed)
        }
    }

    public func startRecording(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isRecording else { return }
        
        cleanupRecording()
        committedSegments.removeAll()
        currentTaskText = ""
        stopCompletion = nil
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

                // Check if Apple's recognizer reset its formattedString after a silence pause
                let isDisjoint = !self.currentTaskText.isEmpty &&
                                 !text.lowercased().hasPrefix(self.currentTaskText.lowercased()) &&
                                 !self.currentTaskText.lowercased().hasPrefix(text.lowercased())

                // Disjoint text after silence (>=0.5s) means previous sentence finished
                if isDisjoint && (now - self.lastVoiceDetectedTime > 0.5 || text.count < max(1, self.currentTaskText.count / 2)) {
                    self.commitSegment(self.currentTaskText)
                }

                self.currentTaskText = text

                if result.isFinal {
                    self.commitSegment(text)
                    self.currentTaskText = ""
                }

                let full = self.currentFullTranscript()
                DispatchQueue.main.async {
                    self.onPartialTranscript?(full)
                }
            }

            // If user stopped recording and Apple emitted the final transcription, complete cleanly
            if self.stopCompletion != nil && (result?.isFinal == true || error != nil) {
                self.finishStopRecording()
                return
            }

            // If task finalized during recording (e.g. Pause timeout), restart seamlessly
            if self.isRecording && (result?.isFinal == true || error != nil) {
                if !self.currentTaskText.isEmpty {
                    self.commitSegment(self.currentTaskText)
                    self.currentTaskText = ""
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
        stopCompletion = completion

        // Stop microphone input so no more audio is added
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Tell recognizer that audio input ended so it can process final audio frames
        recognitionRequest?.endAudio()

        // Watchdog fallback: if Apple takes longer than 750ms to emit isFinal, complete cleanly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self = self, self.stopCompletion != nil else { return }
            self.finishStopRecording()
        }
    }

    private func finishStopRecording() {
        guard let completion = stopCompletion else { return }
        stopCompletion = nil

        if !currentTaskText.isEmpty {
            commitSegment(currentTaskText)
            currentTaskText = ""
        }

        let finalText = currentFullTranscript()
        cleanupRecording()
        DispatchQueue.main.async {
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
