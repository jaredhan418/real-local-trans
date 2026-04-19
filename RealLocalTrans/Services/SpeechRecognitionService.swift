import Foundation
import Speech
import AVFoundation

/// Captures audio from the selected input device and converts speech to text.
///
/// - When `provider == .appleLocal` it uses Apple's `Speech` framework.
/// - When `provider == .llm` it records a short segment, then sends it to the
///   Whisper-compatible LLM transcription endpoint.
@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var isListening = false
    @Published private(set) var partialTranscript = ""

    // MARK: - Callback

    /// Called whenever a final transcript segment is ready.
    var onFinalTranscript: ((String) -> Void)?

    // MARK: - Private

    private let settings: AppSettings
    private let audioRouter: AudioRouterService
    private var llmService: LLMService?

    // Apple Speech
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // LLM recording
    private var llmRecordingTimer: Task<Void, Never>?

    init(settings: AppSettings, audioRouter: AudioRouterService) {
        self.settings = settings
        self.audioRouter = audioRouter
        super.init()
    }

    // MARK: - Public API

    func start() async {
        guard !isListening else { return }

        updateLLMService()

        // Request microphone permission
        let granted = await requestMicPermission()
        guard granted else {
            print("[STT] Microphone permission denied")
            return
        }

        // Switch input device if configured
        audioRouter.setSystemInputDevice(uid: settings.inputDeviceUID)

        switch settings.sttProvider {
        case .appleLocal: startAppleSTT()
        case .llm:        await startLLMSTT()
        }
    }

    func stop() {
        guard isListening else { return }
        switch settings.sttProvider {
        case .appleLocal: stopAppleSTT()
        case .llm:        stopLLMSTT()
        }
        isListening = false
        partialTranscript = ""
    }

    // MARK: - Apple STT

    private func startAppleSTT() {
        let locale = Locale(identifier: settings.sourceLanguage.id)
        recognizer = SFSpeechRecognizer(locale: locale)
        recognizer?.delegate = self

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                print("[STT] Speech recognition not authorized: \(status.rawValue)")
                return
            }
        }

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                Task { @MainActor in
                    self.partialTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.onFinalTranscript?(result.bestTranscription.formattedString)
                        self.partialTranscript = ""
                        // Restart for continuous recognition
                        self.stopAppleSTT()
                        self.startAppleSTT()
                    }
                }
            }
            if let error = error {
                print("[STT] Recognition error: \(error.localizedDescription)")
            }
        }

        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("[STT] AudioEngine start error: \(error.localizedDescription)")
        }
    }

    private func stopAppleSTT() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // MARK: - LLM STT (Whisper)
    // Records a fixed-duration chunk and sends it to the Whisper endpoint.

    private func startLLMSTT() async {
        guard llmService != nil else {
            print("[STT] LLM service not configured")
            return
        }
        isListening = true
        scheduleNextLLMChunk()
    }

    private func scheduleNextLLMChunk() {
        llmRecordingTimer = Task { [weak self] in
            guard let self else { return }
            await self.recordAndTranscribeChunk()
            if self.isListening {
                self.scheduleNextLLMChunk()
            }
        }
    }

    private func recordAndTranscribeChunk() async {
        guard let llmService else { return }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)

        do {
            let file = try AVAudioFile(forWriting: tmpURL,
                                       settings: format.settings)
            node.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                try? file.write(from: buffer)
            }
            try audioEngine.start()
        } catch {
            print("[STT] LLM record start error: \(error.localizedDescription)")
            return
        }

        // Record for ~5 seconds per chunk
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        audioEngine.stop()
        node.removeTap(onBus: 0)

        guard let data = try? Data(contentsOf: tmpURL) else { return }
        try? FileManager.default.removeItem(at: tmpURL)

        do {
            let languageCode = String(settings.sourceLanguage.id.prefix(2))
            let text = try await llmService.transcribe(audioData: data, language: languageCode)
            if !text.isEmpty {
                partialTranscript = text
                onFinalTranscript?(text)
                partialTranscript = ""
            }
        } catch {
            print("[STT] Whisper error: \(error.localizedDescription)")
        }
    }

    private func stopLLMSTT() {
        llmRecordingTimer?.cancel()
        llmRecordingTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    // MARK: - Helpers

    private func updateLLMService() {
        llmService = LLMService(config: settings.llmConfig)
    }

    private func requestMicPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechRecognitionService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer,
                                      availabilityDidChange available: Bool) {
        if !available {
            print("[STT] Speech recognizer became unavailable")
        }
    }
}
