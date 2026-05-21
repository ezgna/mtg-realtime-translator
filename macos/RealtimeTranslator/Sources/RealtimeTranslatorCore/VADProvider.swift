import Foundation
import FluidAudio

public enum VADEvent: Equatable {
    case speechStart
    case speechEnd
}

public struct VADDecision: Equatable {
    public let probability: Float
    public let event: VADEvent?

    public init(probability: Float, event: VADEvent?) {
        self.probability = probability
        self.event = event
    }
}

public protocol VADProvider: AnyObject {
    func reset() async
    func process(samples16kMono samples: [Float]) async throws -> VADDecision
}

public actor FluidAudioVADProvider: VADProvider {
    private let manager: VadManager
    private var streamState = VadStreamState.initial()
    private let streamConfig: VadSegmentationConfig

    public init(threshold: Float = 0.75) async throws {
        manager = try await VadManager(config: VadConfig(defaultThreshold: threshold))
        streamConfig = VadSegmentationConfig(
            minSpeechDuration: 0.15,
            minSilenceDuration: Double(TranslatorConstants.silenceTailMilliseconds) / 1000.0,
            maxSpeechDuration: 14.0,
            speechPadding: 0.10,
            silenceThresholdForSplit: 0.30,
            negativeThreshold: nil,
            negativeThresholdOffset: 0.15,
            minSilenceAtMaxSpeech: 0.098,
            useMaxPossibleSilenceAtMaxSpeech: true
        )
    }

    public func reset() async {
        streamState = .initial()
    }

    public func process(samples16kMono samples: [Float]) async throws -> VADDecision {
        let result = try await manager.processStreamingChunk(
            samples,
            state: streamState,
            config: streamConfig,
            returnSeconds: true,
            timeResolution: 2
        )
        streamState = result.state

        let event: VADEvent?
        switch result.event?.kind {
        case .speechStart:
            event = .speechStart
        case .speechEnd:
            event = .speechEnd
        case nil:
            event = nil
        @unknown default:
            event = nil
        }

        return VADDecision(probability: result.probability, event: event)
    }
}
