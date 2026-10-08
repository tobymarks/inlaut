"""One recording from the mic, transcribed by Parakeet (sherpa-onnx), Whisper turbo German (MLX)
and Apple SpeechAnalyzer.

    .venv/bin/python spike/compare.py [mic number or name part, e.g. 2 or MacBook]

Enter starts a take, Enter stops it, q quits. Takes are saved in spike/takes/
so a bad result can be replayed: spike/try_apple spike/takes/<file>.wav
"""
import subprocess
import sys
import time
import wave
from pathlib import Path

import numpy as np

import try_parakeet as tp
from try_whisper import Whisper

HERE = Path(__file__).parent
APPLE = HERE / "try_apple"
TAKES = HERE / "takes"


def save(audio):
    TAKES.mkdir(exist_ok=True)
    path = TAKES / time.strftime("%Y%m%d-%H%M%S.wav")
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(tp.SR)
        wf.writeframes(audio.astype(np.int16).tobytes())
    return path


def main():
    if not APPLE.exists():
        sys.exit(f"build it first: swiftc -O {HERE}/try_apple.swift -o {APPLE}")
    rec = tp.load(threads=2)
    whisper = Whisper()
    import sounddevice as sd
    device = sys.argv[1] if len(sys.argv) > 1 else None
    if device and device.isdigit():
        device = int(device)
    mics = ", ".join(f"{i} {d['name']}" for i, d in enumerate(sd.query_devices()) if d["max_input_channels"])
    print(f"microphone: {sd.query_devices(device, kind='input')['name']}  (available: {mics})")
    while True:
        if input("\nEnter = record, q + Enter = quit: ").strip().lower() == "q":
            break
        audio = tp.record(device)
        if not len(audio) or not np.abs(audio).max():
            # macOS hands out pure zeros instead of an error when the app
            # running this script has no microphone permission.
            print("only digital silence — grant this terminal app access in System Settings → "
                  "Privacy & Security → Microphone, then restart it")
            continue
        path = save(audio)
        print("\n--- Parakeet (primeline, sherpa-onnx) ---", end="")
        tp.run(rec, audio)
        print("\n--- Whisper large-v3-turbo German (MLX, GPU) ---")
        whisper.run(audio)
        print("\n--- Apple SpeechAnalyzer ---")
        out = subprocess.run([str(APPLE), str(path)], capture_output=True, text=True)
        print("\n".join(l for l in out.stdout.splitlines() if not l.startswith("de-DE")) or out.stderr)


if __name__ == "__main__":
    main()
