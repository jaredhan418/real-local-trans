import Foundation

/// Thin async HTTP wrapper for OpenAI-compatible LLM APIs.
/// Supports: chat completion, audio transcription (Whisper), and TTS.
final class LLMService {

    private let config: LLMConfig

    init(config: LLMConfig) {
        self.config = config
    }

    // MARK: - Chat Completion

    /// Send a single user message and return the assistant reply text.
    func chatCompletion(systemPrompt: String, userMessage: String) async throws -> String {
        let url = URL(string: "\(config.baseURL)/chat/completions")!
        var request = makeRequest(url: url)
        request.httpMethod = "POST"

        let body: [String: Any] = [
            "model": config.chatModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userMessage]
            ],
            "temperature": 0.3,
            "max_tokens": 2048
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return (message?["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Whisper Transcription

    /// Transcribe audio data (PCM/WAV/M4A) using the Whisper-compatible endpoint.
    func transcribe(audioData: Data, filename: String = "audio.m4a", language: String? = nil) async throws -> String {
        let url = URL(string: "\(config.baseURL)/audio/transcriptions")!
        var request = makeRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // model field
        body.appendFormField("model", value: config.whisperModel, boundary: boundary)
        // language field (optional)
        if let lang = language {
            body.appendFormField("language", value: lang, boundary: boundary)
        }
        // file field
        body.appendFileField("file", filename: filename, mimeType: "audio/m4a",
                             data: audioData, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        // Override Content-Type set by makeRequest
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - TTS

    /// Synthesise `text` and return raw audio bytes (MP3).
    func synthesize(text: String, voice: String? = nil) async throws -> Data {
        let url = URL(string: "\(config.baseURL)/audio/speech")!
        var request = makeRequest(url: url)
        request.httpMethod = "POST"

        let body: [String: Any] = [
            "model": config.ttsModel,
            "input": text,
            "voice": voice ?? config.ttsVoice,
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)
        return data
    }

    // MARK: - Helpers

    private func makeRequest(url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("application/json",        forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        r.timeoutInterval = 60
        return r
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode < 200 || http.statusCode >= 300 {
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Data multipart helpers

private extension Data {
    mutating func appendFormField(_ name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendFileField(_ name: String, filename: String, mimeType: String,
                                   data fileData: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
