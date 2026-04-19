import Foundation
import Combine

// MARK: - Provider enums

enum STTProvider: String, CaseIterable, Codable, Identifiable {
    case appleLocal = "Apple Speech (local)"
    case llm        = "LLM / Whisper API"
    var id: String { rawValue }
}

enum TTSProvider: String, CaseIterable, Codable, Identifiable {
    case appleLocal = "Apple Speech (local)"
    case llm        = "LLM TTS API"
    var id: String { rawValue }
}

enum TranslationProvider: String, CaseIterable, Codable, Identifiable {
    case appleLocal = "Apple Translation (local)"
    case llm        = "LLM Translation API"
    var id: String { rawValue }
}

// MARK: - Language

struct TranslationLanguage: Identifiable, Hashable, Codable {
    let id: String          // BCP-47 locale identifier, e.g. "en-US", "zh-Hans"
    let displayName: String

    static let supported: [TranslationLanguage] = [
        .init(id: "en-US",   displayName: "English (US)"),
        .init(id: "zh-Hans", displayName: "Chinese (Simplified)"),
        .init(id: "zh-Hant", displayName: "Chinese (Traditional)"),
        .init(id: "ja-JP",   displayName: "Japanese"),
        .init(id: "ko-KR",   displayName: "Korean"),
        .init(id: "es-ES",   displayName: "Spanish"),
        .init(id: "fr-FR",   displayName: "French"),
        .init(id: "de-DE",   displayName: "German"),
        .init(id: "pt-BR",   displayName: "Portuguese (Brazil)"),
        .init(id: "ar-SA",   displayName: "Arabic"),
        .init(id: "hi-IN",   displayName: "Hindi"),
        .init(id: "ru-RU",   displayName: "Russian"),
        .init(id: "it-IT",   displayName: "Italian"),
    ]

    static let english = supported.first!
    static let chineseSimplified = supported.first(where: { $0.id == "zh-Hans" })!
}

// MARK: - LLM Config

struct LLMConfig: Codable {
    var baseURL: String      = "https://api.openai.com/v1"
    var apiKey:  String      = ""
    var chatModel: String    = "gpt-4o"
    var whisperModel: String = "whisper-1"
    var ttsModel: String     = "tts-1"
    var ttsVoice: String     = "alloy"
}

// MARK: - AppSettings

class AppSettings: ObservableObject {

    // ── Language pair ───────────────────────────────────────────────────────
    @Published var sourceLanguage: TranslationLanguage = .english {
        didSet { save() }
    }
    @Published var targetLanguage: TranslationLanguage = .chineseSimplified {
        didSet { save() }
    }

    // ── Provider selection ──────────────────────────────────────────────────
    @Published var sttProvider: STTProvider = .appleLocal {
        didSet { save() }
    }
    @Published var ttsProvider: TTSProvider = .appleLocal {
        didSet { save() }
    }
    @Published var translationProvider: TranslationProvider = .appleLocal {
        didSet { save() }
    }

    // ── Audio device UIDs (empty → system default) ─────────────────────────
    @Published var inputDeviceUID: String = "" {
        didSet { save() }
    }
    /// Primary output – plays the **source** language TTS
    @Published var primaryOutputDeviceUID: String = "" {
        didSet { save() }
    }
    /// Secondary output – plays the **target** language TTS
    @Published var secondaryOutputDeviceUID: String = "" {
        didSet { save() }
    }

    // ── LLM configuration ───────────────────────────────────────────────────
    @Published var llmConfig: LLMConfig = LLMConfig() {
        didSet { save() }
    }

    // ── Apple TTS voice selection ───────────────────────────────────────────
    /// BCP-47 voice identifier used for source-language TTS
    @Published var sourceVoiceIdentifier: String = "" {
        didSet { save() }
    }
    /// BCP-47 voice identifier used for target-language TTS
    @Published var targetVoiceIdentifier: String = "" {
        didSet { save() }
    }

    // MARK: Persistence

    private static let key = "AppSettingsV1"

    private struct Stored: Codable {
        var sourceLanguageID:        String
        var targetLanguageID:        String
        var sttProvider:             STTProvider
        var ttsProvider:             TTSProvider
        var translationProvider:     TranslationProvider
        var inputDeviceUID:          String
        var primaryOutputDeviceUID:  String
        var secondaryOutputDeviceUID:String
        var llmConfig:               LLMConfig
        var sourceVoiceIdentifier:   String
        var targetVoiceIdentifier:   String
    }

    init() { load() }

    private func save() {
        let stored = Stored(
            sourceLanguageID:         sourceLanguage.id,
            targetLanguageID:         targetLanguage.id,
            sttProvider:              sttProvider,
            ttsProvider:              ttsProvider,
            translationProvider:      translationProvider,
            inputDeviceUID:           inputDeviceUID,
            primaryOutputDeviceUID:   primaryOutputDeviceUID,
            secondaryOutputDeviceUID: secondaryOutputDeviceUID,
            llmConfig:                llmConfig,
            sourceVoiceIdentifier:    sourceVoiceIdentifier,
            targetVoiceIdentifier:    targetVoiceIdentifier
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.key),
            let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return }

        sourceLanguage = TranslationLanguage.supported
            .first(where: { $0.id == stored.sourceLanguageID }) ?? .english
        targetLanguage = TranslationLanguage.supported
            .first(where: { $0.id == stored.targetLanguageID }) ?? .chineseSimplified
        sttProvider              = stored.sttProvider
        ttsProvider              = stored.ttsProvider
        translationProvider      = stored.translationProvider
        inputDeviceUID           = stored.inputDeviceUID
        primaryOutputDeviceUID   = stored.primaryOutputDeviceUID
        secondaryOutputDeviceUID = stored.secondaryOutputDeviceUID
        llmConfig                = stored.llmConfig
        sourceVoiceIdentifier    = stored.sourceVoiceIdentifier
        targetVoiceIdentifier    = stored.targetVoiceIdentifier
    }
}
