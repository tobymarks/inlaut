#!/usr/bin/env python3
"""Validate a release DMG's payload, installation target and Finder layout."""
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import sys

from ds_store import DSStore


def run(*args):
    return subprocess.check_output(args)


def manifest(root):
    """Include files and symlinks without following framework links."""
    result = {}
    for directory, folders, files in os.walk(root):
        for name in folders + files:
            path = Path(directory) / name
            relative = str(path.relative_to(root))
            if path.is_symlink():
                result[relative] = ("link", os.readlink(path))
            elif path.is_file():
                result[relative] = ("file", hashlib.sha256(path.read_bytes()).hexdigest())
    return result


def validate(image, source_app, folder="Programme"):
    run("hdiutil", "verify", str(image))
    attached = plistlib.loads(run("hdiutil", "attach", "-readonly", "-nobrowse",
                                 "-noautoopen", "-plist", str(image)))
    entities = attached["system-entities"]
    device = entities[0]["dev-entry"]
    try:
        mounts = [Path(e["mount-point"]) for e in entities if "mount-point" in e]
        assert len(mounts) == 1, "Expected one mounted volume"
        volume = mounts[0]
        assert {p.name for p in volume.iterdir() if not p.name.startswith(".")} == {
            "Inlaut.app", folder
        }, "Unexpected visible disk image contents"
        assert (volume / folder).is_symlink(), "Installation target is not a link"
        assert os.readlink(volume / folder) == "/Applications", "Wrong installation target"
        app = volume / "Inlaut.app"
        assert manifest(app) == manifest(source_app), "DMG payload differs from the exported app"
        run("codesign", "--verify", "--deep", "--strict", str(app))
        run("xcrun", "stapler", "validate", str(app))
        run("spctl", "--assess", "--type", "execute", "--verbose=2", str(app))
        with DSStore.open(str(volume / ".DS_Store"), "r") as store:
            assert store["."]["icvl"] == (b"type", b"icnv"), "Default Finder view is not icon view"
            view = store["."]["icvp"]
            assert view["backgroundType"] == 2 and view["backgroundImageAlias"], "Missing background"
            assert view["arrangeBy"] == "none" and view["gridSpacing"] < 100, "Invalid icon arrangement"
            assert store["Inlaut.app"]["Iloc"] == (176, 252), "Wrong app position"
            assert store[folder]["Iloc"] == (484, 252), "Wrong folder position"
            window = store["."]["bwsp"]
            assert window["WindowBounds"] == "{{200, 180}, {660, 462}}", "Wrong window bounds"
            assert not window["ShowToolbar"] and not window["ShowSidebar"], "Unexpected Finder chrome"
        assert (volume / ".background.tiff").is_file(), "Missing Retina installer artwork"
        print("DMG verified: identical notarized app, /Applications target, artwork and Finder layout.")
    finally:
        subprocess.run(["hdiutil", "detach", device], check=True)


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit("Usage: validate-dmg.py IMAGE.dmg SOURCE.app [FOLDER]")
    validate(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), *sys.argv[3:])
