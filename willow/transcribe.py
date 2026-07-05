"""Local speech-to-text via whisper.cpp (Metal-accelerated on Apple Silicon).

Runs a persistent whisper-server on localhost so the model stays loaded in
memory — per-dictation latency is then just decode time, not model load.
"""
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
import uuid


class Transcriber:
    def __init__(self, whisper_bin: str, model_path: str, language: str = "en",
                 vocabulary: list | None = None, port: int = 8178):
        self.model_path = model_path
        self.language = language
        self.vocabulary = vocabulary or []
        self.port = port
        self.server_bin = "whisper-server"
        self._proc = None

    @property
    def _url(self) -> str:
        return f"http://127.0.0.1:{self.port}/inference"

    def start(self):
        """Launch whisper-server (localhost only) and wait for the model to load."""
        cmd = [
            self.server_bin,
            "-m", self.model_path,
            "-l", self.language,
            "--host", "127.0.0.1",
            "--port", str(self.port),
        ]
        if self.vocabulary:
            cmd += ["--prompt", "Glossary: " + ", ".join(self.vocabulary) + ".",
                    "--carry-initial-prompt"]
        self._proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                      stderr=subprocess.DEVNULL)
        deadline = time.time() + 60
        while time.time() < deadline:
            if self._proc.poll() is not None:
                raise RuntimeError(
                    f"whisper-server exited (code {self._proc.returncode}) — "
                    f"check model path: {self.model_path}")
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{self.port}/", timeout=1)
                return
            except urllib.error.HTTPError:
                return  # server responded at all → it's up
            except (urllib.error.URLError, OSError):
                time.sleep(0.25)
        raise RuntimeError("whisper-server did not become ready within 60s")

    def stop(self):
        if self._proc and self._proc.poll() is None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._proc.kill()

    def transcribe(self, wav_path: str) -> str:
        try:
            with open(wav_path, "rb") as f:
                wav = f.read()
        finally:
            try:
                os.unlink(wav_path)
            except OSError:
                pass

        boundary = uuid.uuid4().hex
        parts = []
        for name, value in (("response_format", "json"),
                            ("temperature", "0.0")):
            parts.append(
                f"--{boundary}\r\nContent-Disposition: form-data; "
                f'name="{name}"\r\n\r\n{value}\r\n'.encode())
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; "
            f'name="file"; filename="audio.wav"\r\n'
            f"Content-Type: audio/wav\r\n\r\n".encode() + wav + b"\r\n")
        parts.append(f"--{boundary}--\r\n".encode())
        body = b"".join(parts)

        req = urllib.request.Request(
            self._url, data=body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read())
        if "error" in result:
            raise RuntimeError(f"whisper-server: {result['error']}")
        return result.get("text", "").strip()
