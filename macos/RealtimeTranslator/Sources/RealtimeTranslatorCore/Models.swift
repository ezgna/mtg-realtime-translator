import AVFoundation
import Foundation

public enum TranslatorConstants {
    public static let sampleRate: Double = 24_000
    public static let vadSampleRate: Double = 16_000
    public static let channels: AVAudioChannelCount = 1
    public static let chunkMilliseconds = 20
    public static let chunkSamples = Int(sampleRate) * chunkMilliseconds / 1000
    public static let silenceTailMilliseconds = 800
    public static let silenceTailChunks = silenceTailMilliseconds / chunkMilliseconds
    public static let preRollMilliseconds = 240
    public static let preRollChunks = preRollMilliseconds / chunkMilliseconds
    public static let presentationInputHoldoffMilliseconds = 700
    public static let model = "gpt-realtime-translate"
    public static let websocketURL = URL(string: "wss://api.openai.com/v1/realtime/translations?model=\(model)")!
}

public struct LanguageOption: Identifiable, Hashable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    public static let supported: [LanguageOption] = [
        .init(id: "en", label: "English"),
        .init(id: "ja", label: "日本語"),
        .init(id: "es", label: "Español"),
        .init(id: "pt", label: "Português"),
        .init(id: "fr", label: "Français"),
        .init(id: "it", label: "Italiano"),
        .init(id: "de", label: "Deutsch"),
        .init(id: "ru", label: "Русский"),
        .init(id: "zh", label: "中文"),
        .init(id: "ko", label: "한국어"),
        .init(id: "hi", label: "हिन्दी"),
        .init(id: "id", label: "Bahasa Indonesia"),
        .init(id: "vi", label: "Tiếng Việt"),
    ]
}

public enum TranslatorMode: String, CaseIterable, Identifiable {
    case presentation
    case presentationDevices
    case routing

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .presentation: "Presentation"
        case .presentationDevices: "Presentation + Devices"
        case .routing: "Routing"
        }
    }

    public var detail: String {
        switch self {
        case .presentation:
            "Apple Voice Processing I/O と再生中ミュートで、会場発表時の自己再入力を抑えます。"
        case .presentationDevices:
            "iPhone など任意デバイスを使う発表モードです。Apple AEC は保証せず、再生中ミュートで自己再入力を抑えます。"
        case .routing:
            "BlackHole/Teams 用の互換経路です。任意デバイス指定を優先し、AEC は保証しません。"
        }
    }
}

public enum TranslatorStatus: Equatable {
    case idle
    case loadingVAD
    case connecting
    case ready
    case live
    case stopping
    case failed(String)

    public var text: String {
        switch self {
        case .idle: "Idle"
        case .loadingVAD: "Loading VAD"
        case .connecting: "Connecting"
        case .ready: "Ready"
        case .live: "Live"
        case .stopping: "Stopping"
        case .failed: "Error"
        }
    }
}
