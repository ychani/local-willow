"""Configuration for local-willow, loaded from config.json next to the project root."""
import json
import os
from dataclasses import dataclass, field

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(PROJECT_ROOT, "config.json")


@dataclass
class Config:
    # Hotkey: hold to record, release to transcribe. Names from pynput.keyboard.Key,
    # e.g. "alt_r" (right option), "cmd_r", "f13".
    hotkey: str = "alt_r"
    model_path: str = os.path.join(PROJECT_ROOT, "models", "ggml-large-v3-turbo-q5_0.bin")
    whisper_bin: str = "whisper-cli"
    language: str = "en"
    sample_rate: int = 16000
    # Words the STT should bias toward (names, jargon) — passed as the whisper prompt.
    vocabulary: list = field(default_factory=list)
    # Literal post-transcription replacements, e.g. {"cloud code": "Claude Code"}.
    replacements: dict = field(default_factory=dict)
    remove_fillers: bool = True
    sounds: bool = True
    # Optional Willow-style "AI mode": rewrite via a local Ollama model. Off unless
    # ollama is running and ai_mode is true.
    ai_mode: bool = False
    ollama_url: str = "http://localhost:11434/api/generate"
    ollama_model: str = "llama3.2:3b"
    max_record_seconds: int = 120


def load() -> Config:
    cfg = Config()
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            data = json.load(f)
        for key, value in data.items():
            if hasattr(cfg, key):
                setattr(cfg, key, value)
    return cfg


def save_default():
    if not os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, "w") as f:
            json.dump({
                "hotkey": "alt_r",
                "language": "en",
                "vocabulary": [],
                "replacements": {},
                "remove_fillers": True,
                "sounds": True,
                "ai_mode": False,
                "ollama_model": "llama3.2:3b",
            }, f, indent=2)
