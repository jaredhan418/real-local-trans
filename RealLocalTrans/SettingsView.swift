import SwiftUI
import AVFoundation

/// Settings sheet – languages, providers, audio devices, LLM configuration.
struct SettingsView: View {

    @EnvironmentObject var settings:    AppSettings
    @EnvironmentObject var audioRouter: AudioRouterService

    var body: some View {
        TabView {
            LanguageTab()
                .tabItem { Label("Languages", systemImage: "globe") }

            ProvidersTab()
                .tabItem { Label("Providers", systemImage: "cpu") }

            AudioDevicesTab()
                .tabItem { Label("Audio", systemImage: "hifispeaker.2.fill") }

            LLMConfigTab()
                .tabItem { Label("LLM / API", systemImage: "key.fill") }
        }
        .padding(20)
        .environmentObject(settings)
        .environmentObject(audioRouter)
    }
}

// MARK: - Language Tab

private struct LanguageTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Source Language (input / speaker A)") {
                Picker("Source", selection: $settings.sourceLanguage) {
                    ForEach(TranslationLanguage.supported) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Target Language (translation / speaker B)") {
                Picker("Target", selection: $settings.targetLanguage) {
                    ForEach(TranslationLanguage.supported) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Providers Tab

private struct ProvidersTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Speech-to-Text (STT)") {
                Picker("Provider", selection: $settings.sttProvider) {
                    ForEach(STTProvider.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Translation") {
                Picker("Provider", selection: $settings.translationProvider) {
                    ForEach(TranslationProvider.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.translationProvider == .appleLocal {
                    Text("Apple Translation requires macOS 15 Sequoia or later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Text-to-Speech (TTS)") {
                Picker("Provider", selection: $settings.ttsProvider) {
                    ForEach(TTSProvider.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            if settings.ttsProvider == .appleLocal {
                Section("Apple TTS Voices") {
                    VoicePicker(label: "Source voice (\(settings.sourceLanguage.displayName))",
                                languageID: settings.sourceLanguage.id,
                                selected: $settings.sourceVoiceIdentifier)

                    VoicePicker(label: "Target voice (\(settings.targetLanguage.displayName))",
                                languageID: settings.targetLanguage.id,
                                selected: $settings.targetVoiceIdentifier)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Voice Picker helper

private struct VoicePicker: View {
    let label: String
    let languageID: String
    @Binding var selected: String

    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(String(languageID.prefix(2))) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Picker(label, selection: $selected) {
            Text("System Default").tag("")
            ForEach(voices, id: \.identifier) { voice in
                Text("\(voice.name) (\(voice.quality == .enhanced ? "Enhanced" : "Standard"))")
                    .tag(voice.identifier)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Audio Devices Tab

private struct AudioDevicesTab: View {
    @EnvironmentObject var settings:    AppSettings
    @EnvironmentObject var audioRouter: AudioRouterService

    var body: some View {
        Form {
            Section("Microphone Input") {
                DevicePicker(label: "Input device",
                             devices: audioRouter.inputDevices,
                             selectedUID: $settings.inputDeviceUID)
            }

            Section("Output A – Source Language (\(settings.sourceLanguage.displayName))") {
                DevicePicker(label: "Output device A",
                             devices: audioRouter.outputDevices,
                             selectedUID: $settings.primaryOutputDeviceUID)
                Text("E.g. connect AirPods or headphones that should hear the original speech.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Output B – Target Language (\(settings.targetLanguage.displayName))") {
                DevicePicker(label: "Output device B",
                             devices: audioRouter.outputDevices,
                             selectedUID: $settings.secondaryOutputDeviceUID)
                Text("E.g. a second pair of AirPods that should hear the translated speech.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Refresh Devices") {
                audioRouter.refresh()
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DevicePicker: View {
    let label: String
    let devices: [AudioDevice]
    @Binding var selectedUID: String

    var body: some View {
        Picker(label, selection: $selectedUID) {
            ForEach(devices) { device in
                Text(device.name).tag(device.uid)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - LLM / API Tab

private struct LLMConfigTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showKey = false

    var body: some View {
        Form {
            Section("Endpoint") {
                TextField("Base URL", text: $settings.llmConfig.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .help("OpenAI-compatible base URL, e.g. https://api.openai.com/v1")
            }

            Section("Authentication") {
                HStack {
                    if showKey {
                        TextField("API Key", text: $settings.llmConfig.apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $settings.llmConfig.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Models") {
                TextField("Chat model",    text: $settings.llmConfig.chatModel)
                    .textFieldStyle(.roundedBorder)
                    .help("Used for translation, e.g. gpt-4o")
                TextField("Whisper model", text: $settings.llmConfig.whisperModel)
                    .textFieldStyle(.roundedBorder)
                    .help("Used for STT, e.g. whisper-1")
                TextField("TTS model",     text: $settings.llmConfig.ttsModel)
                    .textFieldStyle(.roundedBorder)
                    .help("Used for TTS, e.g. tts-1")
                TextField("TTS voice",     text: $settings.llmConfig.ttsVoice)
                    .textFieldStyle(.roundedBorder)
                    .help("Voice name for LLM TTS, e.g. alloy, echo, fable, onyx, nova, shimmer")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
        .environmentObject(AudioRouterService())
        .frame(width: 540, height: 420)
}
