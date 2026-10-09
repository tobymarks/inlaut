#!/usr/bin/env python3
"""Compare the strings the compiler extracted with Resources/Localizable.xcstrings.

    xcodebuild -project Inlaut.xcodeproj -scheme Inlaut -configuration Debug -derivedDataPath build build
    python3 scripts/check-localizations.py

Lists source strings without a German translation and catalog entries no
longer used. Building in the Xcode app adds new keys to the catalog by
itself; xcodebuild does not, so new strings need a German entry by hand.
"""
import glob
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
objects = ROOT / "build/Build/Intermediates.noindex/Inlaut.build/Debug/Inlaut.build/Objects-normal/arm64"
files = glob.glob(str(objects / "*.stringsdata"))
if not files:
    sys.exit("no .stringsdata found — build the Debug app first")
extracted = {e["key"] for f in files for entries in json.load(open(f)).get("tables", {}).values() for e in entries}
catalog = json.load(open(ROOT / "Resources/Localizable.xcstrings"))["strings"]

missing = sorted(k for k in extracted
                 if catalog.get(k, {}).get("shouldTranslate") is not False
                 and "de" not in catalog.get(k, {}).get("localizations", {}))
stale = sorted(set(catalog) - extracted)
for key in missing:
    print(f"missing German: {key!r}")
for key in stale:
    print(f"unused in source: {key!r}")
sys.exit(1 if missing else 0)
