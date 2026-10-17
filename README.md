# LocalFlow

A lightweight, 100% offline, native macOS voice dictation app inspired by Wispr Flow with personal style learning and zero-UI headless support.

## Key Capabilities

- **On-Device Speech-to-Text**: Built on macOS `SFSpeechRecognizer` running directly on Apple Neural Engine (ANE). 100% private and offline.
- **Personalized AI Autocorrect**: Connects to local [Ollama](http://localhost:11434) (`qwen2.5-coder:1.5b` or `llama3.2:1b`) to remove filler words (*"um"*, *"uh"*, *"like"*), fix punctuation, and format numbers/dates.
- **Personal Dictionary**: Add custom names, jargon, or acronyms to `config.json` so the AI always uses your preferred spellings.
- **Custom Tags Expansion**: Define tags (like `:email`, `:standup`, `:gh`) that automatically expand into full phrases.
- **Personal Writing Style Learning**:
  - Add your writing/chat samples to `~/.config/localflow/my_style.txt` so the AI matches your natural voice.
  - Automatically records dictation history in a local SQLite database (`~/.config/localflow/history.db`).
- **Zero-UI Headless Mode**: Toggle headless mode to hide the floating pill and rely purely on subtle audio cues (*Tink* on start, *Pop* on end).
- **Global Control Shortcut**:
  - Press **Control twice** (`Ctrl Ctrl` within 400ms) to **start** dictating.
  - Press **Control once** (`Ctrl`) while recording to **stop and paste**.

---

## Configuration (`~/.config/localflow/config.json`)

The config file is automatically created on first launch with live file watching (edits take effect immediately):

```json
{
  "double_tap_threshold_ms": 400,
  "headless": false,
  "llm_model": "qwen2.5-coder:1.5b",
  "personal_dictionary": [
    "LocalFlow",
    "Wispr",
    "Kubernetes",
    "GraphQL",
    "Ollama"
  ],
  "sound_effects": true,
  "style_instructions": "Natural, direct, and conversational. Keep my personal tone, avoid unnecessary corporate filler, and format lists or numbers cleanly.",
  "tags": {
    ":email": "my.email@domain.com",
    ":standup": "Today I am focusing on"
  }
}
```

---

## How to Run

1. Ensure Ollama is running in your terminal:
   ```bash
   ollama run qwen2.5-coder:1.5b
   ```

2. Launch `LocalFlow.app`:
   ```bash
   open "/Applications/LocalFlow.app"
   ```

3. A microphone icon will appear in your macOS Menu Bar.
4. From the menu bar, you can click **"Open Config Folder"** to edit your dictionary or style samples anytime.
5. In any app, press **`Ctrl Ctrl`**, speak, and press **`Ctrl`** once to paste your polished words!

## Rebuilding

To recompile and package:
```bash
./package.sh
```
