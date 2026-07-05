# LocalWillow

A private, fully local replica of the [Willow Voice](https://willowvoice.com/) macOS app.
A native menu-bar app: hold a hotkey, speak while a floating waveform pill shows you're live,
release — cleaned-up text lands at your cursor in whatever app is focused.
**No audio or text ever leaves your Mac.**

## The app

`LocalWillow.app` (built from `app/`, pure Swift/AppKit/SwiftUI — no Xcode project needed):

- **Menu bar presence** — mic icon that turns red while recording and shows a waveform while
  transcribing; menu with recent dictations (click to copy), AI-mode toggle, settings, quit.
- **Hold-to-talk hotkey** — default **right ⌥ Option**; right ⌘, right ⌃, or F13 in Settings.
- **Floating pill overlay** — live waveform while recording, "Transcribing…" while processing,
  visible over full-screen apps, click-through.
- **Settings window** — General (hotkey, language, sounds, launch at login, AI mode, model path),
  Permissions (live status + grant buttons, shown automatically on first run), Dictionary
  (vocabulary that biases the STT, and `heard -> replacement` corrections), History (last 20).
- **Engine** — whisper.cpp `large-v3-turbo` (quantized) on Metal, kept warm by a
  `whisper-server` child bound to 127.0.0.1. ~300 ms from key-release to text.
  Orphaned engine processes are reaped automatically.
- **AI mode** — optional rewrite through a local Ollama model (Willow's "AI mode", offline).
- **Insertion** — pasteboard + synthetic ⌘V; your previous clipboard is restored.

## Install / run

```sh
app/build.sh          # rebuild (only needed after code changes)
open LocalWillow.app  # or drag it to /Applications first
```

On first launch the Settings window opens on the **Permissions** tab. Only two grants are
needed (the hotkey uses a CGEventTap, so Input Monitoring is not required):

1. **Microphone** — click Grant, accept the system prompt.
2. **Accessibility** — click Grant, enable LocalWillow in System Settings.

The app detects new grants within ~2 seconds and arms itself automatically — no relaunch
needed. Esc cancels a recording mid-hold. While the Settings window is open the app appears
in the Dock and ⌘-Tab; it returns to menu-bar-only when closed. Engine-related settings
(language, model, vocabulary) are applied when the Settings window closes.

Notes: rebuilding re-signs the app (ad-hoc), so macOS may silently drop Accessibility after
a rebuild — remove the stale entry (−) and re-add it. Diagnostics for every stage are
appended to `~/Library/Logs/LocalWillow.log`.

## Languages

Language is set to `auto`: Whisper detects the language of each dictation independently,
so you can switch between e.g. English and Korean utterance-by-utterance with no toggle.
Set a fixed ISO code (`en`, `ko`, …) in Settings if detection ever misfires on very short
clips. Caveat: vocabulary/glossary entries are injected as an English prompt, which can
bias detection — prefer a fixed language if you rely heavily on vocabulary.

## Dependencies

- `brew install whisper-cpp` (provides `whisper-server` at `/opt/homebrew/bin`)
- A ggml Whisper model in `models/` — `large-v3-turbo-q5_0` is downloaded already; swap via
  Settings → model path with any model from
  [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp/tree/main).
- Optional: [Ollama](https://ollama.com) + `ollama pull llama3.2:3b` for AI mode.

## How it maps to Willow

| Willow (cloud) | LocalWillow (on-device) |
|---|---|
| Menu bar app, global hotkey | Same, native Swift |
| Recording pill overlay | Same, waveform driven by live mic levels |
| Proprietary cloud STT, ~200 ms | whisper.cpp on Metal, ~300 ms, model kept warm |
| Llama-based cleanup/formatting pipeline | Filler removal + dictionary; optional local Ollama rewrite |
| Style memory / context awareness | Vocabulary biasing + corrections dictionary |
| Zero-data-retention *policy* | Zero-data-egress *architecture* (server on 127.0.0.1, temp WAVs deleted) |

## Repo layout

- `app/` — Swift sources, `build.sh`, `Info.plist` → builds `LocalWillow.app`
- `models/` — ggml Whisper models
- `willow/` + `run.sh` — the original Python CLI prototype of the same pipeline (still works
  headless via `./run.sh`; useful for scripting/debugging the engine)
