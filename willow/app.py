"""local-willow: hold a hotkey, speak, release — text appears at your cursor.

Everything runs on-device: whisper.cpp for speech-to-text, optional Ollama for
AI cleanup. No audio or text ever leaves this machine.
"""
import subprocess
import sys
import threading

from pynput import keyboard

from . import config
from .formatter import Formatter
from .inject import insert_text
from .recorder import Recorder
from .transcribe import Transcriber

SOUND_START = "/System/Library/Sounds/Pop.aiff"
SOUND_DONE = "/System/Library/Sounds/Purr.aiff"


def _play(path: str):
    subprocess.Popen(["afplay", path], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)


def _notify(message: str, title: str = "local-willow"):
    subprocess.run([
        "osascript", "-e",
        f'display notification "{message}" with title "{title}"',
    ], capture_output=True, timeout=5)


def _resolve_key(name: str):
    if hasattr(keyboard.Key, name):
        return getattr(keyboard.Key, name)
    if len(name) == 1:
        return keyboard.KeyCode.from_char(name)
    raise ValueError(f"Unknown hotkey '{name}' — use a pynput key name like alt_r, cmd_r, f13")


class App:
    def __init__(self, cfg: config.Config):
        self.cfg = cfg
        self.hotkey = _resolve_key(cfg.hotkey)
        self.recorder = Recorder(cfg.sample_rate, cfg.max_record_seconds)
        self.transcriber = Transcriber(cfg.whisper_bin, cfg.model_path,
                                       cfg.language, cfg.vocabulary)
        self.formatter = Formatter(cfg)
        self.recording = False
        self.busy = False

    def on_press(self, key):
        if key == self.hotkey and not self.recording and not self.busy:
            self.recording = True
            if self.cfg.sounds:
                _play(SOUND_START)
            self.recorder.start()
            print("● recording...", flush=True)

    def on_release(self, key):
        if key == self.hotkey and self.recording:
            self.recording = False
            wav = self.recorder.stop()
            if wav is None:
                print("  (too short, ignored)", flush=True)
                return
            # Transcribe off the listener thread so the hotkey stays responsive.
            threading.Thread(target=self._process, args=(wav,), daemon=True).start()

    def _process(self, wav: str):
        self.busy = True
        try:
            raw = self.transcriber.transcribe(wav)
            text = self.formatter.format(raw)
            if text:
                insert_text(text)
                if self.cfg.sounds:
                    _play(SOUND_DONE)
                print(f"  → {text}", flush=True)
            else:
                print("  (no speech detected)", flush=True)
        except Exception as e:
            print(f"  ! error: {e}", file=sys.stderr, flush=True)
            _notify(str(e)[:120], "local-willow error")
        finally:
            self.busy = False

    def run(self):
        print("loading model into memory...", flush=True)
        self.transcriber.start()
        mode = "AI mode (Ollama)" if self.cfg.ai_mode else "standard cleanup"
        print(f"local-willow ready — hold [{self.cfg.hotkey}] to dictate, "
              f"release to insert. Formatting: {mode}. Ctrl+C to quit.", flush=True)
        try:
            with keyboard.Listener(on_press=self.on_press,
                                   on_release=self.on_release) as listener:
                listener.join()
        finally:
            self.transcriber.stop()


def main():
    config.save_default()
    cfg = config.load()
    try:
        App(cfg).run()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
