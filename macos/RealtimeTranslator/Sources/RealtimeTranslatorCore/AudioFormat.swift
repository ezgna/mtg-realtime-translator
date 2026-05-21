import AVFoundation
import Foundation

public enum AudioFormatError: Error {
    case unsupportedBuffer
    case conversionFailed
}

public enum AudioFormat {
    public static var networkFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: TranslatorConstants.sampleRate,
            channels: AVAudioChannelCount(TranslatorConstants.channels),
            interleaved: false
        )!
    }

    public static var vadFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: TranslatorConstants.vadSampleRate,
            channels: AVAudioChannelCount(TranslatorConstants.channels),
            interleaved: false
        )!
    }

    public static func pcm16Data(fromFloatSamples samples: [Float]) -> Data {
        let ints = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }
        return ints.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    public static func floatSamples(fromPCM16 data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        return data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: Int16.self).baseAddress else {
                return []
            }
            return (0..<sampleCount).map { index in
                Float(base[index]) / Float(Int16.max)
            }
        }
    }

    public static func pcm16Buffer(from data: Data) -> AVAudioPCMBuffer? {
        let samples = floatSamples(fromPCM16: data)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: networkFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }

    public static func monoFloatSamples(from buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) throws -> [Float] {
        let converted = try convert(buffer, to: targetFormat)
        guard let channel = converted.floatChannelData?[0] else {
            throw AudioFormatError.unsupportedBuffer
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
    }

    public static func convert(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == targetFormat {
            return buffer
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            throw AudioFormatError.conversionFailed
        }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = max(1, AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 8)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw AudioFormatError.conversionFailed
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            if didProvideInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if status == .error || conversionError != nil {
            throw conversionError ?? AudioFormatError.conversionFailed
        }
        return converted
    }

    public static func durationSeconds(forPCM16 data: Data) -> TimeInterval {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        return Double(sampleCount) / TranslatorConstants.sampleRate
    }
}

public struct AudioInputFrame {
    public let pcm24kMono16: Data
    public let vad16kMonoFloat: [Float]
    public let level: Float

    public init(pcm24kMono16: Data, vad16kMonoFloat: [Float], level: Float) {
        self.pcm24kMono16 = pcm24kMono16
        self.vad16kMonoFloat = vad16kMonoFloat
        self.level = level
    }
}
