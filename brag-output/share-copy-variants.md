# Share Copy Variants: LocalFlow

## Twitter / X (Punchy & Direct)
Tired of paying $15/mo for voice dictation tools to stream your confidential audio to the cloud?

I built LocalFlow: a 100% offline macOS voice dictation app.
• Built on Apple Neural Engine (ANE)
• Sub-500ms grammar cleanup with local Ollama
• Push-to-Talk & double-tap modes
• Zero subscriptions. Zero cloud lag.

100% free and open-source on GitHub: github.com/atish23/LocalFlow

---

## LinkedIn (Builder & Engineering Story)
Why send your voice to cloud servers when Apple Silicon has a dedicated Neural Engine sitting right on your desk?

Today I am open-sourcing LocalFlow, an on-device native macOS voice dictation app designed for privacy-conscious developers and builders.

Instead of paying recurring cloud subscriptions:
1. Speech-to-Text runs locally on Apple Silicon (sub-50ms latency).
2. Local Ollama (Qwen 2.5 Coder 1.5B) handles grammar, punctuation, and loop deduplication in under 500ms.
3. Audio waveforms, trackpad haptics, and custom developer vocabulary make it feel native to macOS.

Check out the code, release DMG, and architecture on GitHub:
https://github.com/atish23/LocalFlow

---

## Discord / Hacker News (Technical Summary)
Show HN: LocalFlow - 100% offline, on-device voice dictation for macOS

LocalFlow replaces cloud dictation tools (like Wispr Flow) with a local pipeline:
- SFSpeechRecognizer executing on Apple Neural Engine
- Local Ollama fallback for grammar and deduplication
- Push-to-Talk (Hold-to-speak) + Double-tap toggle
- Native AppKit/SwiftUI settings window with custom vocabulary store
- Zero telemetry, zero subscriptions, MIT license.

Repo: https://github.com/atish23/LocalFlow
