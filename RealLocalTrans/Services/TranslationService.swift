import Foundation

/// Translates text from the source language to the target language.
///
/// Provider selection:
/// - `.appleLocal` – uses Apple's `Translation` framework via the SwiftUI
///   `.translationTask` modifier (macOS 15+).  If the Translation session is
///   not yet available (app hasn't received it from SwiftUI yet), the service
///   falls back to the LLM provider automatically.
/// - `.llm` – sends a chat-completion request to the configured LLM endpoint.
@MainActor
final class TranslationService: ObservableObject {

    private let settings: AppSettings
    private var llmService: LLMService?

    // Set by ContentView when a SwiftUI TranslationSession is available (macOS 15+).
    // Stored as a closure to allow compilation on macOS 14.
    var appleTranslationHandler: ((String) async throws -> String)?

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Public API

    /// Translate `text` from `settings.sourceLanguage` to `settings.targetLanguage`.
    func translate(text: String) async throws -> String {
        guard !text.isEmpty else { return "" }

        switch settings.translationProvider {
        case .appleLocal:
            if let handler = appleTranslationHandler {
                do {
                    return try await handler(text)
                } catch {
                    print("[Translation] Apple translation failed, falling back to LLM: \(error)")
                    return try await translateLLM(text: text)
                }
            } else {
                // Apple Translation session not yet available; fall back to LLM
                print("[Translation] Apple Translation session not available. Falling back to LLM.")
                return try await translateLLM(text: text)
            }
        case .llm:
            return try await translateLLM(text: text)
        }
    }

    // MARK: - LLM Translation

    private func translateLLM(text: String) async throws -> String {
        if llmService == nil { llmService = LLMService(config: settings.llmConfig) }
        guard let llmService else { throw TranslationError.notConfigured }

        let systemPrompt = """
        You are a professional translator. \
        Translate the following text from \(settings.sourceLanguage.displayName) \
        to \(settings.targetLanguage.displayName). \
        Output only the translated text with no explanations or extra commentary.
        """

        return try await llmService.chatCompletion(systemPrompt: systemPrompt, userMessage: text)
    }

    // MARK: - Errors

    enum TranslationError: LocalizedError {
        case notAvailable
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Apple Translation is not available. Please configure an LLM provider in Settings."
            case .notConfigured:
                return "LLM service is not configured. Please add an API key in Settings."
            }
        }
    }
}
