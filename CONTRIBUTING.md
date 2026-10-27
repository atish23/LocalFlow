# Contributing to LocalFlow

Thank you for your interest in contributing to LocalFlow. LocalFlow is an on-device, offline macOS voice dictation application that respects user privacy and runs with zero cloud subscriptions.

---

## 1. Development Prerequisites

- **Operating System**: macOS 13.0 (Ventura) or later (Apple Silicon recommended for Neural Engine performance)
- **Toolchain**: Xcode 15+ or Swift 5.9+ Command Line Tools (`xcode-select --install`)
- **Local LLM**: [Ollama](https://ollama.ai) installed and running locally
  ```bash
  ollama run qwen2.5-coder:1.5b
  ```

---

## 2. Project Architecture

LocalFlow is organized as a modular Swift Package:

- **`Sources/LocalFlowCore`**: Core business logic and reusable modules:
  - `Audio/`: Speech recognition via Apple Neural Engine (`SpeechManager`), audio device discovery (`AudioDeviceManager`), sound feedback (`SoundFeedback`), trackpad haptics (`HapticFeedback`).
  - `Hotkey/`: Global event monitoring with both Push-to-Talk (Hold-to-Talk) and Double-Tap Toggle modes (`HotkeyManager`).
  - `Processing/`: Deterministic regex polisher, phonetic substitutions, filler word removal, currency and number formatting, and app-aware styling (`TextPolisher`).
  - `LLM/`: High-speed local Ollama client with timeout fallback and connection health checks (`OllamaClient`).
  - `Paster/`: Accessibility-backed HID keystroke injection via `CGEvent` (`TextPaster`).
  - `Storage/`: Local SQLite store for vocabulary, corrections, and dictation history (`CorrectionStore`).
  - `UI/`: Real-time RMS audio waveform floating HUD (`FloatingPill`) and comprehensive preferences window (`SettingsWindow`).
- **`Sources/LocalFlow`**: Application entry point and menu bar lifecycle (`main.swift`).
- **`Tests/LocalFlowTests`**: Comprehensive unit tests for text processing, SQLite storage, configuration, and device discovery.

---

## 3. Building and Running Locally

### Run Unit Tests
```bash
swift test
```

### Build in Release Mode
```bash
swift build -c release
```

### Package Application Bundle
```bash
./package.sh
```

### Create Release DMG
```bash
./package.sh --dmg
# Output artifact is placed at build/LocalFlow-1.0.0.dmg
```

### Deploy to /Applications (with persistent code signing)
```bash
./deploy.sh
```

---

## 4. Code Style & Contribution Guidelines

1. **Typography Policy**: NEVER use em-dashes or en-dashes in code, comments, commit messages, or documentation. Use standard hyphens, commas, colons, or parentheses instead.
2. **Deterministic Fallbacks**: Speech processing must never fail or block the user interface. If Ollama is unavailable or slow (>2.5s), the system must immediately fall back to deterministic regex output.
3. **No Unsound Test Weakening**: Never weaken, disable, or delete existing tests to make new changes pass. Add tests for new edge cases and features.
4. **App Privacy & Permissions**: Keep all dictation processing 100% on-device. Never introduce cloud tracking or external network dependencies.

---

## 5. Submitting Pull Requests

1. Fork the repository and create your feature branch from `main`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. Commit your changes with clear, descriptive commit messages:
   ```bash
   git commit -m "feat(audio): add support for custom haptic feedback patterns"
   ```
3. Verify that all tests pass:
   ```bash
   swift test
   ```
4. Push to your branch and open a Pull Request against `main`.
