# RealLocalTrans

**RealLocalTrans** is a macOS app that provides real-time, bidirectional speech translation with support for routing the original and translated audio to _separate_ output devices — perfect for two-person conversations using a pair of AirPods each, or any two audio output devices.

---

## Features

| Capability | Apple (local) | LLM / API |
|---|---|---|
| **Speech-to-Text (STT)** | Apple `Speech` framework | OpenAI Whisper API |
| **Translation** | Apple `Translation` framework (macOS 15+) | OpenAI Chat Completions API |
| **Text-to-Speech (TTS)** | `AVSpeechSynthesizer` | OpenAI TTS API |

- **Dual audio output** – route the source-language TTS to Output A and the translated TTS to Output B (e.g. two pairs of AirPods)
- **Any microphone input** – pick the input device in Settings
- **13 supported languages** out of the box (English, Chinese Simplified/Traditional, Japanese, Korean, Spanish, French, German, Portuguese, Arabic, Hindi, Russian, Italian)
- **Persistent settings** – all preferences are saved in `UserDefaults` and survive restarts
- **macOS sandbox-compatible** – ships with a `.entitlements` file for App Store distribution

---

## Requirements

| Component | Version |
|---|---|
| macOS | 14 Sonoma or later (15 Sequoia for Apple local translation) |
| Xcode | 15 or later |
| Swift | 5.9 or later |

For LLM features, you need an **OpenAI-compatible API key** (OpenAI, Azure OpenAI, Ollama, LM Studio, etc.).

---

## Building

1. Open `RealLocalTrans.xcodeproj` in Xcode.
2. Select your development team in *Signing & Capabilities*.
3. Choose **My Mac** as the run destination.
4. Press ⌘R.

---

## Usage

### 1. Configure settings (⌘,)

**Languages tab**
- Set **Source Language** — the language you will _speak_.
- Set **Target Language** — the language you want to hear as output.

**Providers tab**
- Choose between Apple local or LLM for each of STT, Translation, and TTS.
- If using Apple local TTS, pick a voice for each language.

**Audio tab**
- **Input device** — the microphone to capture your voice.
- **Output A** — plays back the _source_ language TTS (the speaker's own language).
- **Output B** — plays back the _translated_ language TTS (the listener's language).

> **AirPods example:** Connect two pairs of AirPods. Assign one to Output A and one to Output B. Person A wears Output A AirPods (hears themselves in English), Person B wears Output B AirPods (hears the Chinese translation).

**LLM / API tab**
- Enter your API base URL and key.
- Adjust model names if using a different provider.

### 2. Start translation

Press the **Start** button in the main window. The app begins listening on the selected input device. Whenever a sentence is recognised:

1. The transcript appears in the **left panel** (source language).
2. The text is translated and appears in the **right panel** (target language).
3. The source audio plays on Output A; the translated audio plays on Output B.

Press **Stop** to end the session.

---

## Architecture

```
RealLocalTrans/
├── RealLocalTransApp.swift        # @main SwiftUI app
├── ContentView.swift              # Live translation window
├── SettingsView.swift             # Settings sheet (4 tabs)
├── Models/
│   ├── AppSettings.swift          # Observable settings + UserDefaults persistence
│   └── AudioDevice.swift          # CoreAudio device model
└── Services/
    ├── AudioRouterService.swift    # CoreAudio device enumeration & routing
    ├── SpeechRecognitionService.swift  # STT – Apple Speech / LLM Whisper
    ├── TranslationService.swift    # Translation – Apple Translation / LLM chat
    ├── SpeechSynthesisService.swift    # TTS – AVSpeechSynthesizer / LLM TTS
    └── LLMService.swift            # OpenAI-compatible HTTP client
```

---

## Privacy

The app requests the following permissions:
- **Microphone** – to capture speech
- **Speech Recognition** – for Apple on-device STT
- **Network (outbound)** – only when an LLM provider is selected

When using Apple local providers, **no audio or text ever leaves your Mac**.

---

## License

MIT
