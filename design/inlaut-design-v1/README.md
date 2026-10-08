# Inlaut design v1 · Setzpunkt

Richtung A, ausgearbeitet am 8. Oktober 2026. Enthalten sind eigenständig konstruierte Logo- und Symbolpfade, drei unmaskierte Icon-Composer-Ebenen, sechs flache Icon-Vorschauen, Raster-Fallbacks, fünf Menüleisten-Zustände, Web-/Distributionsbilder und Farb-Tokens. `checks/contact-sheet.png` zeigt kleine Rastergrößen auf hellen und dunklen Flächen.

## Dateien und Verwendung

- `app-icon/layers/`: ausschließlich diese Artwork-Ebenen für Icon Composer nutzen. Reihenfolge und Farb-Overrides in `layers.md`.
- `app-icon/preview/`: Ansichtsdateien; Clear/Tinted sind illustrative flache Varianten, keine echten System-Renderings.
- `app-icon/flat/`: maskierte Fallbacks für README, Web und eine spätere `.icns`-Erstellung.
- `menubar/`: schwarze Template-Pfade, 18 × 18 pt; PNGs in 18 und 36 px. Die Vorschau zeigt die vom System simulierte weiße Färbung.
- `logo/`: frei gezeichnete Wortmarke, Symbol und horizontale Kombination in Farbe, Schwarz, Weiß; PNGs mit 512 und 2048 px Breite.
- `web/`: SVG-Favicon, echtes ICO mit 16/32/48 px, Touch-Icon und Social-Bilder.
- `distribution/`: DMG-Flächen mit freien Iconzentren (170,200) und (490,200) pt sowie README-Header.
- `tokens/`: semantische Farben und SwiftUI-Extension; die benannten Color Sets werden wie unten angelegt.

## Einbau in Xcode

### App-Icon

1. Icon Composer öffnen, macOS und 1024 × 1024 wählen. Hintergrundfarbe und die beiden Vordergrunddateien entsprechend `layers/layers.md` anlegen.
2. Default, Dark und Mono einstellen und alle sechs Appearance-Vorschauen prüfen.
3. Als `Inlaut.icon` sichern; in den Xcode-Projektnavigator aufnehmen und dem App-Target zuordnen.
4. Unter App Icons and Launch Screen den App-Icon-Namen `Inlaut` eintragen (ohne `.icon`). Die genaue Oberfläche kann je nach Xcode-Version abweichen.
5. Auf dem Zielsystem mit hellen/dunklen Hintergründen, Clear/Tinted und den Bedienungshilfen prüfen. Der App-Icon-Einbau ändert nicht die Menüleisten-App-Konfiguration und erzeugt kein Dock-Icon.

**Nicht enthalten:** eine nativ erzeugte oder validierte `.icon`-Datei, eine `.icns`-Datei oder ein App-Build. Die SVG-Ebenen und die genaue Bauanleitung werden geliefert; der native Composer-Schritt bleibt erforderlich. OS-Versionsname und Glas-Regler aus dem Briefing sind kein zugesichertes Testergebnis dieses Pakets.

### Menüleisten-Assets

Fünf Image Sets mit den Namen `menubar-ready`, `menubar-recording`, `menubar-transcribing`, `menubar-preparing`, `menubar-failed` anlegen. Jeweils PNG @1x in den 1x-Slot und PNG @2x in den 2x-Slot legen; **Render As: Template Image**. Keine separate weiße Datei hinzufügen.

```swift
let image = NSImage(named: "menubar-ready")
image?.isTemplate = true
image?.size = NSSize(width: 18, height: 18)
statusItem.button?.image = image
statusItem.button?.setAccessibilityLabel("Inlaut: bereit")
```

### Farb-Assets

`InlautColors.swift` zum App-Target hinzufügen. Die Extension verwendet bewusst Asset-Namen und enthält keine hart codierte Appearance-Abfrage. Die erforderlichen Color Sets können im Paketverzeichnis mit diesem Python-3-Snippet erzeugt werden; danach den erzeugten Katalog in Xcode importieren oder die Sets in den bestehenden Katalog kopieren:

```python
import json
from pathlib import Path
source = json.loads(Path("tokens/colors.json").read_text())
catalog = Path("InlautColors.xcassets")
catalog.mkdir(exist_ok=True)
(catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
for token in source["colors"]:
    folder = catalog / (token["assetName"] + ".colorset")
    folder.mkdir(exist_ok=True)
    entries = []
    for appearance in ("light", "dark"):
        value = token[appearance].lstrip("#")
        rgb = [int(value[i:i+2], 16) / 255 for i in (0, 2, 4)]
        entry = {"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": f"{rgb[0]:.6f}", "green": f"{rgb[1]:.6f}", "blue": f"{rgb[2]:.6f}", "alpha": "1.000"}}}
        if appearance == "dark":
            entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        entries.append(entry)
    (folder / "Contents.json").write_text(json.dumps({"colors": entries, "info": {"author": "xcode", "version": 1}}, indent=2))
```

Verwendung: `.tint(.inlautAccent)`. Standardtext weiterhin `.foregroundStyle(.primary)`; native Flächen und Materialien verwenden. Die Markenflächen-Tokens dienen hauptsächlich Web/Marketing. Die Color Sets sind absichtlich nicht zusätzlich im ZIP enthalten, damit dessen vereinbarte Struktur erhalten bleibt.

### DMG

Fensterinhalt 660 × 400 pt, Iconzentren bei (170,200) und (490,200), Icongröße beispielsweise 96 pt. Die Bilder enthalten keine App- oder Programme-Icons: Diese werden durch die tatsächlichen Finder-Objekte dargestellt. Bei der Hintergrundzuweisung Retina-Datei mit korrekter logischer Größe verwenden; Finder-/DMG-Werkzeug separat prüfen. Die @2x-Datei misst 1320 × 800 px.

## Formate und Lizenz

Alle SVGs enthalten ausschließlich Pfadgrafik (ggf. transformierte Gruppen), keine Fonts, Bilder, Filter oder externen Referenzen. Alle PNGs sind RGBA mit eingebettetem sRGB-Profil. Logo und Icon haben transparente Umgebung; Social-, DMG- und Kontaktbogenflächen sind ihrer Funktion entsprechend deckend, behalten aber den Alphakanal.

Logo, Wortmarke und Icons: alle Rechte vorbehalten; **nicht GPL**. Der Programmcode behält seine eigene Lizenz. Manrope für Marketingtexte steht unter SIL OFL 1.1; die Wortmarke ist keine gesetzte Schrift. Siehe `LICENSE-ASSETS.md` und `DESIGN_GUIDE.md`.
