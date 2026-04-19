import Foundation
import AVFoundation

/// Converts text to speech and plays it through a designated audio output device.
///
/// - `.appleLocal`: uses `AVSpeechSynthesizer` (built-in macOS TTS).
/// - `.llm`: fetches MP3 audio from the LLM TTS endpoint, then plays it.
@MainActor
final class SpeechSynthesisService: NSObject, ObservableObject {

    @Published private(set) var isSpeaking = false

    private let settings: AppSettings
    private let audioRouter: AudioRouterService

    // Apple TTS
    private let synthesizer = AVSpeechSynthesizer()

    // LLM TTS
    private var llmService: LLMService?
    private var audioPlayer: AVAudioPlayer?

    init(settings: AppSettings, audioRouter: AudioRouterService) {
        self.settings = settings
        self.audioRouter = audioRouter
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Speak the **source** language text on the primary output device.
    func speakSource(_ text: String) async {
        await speak(text: text, language: settings.sourceLanguage, isTarget: false)
    }

    /// Speak the **target** language text on the secondary output device.
    func speakTarget(_ text: String) async {
        await speak(text: text, language: settings.targetLanguage, isTarget: true)
    }

    // MARK: - Internal

    private func speak(text: String, language: TranslationLanguage, isTarget: Bool) async {
        guard !text.isEmpty else { return }
        switch settings.ttsProvider {
        case .appleLocal: speakApple(text: text, language: language, isTarget: isTarget)
        case .llm:        await speakLLM(text: text, language: language, isTarget: isTarget)
        }
    }

    // MARK: - Apple TTS

    private func speakApple(text: String, language: TranslationLanguage, isTarget: Bool) {
        // Route system output before speaking
        let outputUID = isTarget ? settings.secondaryOutputDeviceUID
                                 : settings.primaryOutputDeviceUID
        audioRouter.setSystemOutputDevice(uid: outputUID)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        // Pick voice: user override → locale match → system default
        let voiceID = isTarget ? settings.targetVoiceIdentifier
                               : settings.sourceVoiceIdentifier
        if !voiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: language.id)
        }

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    // MARK: - LLM TTS

    private func speakLLM(text: String, language: TranslationLanguage, isTarget: Bool) async {
        if llmService == nil || llmServiceConfigChanged() {
            llmService = LLMService(config: settings.llmConfig)
        }
        guard let llmService else { return }

        do {
            let mp3Data = try await llmService.synthesize(text: text)
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp3")
            try mp3Data.write(to: tmpURL)

            // Route output device
            let outputUID = isTarget ? settings.secondaryOutputDeviceUID
                                     : settings.primaryOutputDeviceUID
            audioRouter.setSystemOutputDevice(uid: outputUID)

            audioPlayer = try AVAudioPlayer(contentsOf: tmpURL)
            audioPlayer?.delegate = self
            isSpeaking = true
            audioPlayer?.play()
        } catch {
            print("[TTS] LLM TTS error: \(error.localizedDescription)")
        }
    }

    private var _lastLLMConfigKey: String = ""
    private func llmServiceConfigChanged() -> Bool {
        let key = settings.llmConfig.baseURL + settings.llmConfig.apiKey + settings.llmConfig.ttsModel
        if key != _lastLLMConfigKey { _lastLLMConfigKey = key; return true }
        return false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesisService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: - AVAudioPlayerDelegate

extension SpeechSynthesisService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
