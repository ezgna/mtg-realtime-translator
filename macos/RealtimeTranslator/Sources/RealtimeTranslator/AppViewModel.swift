import AudioToolbox
import Combine
import Foundation
import RealtimeTranslatorCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedLanguage = "en"
    @Published var selectedMode: TranslatorMode = .presentation
    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID?
    @Published var selectedOutputDeviceID: AudioDeviceID?
    @Published var textOnly = false
    @Published var transcript = ""
    @Published var status: TranslatorStatus = .idle
    @Published var micLevel: Float = 0
    @Published var defaultInputDeviceName = "System default"
    @Published var defaultOutputDeviceName = "System default"
    @Published var isRunning = false
    @Published var note = "Presentation は既定入出力 + Apple Voice Processing I/O。iPhone などを選ぶ場合は Presentation + Devices を使います。"

    let languages = LanguageOption.supported
    let modes = TranslatorMode.allCases

    private let controller = TranslationController()

    init() {
        wireController()
        refreshDevices()
    }

    func refreshDevices() {
        inputDevices = AudioDeviceService.inputDevices()
        outputDevices = AudioDeviceService.outputDevices()
        defaultInputDeviceName = AudioDeviceService.defaultInputDevice()?.name ?? "System default"
        defaultOutputDeviceName = AudioDeviceService.defaultOutputDevice()?.name ?? "System default"
    }

    func modeChanged() {
        if selectedMode == .presentation {
            selectedInputDeviceID = nil
            selectedOutputDeviceID = nil
            note = "Presentation は Apple Voice Processing I/O を優先し、macOS の既定入出力を使います。Input/Output の個別指定は Routing で使います。"
        } else if selectedMode == .presentationDevices {
            note = "Presentation + Devices は iPhone など任意デバイスを使う発表モードです。Apple AEC は保証せず、翻訳音声の再生中は入力を止めます。"
        } else {
            note = "Routing は BlackHole/Teams 用です。任意の Input/Output を選べますが、AEC は保証しません。"
        }
        restartIfRunning()
    }

    func deviceSelectionChanged() {
        guard selectedMode != .presentation else {
            return
        }
        restartIfRunning()
    }

    func startStop() {
        if isRunning {
            Task {
                await controller.stop()
                await MainActor.run {
                    isRunning = false
                }
            }
            return
        }

        start(settings: currentSettings())
    }

    func restartIfRunning() {
        guard isRunning else {
            return
        }
        let settings = currentSettings()
        Task {
            await controller.stop()
            await MainActor.run {
                isRunning = false
            }
            start(settings: settings)
        }
    }

    func clearTranscript() {
        transcript = ""
    }

    func applyListenPreset() {
        selectedLanguage = "ja"
        selectedMode = .routing
        selectedInputDeviceID = firstBlackHoleID(in: inputDevices)
        selectedOutputDeviceID = nil
        note = "Teams: Speaker=BlackHole 2ch / Microphone=普段のマイク。Translator は Input=BlackHole、Output=System default。"
        restartIfRunning()
    }

    func applySpeakPreset() {
        selectedLanguage = "en"
        selectedMode = .routing
        selectedInputDeviceID = nil
        selectedOutputDeviceID = firstBlackHoleID(in: outputDevices)
        note = "Teams: Speaker=普段のイヤホン・スピーカー / Microphone=BlackHole 2ch。Translator は Input=System default、Output=BlackHole。"
        restartIfRunning()
    }

    func updateLanguageIfNeeded() {
        guard isRunning else {
            return
        }
        Task {
            await controller.updateLanguage(selectedLanguage)
        }
    }

    func updateTextOnly() {
        controller.setTextOnly(textOnly)
    }

    private func wireController() {
        controller.onStatus = { [weak self] status in
            DispatchQueue.main.async {
                self?.status = status
                if case .live = status {
                    self?.isRunning = true
                } else if case .failed = status {
                    self?.isRunning = false
                } else if status == .ready || status == .idle {
                    self?.isRunning = false
                }
            }
        }
        controller.onTranscriptDelta = { [weak self] delta in
            DispatchQueue.main.async {
                self?.transcript += delta
            }
        }
        controller.onTranscriptDone = { [weak self] in
            DispatchQueue.main.async {
                self?.transcript += "\n\n"
            }
        }
        controller.onMicLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.micLevel = normalizedMicLevel(fromRMS: level)
            }
        }
        controller.onLanguageConfirmed = { [weak self] language in
            DispatchQueue.main.async {
                if self?.selectedLanguage != language {
                    self?.selectedLanguage = language
                }
            }
        }
        controller.onError = { [weak self] message in
            DispatchQueue.main.async {
                self?.transcript += "\n[Error] \(message)\n"
            }
        }
    }

    private func currentSettings() -> TranslationSettings {
        TranslationSettings(
            language: selectedLanguage,
            mode: selectedMode,
            inputDeviceID: selectedMode == .presentation ? nil : selectedInputDeviceID,
            outputDeviceID: selectedMode == .presentation ? nil : selectedOutputDeviceID,
            textOnly: textOnly
        )
    }

    private func start(settings: TranslationSettings) {
        Task {
            do {
                try await controller.start(settings: settings)
                await MainActor.run {
                    isRunning = true
                }
            } catch {
                await MainActor.run {
                    status = .failed(error.localizedDescription)
                    transcript += "\n[Error] \(error.localizedDescription)\n"
                    isRunning = false
                }
            }
        }
    }

    private func firstBlackHoleID(in devices: [AudioDevice]) -> AudioDeviceID? {
        devices.first { $0.name.localizedCaseInsensitiveContains("blackhole") }?.id
    }
}

private func normalizedMicLevel(fromRMS rms: Float) -> Float {
    let floor: Float = 0.000_01
    let decibels = 20 * log10(max(rms, floor))
    return min(max((decibels + 90) / 70, 0), 1)
}
