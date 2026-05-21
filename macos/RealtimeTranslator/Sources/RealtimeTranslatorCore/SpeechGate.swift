import Foundation

public final class SpeechGate {
    private let preRollLimit: Int
    private let tailChunkCount: Int
    private let silenceFrame: Data
    private var preRoll: [Data] = []
    private var isInSpeech = false
    private var tailRemaining = 0

    public init(
        preRollLimit: Int = TranslatorConstants.preRollChunks,
        tailChunkCount: Int = TranslatorConstants.silenceTailChunks,
        frameByteCount: Int = TranslatorConstants.chunkSamples * MemoryLayout<Int16>.size
    ) {
        self.preRollLimit = preRollLimit
        self.tailChunkCount = tailChunkCount
        self.silenceFrame = Data(repeating: 0, count: frameByteCount)
    }

    public func reset() {
        preRoll.removeAll(keepingCapacity: true)
        isInSpeech = false
        tailRemaining = 0
    }

    public func process(frame: Data, event: VADEvent?) -> [Data] {
        var output: [Data] = []

        if event == .speechStart, !isInSpeech {
            isInSpeech = true
            tailRemaining = 0
            output.append(contentsOf: preRoll)
            preRoll.removeAll(keepingCapacity: true)
        }

        if event == .speechEnd, isInSpeech {
            isInSpeech = false
            tailRemaining = tailChunkCount
        }

        if isInSpeech {
            output.append(frame)
        } else if tailRemaining > 0 {
            tailRemaining -= 1
            output.append(silenceFrame)
        } else {
            preRoll.append(frame)
            if preRoll.count > preRollLimit {
                preRoll.removeFirst(preRoll.count - preRollLimit)
            }
        }

        return output
    }
}

public actor PresentationInputGate {
    private var suppressUntil: Date?

    public init() {}

    public func reset() {
        suppressUntil = nil
    }

    public func notePlaybackScheduled(duration: TimeInterval) {
        let holdoff = Double(TranslatorConstants.presentationInputHoldoffMilliseconds) / 1000.0
        let until = Date().addingTimeInterval(duration + holdoff)
        if let current = suppressUntil {
            suppressUntil = max(current, until)
        } else {
            suppressUntil = until
        }
    }

    public func allowsInput(now: Date = Date()) -> Bool {
        guard let suppressUntil else {
            return true
        }
        return now >= suppressUntil
    }
}
