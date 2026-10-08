"""Spike: does parakeet-primeline (German, int8, sherpa-onnx) recognise my speech well enough?

    .venv/bin/python spike/try_parakeet.py            # record from the mic, Enter stops, repeat
    .venv/bin/python spike/try_parakeet.py file.wav   # transcribe a 16 kHz mono WAV

Reuses local_stt.py from ~/Developer/dictate (MIT) for model loading and decoding.
"""
import resource
import sys
import time
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path.home() / "Developer" / "dictate"))
import local_stt  # noqa: E402

SR = local_stt.TARGET_SR


def rss_mb():
    # ru_maxrss is in bytes on macOS
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e6


def load(threads):
    t = time.monotonic()
    rec = local_stt.get_recognizer(num_threads=threads)
    rec.wait_ready()
    if not rec.is_ready():
        sys.exit(f"model failed to load: {rec._load_error}")
    print(f"model loaded in {time.monotonic() - t:.1f}s, peak RSS {rss_mb():.0f} MB, {threads} threads")
    return rec


def run(rec, audio):
    secs = len(audio) / SR
    t = time.monotonic()
    text = rec.transcribe(audio)
    dt = time.monotonic() - t
    print(f"\n[{secs:.1f}s audio, decoded in {dt * 1000:.0f} ms, peak RSS {rss_mb():.0f} MB]")
    print(text or "(nothing recognised)")


def read_wav(path):
    with wave.open(path, "rb") as wf:
        if wf.getframerate() != SR or wf.getnchannels() != 1 or wf.getsampwidth() != 2:
            sys.exit("need 16 kHz mono 16-bit WAV")
        return np.frombuffer(wf.readframes(wf.getnframes()), dtype=np.int16)


def record(device=None):
    import sounddevice as sd
    frames = []
    with sd.InputStream(samplerate=SR, channels=1, dtype="int16", device=device,
                        callback=lambda d, n, t, s: frames.append(d.copy())):
        input("Recording... speak, then press Enter. ")
        time.sleep(0.25)  # keep the last syllable
    return np.concatenate(frames).squeeze() if frames else np.zeros(0, np.int16)


def main():
    if not local_stt.model_installed():
        sys.exit(f"model missing in {local_stt.MODEL_DIR}")
    rec = load(threads=4)
    if len(sys.argv) > 1:
        run(rec, read_wav(sys.argv[1]))
        return
    import sounddevice as sd
    print(f"microphone: {sd.query_devices(kind='input')['name']}")
    while True:
        if input("\nEnter = record, q + Enter = quit: ").strip().lower() == "q":
            break
        run(rec, record())


if __name__ == "__main__":
    main()
