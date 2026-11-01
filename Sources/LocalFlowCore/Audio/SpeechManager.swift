import Foundation
import Speech
import AVFoundation

public final class SpeechManager: NSObject, SFSpeechRecognizerDelegate {
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var requestLock = os_unfair_lock()

    public var onPartialTranscript: ((String) -> Void)?
    public var onAudioLevel: ((Float) -> Void)?
    public var onError: ((String) -> Void)?
    public private(set) var isRecording = false

    private var committedSegments: [String] = []
    private var currentTaskText: String = ""
    private var currentTaskId: UUID = UUID()
    private var rotationTimer: Timer?
    private var lastLevelDispatchTime: TimeInterval = 0
    private var lastVoiceDetectedTime: TimeInterval = 0
    private var stopCompletion: ((String) -> Void)?
    private var interruptionObserver: NSObjectProtocol?
    private var isCancelling = false
    private var consecutiveErrorCount = 0

    public override init() {
        super.init()
        if let recognizer = speechRecognizer {
            recognizer.defaultTaskHint = .dictation
            recognizer.delegate = self
        }
        setupInterruptionHandling()
    }

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        cleanupRecording()
    }

    private func setupInterruptionHandling() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            print("SpeechManager: Audio engine configuration change detected (device route changed).")
            self.handleAudioInterruption()
        }
    }

    private func handleAudioInterruption() {
        guard isRecording else { return }
        if !currentTaskText.isEmpty {
            commitSegment(currentTaskText)
            currentTaskText = ""
        }
        do {
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            audioEngine.inputNode.removeTap(onBus: 0)

            AudioDeviceManager.configureInputDevice(
                selectedID: ConfigManager.shared.config.selected_audio_device_id,
                for: audioEngine
            )

            restartRecognitionTask()

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                os_unfair_lock_lock(&self.requestLock)
                let req = self.recognitionRequest
                os_unfair_lock_unlock(&self.requestLock)
                req?.append(buffer)
                self.dispatchAudioLevelIfNeeded(from: buffer)
            }
            try audioEngine.start()
        } catch {
            print("SpeechManager: Failed to restart audio engine after route change: \(error.localizedDescription)")
            onError?("Audio input device changed or disconnected.")
            cleanupRecording()
        }
    }

    public static func hasPermissions() -> Bool {
        let micGranted = (AudioDeviceManager.microphonePermissionStatus() == .authorized)
        let speechGranted = (AudioDeviceManager.speechRecognitionPermissionStatus() == .authorized)
        return micGranted && speechGranted
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

    // MARK: - Continuity and Boundary Detection

    /// Determines whether incoming transcript text is an ongoing extension or acoustic refinement of the existing utterance,
    /// or if Apple on-device speech recognition treated a silence pause as an utterance boundary and restarted with new words.
    public func isUtteranceContinuation(existing: String, incoming: String) -> Bool {
        let oldTrim = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrim = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if oldTrim.isEmpty || newTrim.isEmpty { return true }

        // Direct prefix or extension
        if newTrim.hasPrefix(oldTrim) || oldTrim.hasPrefix(newTrim) {
            return true
        }

        let oldWords = oldTrim.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let newWords = newTrim.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var commonPrefixCount = 0
        for (w1, w2) in zip(oldWords, newWords) {
            if w1.lowercased() == w2.lowercased() {
                commonPrefixCount += 1
            } else {
                break
            }
        }

        let minCount = min(oldWords.count, newWords.count)
        if commonPrefixCount >= 3 || (commonPrefixCount >= 2 && minCount <= 4) || Double(commonPrefixCount) >= Double(minCount) * 0.4 {
            return true
        }

        return false
    }

    /// Strips acoustic overlap words between the tail of the previous utterance and the head of the incoming utterance.
    public func stripOverlap(previous: String, next: String) -> String {
        let prevWords = previous.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let nextWords = next.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !prevWords.isEmpty && !nextWords.isEmpty else { return next }

        let maxOverlap = min(prevWords.count, nextWords.count)
        var overlapLength = 0

        for k in stride(from: maxOverlap, through: 1, by: -1) {
            let prevSuffix = prevWords.suffix(k).map { $0.lowercased() }
            let nextPrefix = nextWords.prefix(k).map { $0.lowercased() }
            if Array(prevSuffix) == Array(nextPrefix) {
                overlapLength = k
                break
            }
        }

        if overlapLength > 0 {
            let remaining = nextWords.dropFirst(overlapLength)
            return remaining.joined(separator: " ")
        }
        return next
    }

    public func currentFullTranscript() -> String {
        var segments = committedSegments
        let current = currentTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            if let last = segments.last {
                if current.hasPrefix(last) {
                    segments[segments.count - 1] = current
                } else if last == current || last.hasPrefix(current) {
                    // Already represented in last segment
                } else {
                    let lastWords = last.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    let currentWords = current.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    var commonPrefixCount = 0
                    for (w1, w2) in zip(lastWords, currentWords) {
                        if w1.lowercased() == w2.lowercased() {
                            commonPrefixCount += 1
                        } else {
                            break
                        }
                    }

                    if commonPrefixCount >= 3 && commonPrefixCount >= min(lastWords.count, currentWords.count) / 2 {
                        segments[segments.count - 1] = current
                    } else {
                        let stripped = stripOverlap(previous: last, next: current).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !stripped.isEmpty {
                            segments.append(stripped)
                        }
                    }
                }
            } else {
                segments.append(current)
            }
        }
        return segments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitSegment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let last = committedSegments.last {
            // Case 1: Exact duplicate or direct extension/prefix
            if trimmed.hasPrefix(last) {
                committedSegments[committedSegments.count - 1] = trimmed
                return
            }
            if last == trimmed || last.hasPrefix(trimmed) {
                return
            }

            // Case 2: Near-duplicate acoustic revision (sentences sharing >=50% common prefix words)
            let lastWords = last.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let newWords = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            var commonPrefixCount = 0
            for (w1, w2) in zip(lastWords, newWords) {
                if w1.lowercased() == w2.lowercased() {
                    commonPrefixCount += 1
                } else {
                    break
                }
            }

            if commonPrefixCount >= 3 && commonPrefixCount >= min(lastWords.count, newWords.count) / 2 {
                committedSegments[committedSegments.count - 1] = trimmed
                return
            }

            // Case 3: Suffix-prefix boundary overlap
            let stripped = stripOverlap(previous: last, next: trimmed)
            let cleanStripped = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanStripped.isEmpty {
                return
            }
            committedSegments.append(cleanStripped)
            return
        }

        committedSegments.append(trimmed)
    }

    public func startRecording(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isRecording else { return }

        cleanupRecording()
        committedSegments.removeAll()
        currentTaskText = ""
        stopCompletion = nil
        isCancelling = false
        consecutiveErrorCount = 0
        lastVoiceDetectedTime = Date().timeIntervalSince1970

        // Configure input device from user preference
        AudioDeviceManager.configureInputDevice(
            selectedID: ConfigManager.shared.config.selected_audio_device_id,
            for: audioEngine
        )

        let initialRequest = SFSpeechAudioBufferRecognitionRequest()
        configureRecognitionRequest(initialRequest)

        os_unfair_lock_lock(&requestLock)
        self.recognitionRequest = initialRequest
        os_unfair_lock_unlock(&requestLock)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            os_unfair_lock_lock(&self.requestLock)
            let req = self.recognitionRequest
            os_unfair_lock_unlock(&self.requestLock)
            req?.append(buffer)
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
        startRotationTimer()
        completion(.success(()))
    }

    private func startRotationTimer() {
        rotationTimer?.invalidate()
        // Proactively rotate request before Apple 60s hard ceiling
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 50.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording, !self.isCancelling else { return }
            print("SpeechManager: Proactively rotating recognition task at 50s ceiling.")
            if !self.currentTaskText.isEmpty {
                self.commitSegment(self.currentTaskText)
                self.currentTaskText = ""
            }
            self.restartRecognitionTask()
        }
    }

    private func setupRecognitionTask() {
        os_unfair_lock_lock(&requestLock)
        guard let activeRequest = recognitionRequest else {
            os_unfair_lock_unlock(&requestLock)
            return
        }
        os_unfair_lock_unlock(&requestLock)

        let taskId = UUID()
        self.currentTaskId = taskId

        recognitionTask = speechRecognizer?.recognitionTask(with: activeRequest) { [weak self] result, error in
            guard let self = self else { return }
            // Ignore callbacks from previous tasks that have been rotated or cancelled
            guard self.currentTaskId == taskId else { return }
            guard !self.isCancelling else { return }

            if let result = result {
                self.consecutiveErrorCount = 0
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    if !self.currentTaskText.isEmpty {
                        if self.isUtteranceContinuation(existing: self.currentTaskText, incoming: text) {
                            self.currentTaskText = text
                        } else {
                            // Utterance boundary detected after pause. Commit previous text so it is never dropped.
                            self.commitSegment(self.currentTaskText)
                            self.currentTaskText = text
                        }
                    } else {
                        self.currentTaskText = text
                    }

                    if result.isFinal {
                        self.commitSegment(self.currentTaskText)
                        self.currentTaskText = ""
                    }

                    let full = self.currentFullTranscript()
                    DispatchQueue.main.async {
                        self.onPartialTranscript?(full)
                    }
                }
            }

            // If user requested stop and Apple emitted final result or error, complete cleanly
            if self.stopCompletion != nil && (result?.isFinal == true || error != nil) {
                self.finishStopRecording()
                return
            }

            // If task finalized during recording (silence pause, 60s limit, or minor error), loop smoothly
            if self.isRecording && (result?.isFinal == true || error != nil) {
                if !self.currentTaskText.isEmpty {
                    self.commitSegment(self.currentTaskText)
                    self.currentTaskText = ""
                }

                if let err = error as NSError? {
                    // Check if error is normal silence, timeout, retry, or cancellation
                    if self.isSilenceOrTimeoutError(err) {
                        // User paused or stayed silent to think. Keep recording alive without incrementing error count.
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, self.isRecording, !self.isCancelling else { return }
                            self.restartRecognitionTask()
                        }
                        return
                    }

                    self.consecutiveErrorCount += 1
                    if self.consecutiveErrorCount >= 5 {
                        print("SpeechManager: Too many consecutive hardware/permission errors (\(self.consecutiveErrorCount)), halting: \(err.localizedDescription)")
                        DispatchQueue.main.async {
                            self.onError?("Speech recognition error: \(err.localizedDescription)")
                        }
                        self.cleanupRecording()
                        return
                    }
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.isRecording, !self.isCancelling else { return }
                    self.restartRecognitionTask()
                }
            }
        }
    }

    private func isSilenceOrTimeoutError(_ err: NSError) -> Bool {
        if err.domain == "kAFAssistantErrorDomain" {
            let silenceCodes: Set<Int> = [203, 209, 216, 1101, 1107, 1110]
            if silenceCodes.contains(err.code) {
                return true
            }
        }
        let msg = err.localizedDescription.lowercased()
        if msg.contains("timeout") || msg.contains("no speech") || msg.contains("retry") || msg.contains("cancelled") || msg.contains("interrupted") {
            return true
        }
        return false
    }

    private func restartRecognitionTask() {
        guard isRecording else { return }

        let oldTask = self.recognitionTask
        self.recognitionTask = nil
        oldTask?.cancel()

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        configureRecognitionRequest(newRequest)

        os_unfair_lock_lock(&requestLock)
        let oldRequest = self.recognitionRequest
        self.recognitionRequest = newRequest
        os_unfair_lock_unlock(&requestLock)

        oldRequest?.endAudio()

        setupRecognitionTask()
    }

    private func configureRecognitionRequest(_ request: SFSpeechAudioBufferRecognitionRequest) {
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }

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
        // Throttle updates to ~40fps (every 25ms)
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

        rotationTimer?.invalidate()
        rotationTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        os_unfair_lock_lock(&requestLock)
        let activeRequest = recognitionRequest
        recognitionRequest = nil
        os_unfair_lock_unlock(&requestLock)

        activeRequest?.endAudio()

        // Fallback watchdog: if Apple takes longer than 600ms to emit isFinal, complete cleanly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
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

    public func cleanupRecording() {
        isCancelling = true
        rotationTimer?.invalidate()
        rotationTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()

        os_unfair_lock_lock(&requestLock)
        let req = recognitionRequest
        recognitionRequest = nil
        os_unfair_lock_unlock(&requestLock)

        req?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        consecutiveErrorCount = 0
        isCancelling = false
    }

    // SFSpeechRecognizerDelegate
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            print("SpeechManager: SFSpeechRecognizer is currently unavailable.")
            if isRecording {
                onError?("Speech recognition service temporarily unavailable.")
            }
        }
    }
}
