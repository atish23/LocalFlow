import Foundation
import Speech
import AVFoundation

public final class SpeechManager: NSObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    public var onPartialTranscript: ((String) -> Void)?
    public private(set) var isRecording = false
    private var lastRecordedText = ""

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

    public func startRecording(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isRecording else { return }
        
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        lastRecordedText = ""

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            completion(.failure(NSError(domain: "LocalFlow", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])))
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        // Enforce 100% on-device speech recognition
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            completion(.failure(error))
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.lastRecordedText = text
                DispatchQueue.main.async {
                    self.onPartialTranscript?(text)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self.cleanupRecording()
            }
        }

        completion(.success(()))
    }

    public func stopRecording(completion: @escaping (String) -> Void) {
        guard isRecording else {
            completion(lastRecordedText)
            return
        }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isRecording = false
        
        // Wait briefly for final recognition results to flush
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            let finalText = self?.lastRecordedText ?? ""
            self?.cleanupRecording()
            completion(finalText)
        }
    }

    private func cleanupRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }
}
