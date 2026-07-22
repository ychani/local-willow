# LocalWillow for Windows

The Windows port of LocalWillow: hold a hotkey, speak while a floating waveform
pill shows you're live, release — cleaned-up text lands at your cursor in
whatever app is focused. **No audio or text ever leaves your PC.** No admin
rights, no installer, no system permissions needed — it's a portable folder.

Same architecture as the Mac app: a tray app drives a local `whisper-server`
(whisper.cpp) child on `127.0.0.1:8178`, keeps the model warm, and pastes the
transcript via clipboard + synthetic Ctrl+V (your previous clipboard is restored).

## Install

**Option A — download a build** (no toolchain needed):

1. Grab `LocalWillow-windows-x64-win-v<version>.zip` from the repo's GitHub
   Releases (or the latest `windows-build` workflow artifact under Actions).
2. Unzip anywhere (e.g. `C:\Tools\LocalWillow`).
3. In that folder run: `powershell -ExecutionPolicy Bypass -File setup.ps1`
   — downloads the whisper.cpp engine (~10 MB) and the model (~547 MB).
   Have an NVIDIA GPU? Add `-Cuda` for much faster transcription.
   Slow CPU-only machine? Add `-Model small` (or `base`) for a lighter model.
4. Start `LocalWillow.exe`. A waveform icon appears in the tray.

**Option B — build from the repo**:

```powershell
winget install Microsoft.DotNet.SDK.8
git clone https://github.com/ychani/local-willow.git
cd local-willow\windows
powershell -ExecutionPolicy Bypass -File build.ps1     # → dist\LocalWillow.exe
powershell -ExecutionPolicy Bypass -File dist\setup.ps1
dist\LocalWillow.exe
```

## Use

- **Hold Right Alt** (default), speak, release → text is typed at your cursor.
  Toggle mode (press to start / press to stop) is available in Settings.
- **Esc** cancels a recording mid-take.
- Tray menu: recent dictations (click to copy), AI mode, transcribe an audio
  file to a `.txt`, Settings, Quit.
- Language is `auto` by default: each dictation's language is detected
  independently, so you can switch English ↔ Korean utterance-by-utterance.

Korean keyboards: the physical Right Alt key is 한/영, which Windows reports as
`VK_HANGUL` — LocalWillow treats it as the same hotkey, but since the keypress
still reaches the IME it will also toggle 한/영. If that's annoying, switch the
hotkey to Right Ctrl (한자 key) or F13 in Settings.

## Files

Everything lives next to the exe (`engine\`, `models\`) or in
`%APPDATA%\LocalWillow` (`config.json`, `history.json`, `LocalWillow.log`).
Uninstall = delete the folder.

## AI mode

Optional rewrite pass through a local [Ollama](https://ollama.com) model
(`llama3.2:3b` by default), same as the Mac app. Fully offline. Enable in the
tray menu once Ollama is running.

## Troubleshooting

- **First dictation after starting the app takes a while**: the 547 MB model is
  loading into RAM. The pill shows "Loading model…" during this; subsequent
  dictations are fast because the model stays warm.
- **Failures show in the pill** (red text) as well as a notification, and full
  diagnostics land in `%APPDATA%\LocalWillow\LocalWillow.log` plus the raw
  whisper-server output in `engine.log` (tray menu → *Open Log Folder*).
- **Slow transcription on CPU**: setup installs the BLAS-accelerated engine by
  default; if dictation still feels slow, rerun `setup.ps1 -Model small` and
  point Settings → Whisper model at the new file, or `setup.ps1 -Cuda` on a
  machine with an NVIDIA GPU.

## Notes

- Windows "N" editions need the Media Feature Pack for the *Transcribe Audio
  File* feature (Media Foundation); live dictation works without it.
- The whisper-server child is placed in a kill-on-close job object, so it can
  never outlive the app — even if LocalWillow crashes.
- Some hardened work environments flag low-level keyboard hooks (that's how the
  global hotkey works — listen-only, events are never suppressed). If corporate
  AV complains, building from source (Option B) usually satisfies IT.
