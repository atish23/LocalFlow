import Foundation
import AVFoundation
import Speech
import AppKit
import CoreAudio
import AudioToolbox

public struct AudioInputDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public final class AudioDeviceManager: ObservableObject {
    public static let shared = AudioDeviceManager()

    @Published public private(set) var availableDevices: [AudioInputDevice] = []
    @Published public private(set) var isMicTesting = false
    @Published public private(set) var testAudioLevel: Float = 0.0

    private var testAudioEngine: AVAudioEngine?
    private var testTimer: Timer?

    private init() {
        refreshDevices()
    }

    public func refreshDevices() {
        var devices: [AudioInputDevice] = []
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.microphone, .external]
        } else {
            deviceTypes = [.builtInMicrophone, .externalUnknown]
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        )

        let defaultDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID

        for dev in discovery.devices {
            let isDef = (dev.uniqueID == defaultDeviceID)
            devices.append(AudioInputDevice(id: dev.uniqueID, name: dev.localizedName, isDefault: isDef))
        }

        if devices.isEmpty {
            devices.append(AudioInputDevice(id: "default", name: "System Default Microphone", isDefault: true))
        }

        self.availableDevices = devices
    }

    public static func audioDeviceID(from uniqueID: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let getStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard getStatus == noErr else { return nil }

        for devID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidString: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            let uidStatus = withUnsafeMutablePointer(to: &uidString) { ptr in
                AudioObjectGetPropertyData(devID, &uidAddress, 0, nil, &uidSize, ptr)
            }
            if uidStatus == noErr {
                if (uidString as String) == uniqueID {
                    return devID
                }
            }
        }
        return nil
    }

    @discardableResult
    public static func configureInputDevice(selectedID: String?, for engine: AVAudioEngine) -> Bool {
        guard let id = selectedID, id != "default", !id.isEmpty else { return false }
        guard let devID = audioDeviceID(from: id) else {
            print("AudioDeviceManager: Could not resolve AudioDeviceID for UID '\(id)'")
            return false
        }
        guard let audioUnit = engine.inputNode.audioUnit else {
            print("AudioDeviceManager: AVAudioEngine inputNode has no audioUnit")
            return false
        }

        var targetID = devID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &targetID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status == noErr {
            print("AudioDeviceManager: Input device routed to '\(id)' (DeviceID: \(targetID))")
            return true
        } else {
            print("AudioDeviceManager: AudioUnitSetProperty error: \(status)")
            return false
        }
    }

    public static func microphonePermissionStatus() -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static func speechRecognitionPermissionStatus() -> SFSpeechRecognizerAuthorizationStatus {
        return SFSpeechRecognizer.authorizationStatus()
    }

    public static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // Live Mic Test for Settings Window
    public func startMicTest() {
        guard !isMicTesting else { return }
        let engine = AVAudioEngine()
        AudioDeviceManager.configureInputDevice(
            selectedID: ConfigManager.shared.config.selected_audio_device_id,
            for: engine
        )
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = self.calculateRMS(from: buffer)
            DispatchQueue.main.async {
                self.testAudioLevel = level
            }
        }

        do {
            try engine.start()
            self.testAudioEngine = engine
            self.isMicTesting = true
        } catch {
            print("Failed to start mic test engine: \(error.localizedDescription)")
            stopMicTest()
        }
    }

    public func stopMicTest() {
        testAudioEngine?.stop()
        testAudioEngine?.inputNode.removeTap(onBus: 0)
        testAudioEngine = nil
        isMicTesting = false
        testAudioLevel = 0.0
    }

    private func calculateRMS(from buffer: AVAudioPCMBuffer) -> Float {
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
}
