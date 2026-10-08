#!/usr/bin/env python3
"""Install the supplied brand masters into the native app and static website."""
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / "design/inlaut-brand-kit"
ASSETS = ROOT / "Resources/Assets.xcassets"
WEB = ROOT / "site/public"
TOKENS = json.loads((KIT / "design-tokens/colors.json").read_text())


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def color(hex_value):
    rgb = [int(hex_value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return {"color-space": "srgb", "components": dict(zip(
        ("red", "green", "blue", "alpha"), [f"{v:.6f}" for v in rgb] + ["1.000"]))}


for name, key in {
    "Paper": "background", "Surface": "surface", "Ink": "text",
    "Muted": "textSecondary", "Accent": "accent", "OnAccent": "onAccent",
    "Recording": "recording",
}.items():
    write_json(ASSETS / f"Inlaut{name}.colorset/Contents.json", {
        "colors": [
            {"idiom": "universal", "color": color(TOKENS["light"][key])},
            {"idiom": "universal", "color": color(TOKENS["dark"][key]),
             "appearances": [{"appearance": "luminosity", "value": "dark"}]},
        ], "info": {"author": "xcode", "version": 1},
    })

# Derived separators, kept in the same petrol family as the source palette.
for name, light, dark in [("Border", "#D7E2DC", "#35514B"),
                          ("Brand", TOKENS["brand"]["petrol"], TOKENS["brand"]["mint"])]:
    write_json(ASSETS / f"Inlaut{name}.colorset/Contents.json", {
        "colors": [
            {"idiom": "universal", "color": color(light)},
            {"idiom": "universal", "color": color(dark),
             "appearances": [{"appearance": "luminosity", "value": "dark"}]},
        ], "info": {"author": "xcode", "version": 1},
    })


def template(name, svg):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(exist_ok=True)
    (folder / f"{name}.svg").write_text(svg)
    write_json(folder / "Contents.json", {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True,
                       "template-rendering-intent": "template"},
    })


template("InlautWordmark", (KIT / "logo/inlaut-logo-black.svg").read_text())
template("InlautSymbol", (KIT / "logo/inlaut-symbol-black.svg").read_text())
menu = (KIT / "menu-bar/inlaut-template.svg").read_text()
template("menubar-ready", menu)
# Preserve the ready glyph at its supplied size; badges add a non-colour status cue.
badges = {
    "preparing": '<circle cx="23" cy="9" r="2" fill="none" stroke="black" stroke-width="1.3"/>',
    "recording": '<circle cx="23" cy="9" r="2.5" fill="black"/>',
    "transcribing": '<path d="m21 7 2 2-2 2m3-4 2 2-2 2" fill="none" stroke="black" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>',
    "failed": '<path d="M23 5v5" stroke="black" stroke-width="1.8" stroke-linecap="round"/><circle cx="23" cy="13" r="1" fill="black"/>',
}
for state, badge in badges.items():
    svg = menu.replace('width="18"', 'width="28"').replace('viewBox="0 0 18 18"', 'viewBox="0 0 28 18"')
    template(f"menubar-{state}", svg.replace("</svg>", badge + "</svg>"))

# Retain the project's native Icon Composer document and use the new unmasked master.
icon_dir = ROOT / "Resources/Inlaut.icon"
outline = subprocess.run([
    "swift", str(ROOT / "scripts/outline-brand.swift"),
    str(KIT / "icon-composer/foreground-mint.svg"),
], check=True, capture_output=True, text=True)
(icon_dir / "Assets/impulse.svg").write_text(outline.stdout)


def solid(hex_value):
    rgb = [int(hex_value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return {"solid": "srgb:" + ",".join(f"{v:.5f}" for v in rgb) + ",1.00000"}


write_json(icon_dir / "icon.json", {
    "fill-specializations": [
        {"value": solid(TOKENS["brand"]["petrol"])},
        {"appearance": "dark", "value": solid(TOKENS["dark"]["background"])},
        {"appearance": "tinted", "value": solid("#808080")},
    ],
    "groups": [{
        "layers": [{
            "fill-specializations": [
                {"value": solid(TOKENS["brand"]["mint"])},
                {"appearance": "tinted", "value": solid("#FFFFFF")},
            ],
            "glass": True, "image-name": "impulse.svg", "name": "Sprachimpuls",
            "position": {"scale": 1, "translation-in-points": [0, 0]},
        }],
        "shadow": {"kind": "neutral", "opacity": 0.4},
        "translucency": {"enabled": True, "value": 0.5},
    }],
    "supported-platforms": {"squares": ["macOS"]},
})

for asset in (KIT / "web").iterdir():
    shutil.copy2(asset, WEB / asset.name)
# Keep the old touch-icon URL working for previously cached HTML.
shutil.copy2(KIT / "web/icon-180.png", WEB / "apple-touch-icon-180.png")
(WEB / "brand").mkdir(exist_ok=True)
for name in ["inlaut-logo-petrol.svg", "inlaut-logo-mint.svg", "inlaut-symbol-petrol.svg", "inlaut-symbol-mint.svg"]:
    shutil.copy2(KIT / "logo" / name, WEB / "brand" / name)
shutil.copy2(KIT / "app-icon/inlaut-512.png", WEB / "brand/app-icon.png")
print("Brand assets synced from design/inlaut-brand-kit.")
