import SwiftUI

/// Main live-translation window.
struct ContentView: View {

    @EnvironmentObject var settings:    AppSettings
    @EnvironmentObject var audioRouter: AudioRouterService

    // Services (owned here so they share state across the view)
    @StateObject private var sttService: SpeechRecognitionService
    @StateObject private var ttsService: SpeechSynthesisService
    @StateObject private var translationService: TranslationService

    @State private var sourceTranscript  = ""
    @State private var targetTranslation = ""
    @State private var errorMessage: String?
    @State private var showSettings = false

    // We cannot use @EnvironmentObject inside an init, so we use a custom init
    // that receives the objects from the environment via a wrapper view.
    init(settings: AppSettings, audioRouter: AudioRouterService) {
        _sttService = StateObject(wrappedValue:
            SpeechRecognitionService(settings: settings, audioRouter: audioRouter))
        _ttsService = StateObject(wrappedValue:
            SpeechSynthesisService(settings: settings, audioRouter: audioRouter))
        _translationService = StateObject(wrappedValue:
            TranslationService(settings: settings))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            transcriptArea
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(audioRouter)
                .frame(width: 540)
        }
        .onAppear { wireCallbacks() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {

            // Language pair badge
            HStack(spacing: 6) {
                Label(settings.sourceLanguage.displayName, systemImage: "mic.fill")
                    .labelStyle(.titleAndIcon)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Label(settings.targetLanguage.displayName, systemImage: "speaker.wave.2.fill")
                    .labelStyle(.titleAndIcon)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Status indicator
            if sttService.isListening {
                Label("Listening…", systemImage: "waveform")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative)
            }

            // Start / Stop button
            Button(action: toggleListening) {
                Label(
                    sttService.isListening ? "Stop" : "Start",
                    systemImage: sttService.isListening ? "stop.circle.fill" : "play.circle.fill"
                )
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(sttService.isListening ? .red : .accentColor)

            // Settings button
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Open Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Transcript area

    private var transcriptArea: some View {
        HStack(spacing: 0) {
            // Source panel
            TranscriptPanel(
                title: settings.sourceLanguage.displayName,
                icon:  "mic.fill",
                tintColor: .blue,
                partial:   sttService.partialTranscript,
                text:      $sourceTranscript
            )

            Divider()

            // Target panel
            TranscriptPanel(
                title: settings.targetLanguage.displayName,
                icon:  "globe",
                tintColor: .green,
                partial:   "",
                text:      $targetTranslation
            )
        }
        .overlay(alignment: .bottom) {
            if let msg = errorMessage {
                ErrorBanner(message: msg) { errorMessage = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: errorMessage)
    }

    // MARK: - Actions

    private func toggleListening() {
        if sttService.isListening {
            sttService.stop()
        } else {
            Task { await sttService.start() }
        }
    }

    private func wireCallbacks() {
        sttService.onFinalTranscript = { [weak self] text in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sourceTranscript += (self.sourceTranscript.isEmpty ? "" : "\n") + text

                // Translate
                do {
                    let translation = try await self.translationService.translate(text: text)
                    self.targetTranslation += (self.targetTranslation.isEmpty ? "" : "\n") + translation

                    // Speak both channels (fire-and-forget – audio renders on background thread)
                    await self.ttsService.speakSource(text)
                    await self.ttsService.speakTarget(translation)
                } catch {
                    withAnimation { self.errorMessage = error.localizedDescription }
                }
            }
        }
    }
}

// MARK: - ContentView wrapper (injects environment objects into init)

/// Thin wrapper that injects environment objects into ContentView's custom init.
struct ContentViewWrapper: View {
    @EnvironmentObject var settings:    AppSettings
    @EnvironmentObject var audioRouter: AudioRouterService

    var body: some View {
        ContentView(settings: settings, audioRouter: audioRouter)
            .environmentObject(settings)
            .environmentObject(audioRouter)
    }
}

// MARK: - TranscriptPanel

struct TranscriptPanel: View {
    let title: String
    let icon: String
    let tintColor: Color
    let partial: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tintColor)
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Clear") { text = "" }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.quaternary)

            Divider()

            // Transcript scroll view
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !partial.isEmpty {
                            Text(partial)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("partial")
                        }
                    }
                    .padding(14)
                }
                .onChange(of: partial) { _, _ in
                    withAnimation { proxy.scrollTo("partial") }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ErrorBanner

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(.callout)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }
}

// MARK: - Preview

#Preview {
    ContentViewWrapper()
        .environmentObject(AppSettings())
        .environmentObject(AudioRouterService())
        .frame(width: 780, height: 520)
}
