"""Spike: primeline/whisper-large-v3-turbo-german, MLX f16 port, on Apple Silicon GPU.

    .venv/bin/python spike/try_whisper.py file.wav   # 16 kHz mono 16-bit WAV
"""
import sys
import time
from pathlib import Path

import numpy as np

MODEL_DIR = Path.home() / ".local" / "share" / "dictate" / "models" / "whisper-turbo-german-mlx"
SR = 16000


class Whisper:
    def __init__(self):
        import mlx.core as mx
        import mlx_whisper
        self.mx, self.mlx_whisper = mx, mlx_whisper
        if not (MODEL_DIR / "weights.npz").exists():
            sys.exit(f"model missing in {MODEL_DIR}")
        t = time.monotonic()
        self._transcribe(np.zeros(SR, dtype=np.float32))  # loads the model and warms up Metal kernels
        print(f"whisper loaded in {time.monotonic() - t:.1f}s")

    def _transcribe(self, audio):
        return self.mlx_whisper.transcribe(
            audio,
            path_or_hf_repo=str(MODEL_DIR),
            language="de",
            # Whisper otherwise likes to repeat or invent text after a pause.
            condition_on_previous_text=False,
            verbose=None,
        )["text"].strip()

    def run(self, audio):
        """int16 mono 16 kHz in, prints text and timing."""
        if audio.dtype != np.float32:
            audio = audio.astype(np.float32) / 32768.0
        self.mx.reset_peak_memory()
        t = time.monotonic()
        text = self._transcribe(audio.squeeze())
        dt = time.monotonic() - t
        print(f"[{len(audio) / SR:.1f}s audio, decoded in {dt * 1000:.0f} ms, "
              f"peak GPU memory {self.mx.get_peak_memory() / 1e6:.0f} MB]")
        print(text or "(nothing recognised)")


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).parent))
    from try_parakeet import read_wav
    Whisper().run(read_wav(sys.argv[1]))
