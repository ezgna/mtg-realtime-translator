import RealtimeTranslatorCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 18) {
            header
            Divider()
            controls
            presets
            transcript
            footer
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Realtime Translator")
                .font(.headline)
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(viewModel.status.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        Grid(horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                caption("Output language")
                caption("Mode")
                caption("Input")
                caption("Output")
            }
            GridRow {
                Picker("", selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.languages) { language in
                        Text("\(language.label) · \(language.id)").tag(language.id)
                    }
                }
                .labelsHidden()
                .onChange(of: viewModel.selectedLanguage) {
                    viewModel.updateLanguageIfNeeded()
                }

                Picker("", selection: $viewModel.selectedMode) {
                    ForEach(viewModel.modes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .onChange(of: viewModel.selectedMode) {
                    viewModel.modeChanged()
                }

                Picker("", selection: $viewModel.selectedInputDeviceID) {
                    Text("System default (\(viewModel.defaultInputDeviceName))").tag(Optional<UInt32>.none)
                    ForEach(viewModel.inputDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                .disabled(viewModel.selectedMode == .presentation)
                .onChange(of: viewModel.selectedInputDeviceID) {
                    viewModel.deviceSelectionChanged()
                }

                Picker("", selection: $viewModel.selectedOutputDeviceID) {
                    Text("System default (\(viewModel.defaultOutputDeviceName))").tag(Optional<UInt32>.none)
                    ForEach(viewModel.outputDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                .disabled(viewModel.selectedMode == .presentation)
                .onChange(of: viewModel.selectedOutputDeviceID) {
                    viewModel.deviceSelectionChanged()
                }
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Teamsプリセット")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("相手の英語 → 日本語") {
                    viewModel.applyListenPreset()
                }
                Button("自分の日本語 → 英語") {
                    viewModel.applySpeakPreset()
                }
                Button("Refresh devices") {
                    viewModel.refreshDevices()
                }
            }
            Text(viewModel.note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Translation")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(viewModel.transcript.isEmpty ? " " : viewModel.transcript)
                    .font(.system(size: 17))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MIC LEVEL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(viewModel.micLevel))
                    .frame(width: 220)
            }
            Spacer()
            Toggle("Text only", isOn: $viewModel.textOnly)
                .toggleStyle(.checkbox)
                .onChange(of: viewModel.textOnly) {
                    viewModel.updateTextOnly()
                }
            Button("Clear") {
                viewModel.clearTranscript()
            }
            Button(viewModel.isRunning ? "Stop" : "Start") {
                viewModel.startStop()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .live:
            .green
        case .ready:
            .yellow
        case .failed:
            .red
        case .connecting, .loadingVAD, .stopping:
            .orange
        case .idle:
            .secondary
        }
    }
}
