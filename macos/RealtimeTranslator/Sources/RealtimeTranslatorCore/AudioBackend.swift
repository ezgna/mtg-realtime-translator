import AudioToolbox
import AVFoundation
import Foundation

public struct AudioBackendConfig {
    public let inputDeviceID: AudioDeviceID?
    public let outputDeviceID: AudioDeviceID?

    public init(inputDeviceID: AudioDeviceID?, outputDeviceID: AudioDeviceID?) {
        self.inputDeviceID = inputDeviceID
        self.outputDeviceID = outputDeviceID
    }
}

public protocol AudioBackend: AnyObject {
    var onInputFrame: ((AudioInputFrame) -> Void)? { get set }
    var onInputLevel: ((Float) -> Void)? { get set }
    func start(config: AudioBackendConfig) async throws
    func stop()
    func play(_ pcm16: Data)
}

public final class PresentationVoiceProcessingBackend: AVAudioEngineBackend {
    public init() {
        super.init(voiceProcessingEnabled: true, allowsDeviceSelection: false)
    }
}

public final class RoutingBackend: AVAudioEngineBackend {
    public init() {
        super.init(voiceProcessingEnabled: false, allowsDeviceSelection: true)
    }
}

public class AVAudioEngineBackend: AudioBackend {
    public var onInputFrame: ((AudioInputFrame) -> Void)?
    public var onInputLevel: ((Float) -> Void)?

    private let voiceProcessingEnabled: Bool
    private let allowsDeviceSelection: Bool
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let inputMonitor = AVAudioMixerNode()
    private let callbackQueue = DispatchQueue(label: "mtg.realtime-translator.audio-callback")
    private var isRunning = false

    public init(voiceProcessingEnabled: Bool, allowsDeviceSelection: Bool) {
        self.voiceProcessingEnabled = voiceProcessingEnabled
        self.allowsDeviceSelection = allowsDeviceSelection
    }

    public func start(config: AudioBackendConfig) async throws {
        guard !isRunning else {
            return
        }

        let granted = await requestMicrophoneAccess()
        guard granted else {
            throw AudioBackendError.microphonePermissionDenied
        }

        let inputNode = engine.inputNode
        let outputNode = engine.outputNode
        engine.attach(player)
        engine.attach(inputMonitor)
        inputMonitor.outputVolume = 0

        if allowsDeviceSelection {
            try applyDevice(config.inputDeviceID, to: inputNode)
            try applyDevice(config.outputDeviceID, to: outputNode)
        }

        let inputFormat: AVAudioFormat
        if voiceProcessingEnabled {
            let voiceProcessingFormat = inputNode.outputFormat(forBus: 0)
            engine.connect(engine.mainMixerNode, to: outputNode, format: voiceProcessingFormat)
            do {
                try inputNode.setVoiceProcessingEnabled(true)
            } catch {
                throw AudioBackendError.voiceProcessingUnavailable(error.localizedDescription)
            }
            guard inputNode.isVoiceProcessingEnabled && outputNode.isVoiceProcessingEnabled else {
                throw AudioBackendError.voiceProcessingUnavailable("Voice Processing I/O was not enabled on both input and output nodes")
            }
            inputFormat = inputNode.outputFormat(forBus: 0)
        } else {
            inputFormat = inputNode.outputFormat(forBus: 0)
        }

        engine.connect(player, to: engine.mainMixerNode, format: AudioFormat.networkFormat)
        engine.connect(inputNode, to: inputMonitor, format: inputFormat)
        engine.connect(inputMonitor, to: engine.mainMixerNode, format: inputFormat)

        let tapFrameCount = AVAudioFrameCount(
            max(1, Int(inputFormat.sampleRate) * TranslatorConstants.chunkMilliseconds / 1_000)
        )
        inputNode.installTap(
            onBus: 0,
            bufferSize: tapFrameCount,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            if voiceProcessingEnabled {
                throw AudioBackendError.voiceProcessingUnavailable(error.localizedDescription)
            }
            throw error
        }
        player.play()
        isRunning = true
    }

    public func stop() {
        guard isRunning else {
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        if voiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        isRunning = false
    }

    public func play(_ pcm16: Data) {
        guard let buffer = AudioFormat.pcm16Buffer(from: pcm16) else {
            return
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        callbackQueue.async { [weak self] in
            guard let self else {
                return
            }
            do {
                let level = rmsLevel(buffer: buffer)
                self.onInputLevel?(level)
                let networkSamples = try AudioFormat.monoFloatSamples(from: buffer, targetFormat: AudioFormat.networkFormat)
                let vadSamples = try AudioFormat.monoFloatSamples(from: buffer, targetFormat: AudioFormat.vadFormat)
                let pcm = AudioFormat.pcm16Data(fromFloatSamples: networkSamples)
                let frame = AudioInputFrame(
                    pcm24kMono16: pcm,
                    vad16kMonoFloat: vadSamples,
                    level: level
                )
                self.onInputFrame?(frame)
            } catch {
                // Audio callbacks must not throw. The session controller reports
                // user-visible errors from the non-realtime path.
            }
        }
    }

    private func applyDevice(_ deviceID: AudioDeviceID?, to node: AVAudioIONode) throws {
        guard var deviceID else {
            return
        }
        guard let audioUnit = node.audioUnit else {
            return
        }
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            kAudioObjectPropertyElementMain,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            throw AudioBackendError.deviceSelectionFailed(status)
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

public enum AudioBackendError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case deviceSelectionFailed(OSStatus)
    case voiceProcessingUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone permission was denied"
        case .deviceSelectionFailed(let status):
            "Audio device selection failed: \(status)"
        case .voiceProcessingUnavailable(let message):
            "Apple Voice Processing I/O failed: \(message)"
        }
    }
}

private func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
    guard
        buffer.frameLength > 0,
        let channel = buffer.floatChannelData?[0]
    else {
        return 0
    }
    let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
    var sum = Float(0)
    for sample in samples {
        sum += sample * sample
    }
    return sqrt(sum / Float(samples.count))
}
