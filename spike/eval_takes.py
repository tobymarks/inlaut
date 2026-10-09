"""Real-voice evaluation for the English/bilingual model choice (#9, #10).

    .venv/bin/python spike/eval_takes.py record [mic]   # read the sentences aloud, one take each
    .venv/bin/python spike/eval_takes.py score [--diff]  # WER of primeline, v2 and Apple per set

Takes and their reference texts go to spike/takes/eval/ (gitignored, never commit them).
Apple needs: swiftc -O spike/eval_apple.swift -o spike/eval_apple
"""
import json
import re
import subprocess
import sys
import time
import unicodedata
import wave
from collections import defaultdict
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
TAKES = HERE / "takes" / "eval"
MODELS = Path.home() / ".local/share/dictate/models"
SR = 16000

# English as written in everyday work; the German accent is the point.
EN = [
    "Hi Mark, thanks for your feedback on the proposal. I've attached the revised version with the new pricing.",
    "Could we move our call to Thursday afternoon? I'm stuck in a workshop until three.",
    "The product data is imported from the ERP every night and published to the online shop the next morning.",
    "We need to make sure the image rights are stored in the DAM before the assets go into the catalogue.",
    "Please check the API documentation, the endpoint returns a four hundred and four when the SKU is missing.",
    "Our customer wants a digital product passport for every battery they sell in the European Union.",
    "The app runs completely offline, so no audio ever leaves your Mac.",
    "I just pushed a fix for the crash on startup. Could you test it on your machine before we ship the update?",
    "Let's keep the scope small for the first release and add the integrations later.",
    "The meeting notes are in the shared folder, and I've highlighted the open questions in yellow.",
    "Can you give me a rough estimate for the migration? We have about two hundred thousand products and twelve languages.",
    "The weather in Hamburg has been terrible this week, but at least the coffee machine works again.",
    "I'd recommend we start with a proof of concept and decide after the first two sprints.",
    "Thank you for your patience. We have identified the issue and will deploy a fix tomorrow morning.",
    "Kind regards from Germany, and see you at the trade fair in Frankfurt.",
]
# German with English terms, as it is actually spoken at work.
MIX = [
    "Kannst du mir bitte kurz Feedback zum Pitch Deck geben, bevor ich es an den Kunden schicke?",
    "Das Release verschiebt sich, weil der Build auf dem CI Server immer noch rot ist.",
    "Wir sollten das Onboarding vereinfachen, die User brechen im zweiten Step ab.",
    "Im Daily haben wir besprochen, dass das Backend Team den Bug bis Freitag fixt.",
    "Für die Kampagne brauchen wir noch einen Call to Action und ein paar Visuals für Instagram.",
    "Der Shopware Export läuft jetzt stabil, aber das Mapping der Varianten ist noch nicht sauber.",
    "Schick mir bitte den Link zum Dashboard, dann schaue ich mir die Conversion Rate an.",
    "Ich hab das Feature Flag aktiviert, also sollte der neue Checkout jetzt live sein.",
]
# Control: pure German, primeline should stay near zero.
DE = [
    "Vielen Dank für das nette Gespräch heute. Ich melde mich bis Ende der Woche mit einem Angebot.",
    "Die Straße vor unserem Büro ist seit Montag gesperrt, deshalb komme ich etwas später.",
    "Bitte prüfe noch einmal die Rechnung, der Betrag stimmt nicht mit dem Auftrag überein.",
    "Mit freundlichen Grüßen aus Hamburg.",
]
SETS = {"en": EN, "mix": MIX, "de": DE}


def record(device):
    import sounddevice as sd
    TAKES.mkdir(parents=True, exist_ok=True)
    if device and device.isdigit():
        device = int(device)
    print(f"microphone: {sd.query_devices(device, kind='input')['name']}")
    print("Enter starts, Enter stops. After a take: Enter = keep, r = again, s = skip, q = quit.\n")
    items = [(s, i, t) for s, texts in SETS.items() for i, t in enumerate(texts)]
    for n, (s, i, text) in enumerate(items, 1):
        path = TAKES / f"{s}-{i:02d}.wav"
        if path.exists():
            continue
        while True:
            print(f"\n[{n}/{len(items)}] {s.upper()}\n    {text}")
            if input("Enter = record: ").strip().lower() == "q":
                return
            frames = []
            with sd.InputStream(samplerate=SR, channels=1, dtype="int16", device=device,
                                callback=lambda d, *_: frames.append(d.copy())):
                input("  recording … Enter = stop ")
                time.sleep(0.25)
            audio = np.concatenate(frames).squeeze() if frames else np.zeros(0, np.int16)
            if not len(audio) or not np.abs(audio).max():
                print("  only digital silence — grant this terminal microphone access")
                continue
            choice = input(f"  {len(audio) / SR:.1f}s. Enter = keep, r = again, s = skip, q = quit: ").strip().lower()
            if choice == "r":
                continue
            if choice == "q":
                return
            if choice != "s":
                with wave.open(str(path), "wb") as wf:
                    wf.setnchannels(1), wf.setsampwidth(2), wf.setframerate(SR)
                    wf.writeframes(audio.astype(np.int16).tobytes())
                path.with_suffix(".txt").write_text(text)
            break
    print(f"\nDone. Takes in {TAKES}")


def takes():
    return [{"set": p.stem.split("-")[0], "path": str(p), "ref": p.with_suffix(".txt").read_text()}
            for p in sorted(TAKES.glob("*.wav"))]


def run_parakeet(model_dir, items):
    import sherpa_onnx
    rec = sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=str(model_dir / "encoder.int8.onnx"), decoder=str(model_dir / "decoder.int8.onnx"),
        joiner=str(model_dir / "joiner.int8.onnx"), tokens=str(model_dir / "tokens.txt"),
        num_threads=4, model_type="nemo_transducer", decoding_method="greedy_search")
    out = {}
    for it in items:
        with wave.open(it["path"]) as w:
            a = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
        peak = np.abs(a).max()
        if 0 < peak < 0.5:
            a = a * min(0.5 / peak, 30)  # same gain as ParakeetEngine
        s = rec.create_stream()
        s.accept_waveform(SR, a)
        rec.decode_stream(s)
        out[it["path"]] = s.result.text.strip()
    return out


def run_apple(locale, items):
    binary = HERE / "eval_apple"
    if not binary.exists() or not items:
        return None
    lines = "\n".join(it["path"] for it in items) + "\n"
    result = subprocess.run([str(binary), locale], input=lines, capture_output=True, text=True, check=True)
    return {o["path"]: o["text"].strip() for o in map(json.loads, result.stdout.splitlines())}


def norm(s):
    s = unicodedata.normalize("NFC", s).lower().replace("ß", "ss").replace("’", "'")
    s = re.sub(r"[-–/]", " ", s)
    return re.sub(r"[^\w\s']", "", s).replace("'", "").split()


def edits(a, b):
    d = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        p, d[0] = d[0], i
        for j, y in enumerate(b, 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (x != y))
    return d[-1]


def score(show_diff):
    items = takes()
    if not items:
        sys.exit("no takes yet — run: record")
    results = {
        "primeline": run_parakeet(MODELS / "parakeet-primeline-onnx", items),
        "v2": run_parakeet(MODELS / "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8", items),
        "apple-en": run_apple("en-US", [i for i in items if i["set"] == "en"]),
        "apple-de": run_apple("de-DE", [i for i in items if i["set"] != "en"]),
    }
    models = [m for m, r in results.items() if r is not None]
    err = defaultdict(lambda: [0, 0])
    for it in items:
        for m in models:
            if it["path"] in results[m]:
                e = err[(it["set"], m)]
                e[0] += edits(norm(it["ref"]), norm(results[m][it["path"]]))
                e[1] += len(norm(it["ref"]))
    print(f"{'WER %':8}" + "".join(f"{m:>11}" for m in models))
    for s in SETS:
        print(f"{s:8}" + "".join(f"{100 * err[(s, m)][0] / err[(s, m)][1]:>11.1f}" if (s, m) in err else f"{'–':>11}"
                                for m in models))
    if show_diff:
        for it in items:
            for m in models:
                hyp = results[m].get(it["path"])
                if hyp is not None and norm(hyp) != norm(it["ref"]):
                    print(f"\n{Path(it['path']).stem} [{m}]\n  REF {it['ref']}\n  HYP {hyp}")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "record":
        record(sys.argv[2] if len(sys.argv) > 2 else None)
    elif command == "score":
        score("--diff" in sys.argv)
    else:
        sys.exit(__doc__)
