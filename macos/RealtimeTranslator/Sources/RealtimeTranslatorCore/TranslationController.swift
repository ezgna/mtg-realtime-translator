import AudioToolbox
import Foundation

public struct TranslationSettings {
    public let language: String
    public let mode: TranslatorMode
    public let inputDeviceID: AudioDeviceID?
    public let outputDeviceID: AudioDeviceID?
    public let textOnly: Bool

    public init(
        language: String,
        mode: TranslatorMode,
        inputDeviceID: AudioDeviceID?,
        outputDeviceID: AudioDeviceID?,
        textOnly: Bool
    ) {
        self.language = language
        self.mode = mode
        self.inputDeviceID = inputDeviceID
        self.outputDeviceID = outputDeviceID
        self.textOnly = textOnly
    }
}

public final class TranslationController {
    public var onStatus: ((TranslatorStatus) -> Void)?
    public var onTranscriptDelta: ((String) -> Void)?
    public var onTranscriptDone: (() -> Void)?
    public var onMicLevel: ((Float) -> Void)?
    public var onLanguageConfirmed: ((String) -> Void)?
    public var onError: ((String) -> Void)?

    private let apiKeyLoader: APIKeyLoader
    private let inputQueue = DispatchQueue(label: "mtg.realtime-translator.input")
    private let speechGate = SpeechGate()
    private let presentationGate = PresentationInputGate()

    private var settings: TranslationSettings?
    private var client: RealtimeClient?
    private var backend: AudioBackend?
    private var vadProvider: VADProvider?
    private var textOnly = false
    private var isFailed = false

    public init(apiKeyLoader: APIKeyLoader = APIKeyLoader()) {
        self.apiKeyLoader = apiKeyLoader
    }

    public func start(settings: TranslationSettings) async throws {
        self.settings = settings
        textOnly = settings.textOnly
        isFailed = false
        onStatus?(.loadingVAD)

        let apiKey = try apiKeyLoader.load()
        let vad = try await FluidAudioVADProvider()
        await vad.reset()
        vadProvider = vad

        onStatus?(.connecting)
        let client = RealtimeClient()
        client.onEvent = { [weak self] event in
            self?.handleRealtimeEvent(event)
        }
        client.onDisconnect = { [weak self] error in
            if let error {
                self?.emitError(error.localizedDescription)
            } else {
                self?.onStatus?(.ready)
            }
        }
        try await client.connect(apiKey: apiKey, language: settings.language)
        self.client = client

        do {
            self.backend = try await startAudioBackend(settings: settings)
        } catch {
            client.disconnect()
            self.client = nil
            vadProvider = nil
            self.settings = nil
            throw error
        }

        speechGate.reset()
        await presentationGate.reset()
        onStatus?(.live)
    }

    public func stop() async {
        onStatus?(.stopping)
        isFailed = false
        backend?.stop()
        backend = nil
        client?.disconnect()
        client = nil
        vadProvider = nil
        settings = nil
        speechGate.reset()
        await presentationGate.reset()
        onStatus?(.ready)
    }

    public func updateLanguage(_ language: String) async {
        settings = settings.map {
            TranslationSettings(
                language: language,
                mode: $0.mode,
                inputDeviceID: $0.inputDeviceID,
                outputDeviceID: $0.outputDeviceID,
                textOnly: textOnly
            )
        }
        do {
            try await client?.updateLanguage(language)
        } catch {
            emitError(error.localizedDescription)
        }
    }

    public func setTextOnly(_ enabled: Bool) {
        textOnly = enabled
    }

    private func handleInputFrame(_ frame: AudioInputFrame) {
        inputQueue.async { [weak self] in
            guard let self else {
                return
            }
            Task {
                await self.processInputFrame(frame)
            }
        }
    }

    private func startAudioBackend(settings: TranslationSettings) async throws -> AudioBackend {
        let config = AudioBackendConfig(
            inputDeviceID: settings.inputDeviceID,
            outputDeviceID: settings.outputDeviceID
        )

        if settings.mode == .presentation {
            let voiceBackend = PresentationVoiceProcessingBackend()
            voiceBackend.onInputFrame = { [weak self] frame in
                self?.handleInputFrame(frame)
            }
            voiceBackend.onInputLevel = { [weak self] level in
                self?.onMicLevel?(level)
            }
            try await voiceBackend.start(config: config)
            return voiceBackend
        }

        let backend = RoutingBackend()
        backend.onInputFrame = { [weak self] frame in
            self?.handleInputFrame(frame)
        }
        backend.onInputLevel = { [weak self] level in
            self?.onMicLevel?(level)
        }
        try await backend.start(config: config)
        return backend
    }

    private func processInputFrame(_ frame: AudioInputFrame) async {
        guard let client, let vadProvider else {
            return
        }

        if settings?.mode == .presentation || settings?.mode == .presentationDevices {
            let allowed = await presentationGate.allowsInput()
            if !allowed {
                speechGate.reset()
                await vadProvider.reset()
                return
            }
        }

        do {
            let decision = try await vadProvider.process(samples16kMono: frame.vad16kMonoFloat)
            let frames = speechGate.process(frame: frame.pcm24kMono16, event: decision.event)
            for pcm in frames {
                try await client.sendAudio(pcm)
            }
        } catch {
            emitError(error.localizedDescription)
        }
    }

    private func handleRealtimeEvent(_ event: RealtimeEvent) {
        switch event {
        case .sessionCreated:
            break
        case .sessionUpdated(let language):
            if let language {
                onLanguageConfirmed?(language)
            }
        case .audioDelta(let data):
            guard !textOnly else {
                return
            }
            backend?.play(data)
            if settings?.mode == .presentation || settings?.mode == .presentationDevices {
                Task {
                    await presentationGate.notePlaybackScheduled(duration: AudioFormat.durationSeconds(forPCM16: data))
                }
            }
        case .transcriptDelta(let delta):
            onTranscriptDelta?(delta)
        case .transcriptDone:
            onTranscriptDone?()
        case .responseDone:
            break
        case .error(let message):
            emitError(message)
        case .ignored:
            break
        }
    }

    private func emitError(_ message: String) {
        guard !isFailed else {
            return
        }
        isFailed = true
        backend?.stop()
        backend = nil
        client?.disconnect()
        client = nil
        vadProvider = nil
        settings = nil
        speechGate.reset()
        Task {
            await presentationGate.reset()
        }
        onError?(message)
        onStatus?(.failed(message))
    }
}
