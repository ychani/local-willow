"""Microphone capture. Records 16 kHz mono int16 WAV files for whisper.cpp."""
import os
import tempfile
import threading
import wave

import numpy as np
import sounddevice as sd


class Recorder:
    def __init__(self, sample_rate: int = 16000, max_seconds: int = 120):
        self.sample_rate = sample_rate
        self.max_seconds = max_seconds
        self._chunks = []
        self._stream = None
        self._lock = threading.Lock()

    def start(self):
        with self._lock:
            if self._stream is not None:
                return
            self._chunks = []
            self._stream = sd.InputStream(
                samplerate=self.sample_rate,
                channels=1,
                dtype="int16",
                callback=self._callback,
            )
            self._stream.start()

    def _callback(self, indata, frames, time_info, status):
        if len(self._chunks) * frames / self.sample_rate < self.max_seconds:
            self._chunks.append(indata.copy())

    def stop(self) -> str | None:
        """Stop recording and return path to a WAV file, or None if too short."""
        with self._lock:
            if self._stream is None:
                return None
            self._stream.stop()
            self._stream.close()
            self._stream = None
            if not self._chunks:
                return None
            audio = np.concatenate(self._chunks)
            self._chunks = []

        # Ignore accidental taps: under ~0.3s of audio is never real dictation.
        if len(audio) < self.sample_rate * 0.3:
            return None

        fd, path = tempfile.mkstemp(suffix=".wav", prefix="willow_")
        os.close(fd)
        with wave.open(path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(self.sample_rate)
            wf.writeframes(audio.tobytes())
        return path
