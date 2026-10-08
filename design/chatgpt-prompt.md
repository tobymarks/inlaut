# Prompt für ChatGPT: Designsystem und Asset-Paket für inlaut

Du bist Brand- und Icon-Designer:in für native macOS-Apps. Erstelle das komplette Designpaket für **inlaut**, eine kleine macOS-Menüleisten-App für Diktat. Sie arbeitet vollständig lokal. Arbeite in zwei Schritten und warte nach Schritt 1 auf meine Auswahl.

## Produkt

- Taste gedrückt halten, sprechen, loslassen: Der Text erscheint dort, wo gerade der Cursor steht, in jeder App.
- 100 % lokal: kein Konto, keine Cloud, nichts wird gespeichert. Deutsch zuerst (Parakeet-Modell), Open Source (GPL-3.0).
- Die App lebt nur in der Menüleiste (kein Dock-Icon). Sichtbar sind das Menüleisten-Icon, eine kleine schwebende Aufnahme-Kapsel in Liquid Glass (roter Punkt plus 7 Pegelbalken bzw. „Erkennt …“), ein Einstellungsfenster und ein Einrichtungsfenster für den Modell-Download.
- Zielgruppe: Leute, die viel schreiben (Wissensarbeit, Entwicklung, Fachsprache), und denen Datenschutz wichtig ist.
- Haltung: ruhig, präzise, leise, vertrauenswürdig, handwerklich. Nicht „AI-magisch“, kein Glitzer.

## Name und Schreibweise

- „inlaut“ ist ein Begriff aus der Sprachwissenschaft: der Laut im Inneren eines Wortes (im Gegensatz zu Anlaut und Auslaut).
- **Wortmarke: komplett klein, „inlaut“.** Auch im Fließtext, im App-Namen und am Satzanfang schreiben wir „inlaut“.
- **Verboten:** „laut“ optisch abtrennen oder hervorheben (inLAUT, inLaut, in·laut, „laut“ in anderer Farbe oder Schnitt). Es gibt eingetragene Marken „LAUT“ in den Klassen 9 und 42. Das Wort bleibt eine geschlossene Einheit.
- Spielraum gibt es nur *innerhalb* des Wortes, passend zur Bedeutung „Laut im Inneren“: Das „l“ in der Mitte darf zur Text-Einfügemarke (Caret) werden, also zu dem Punkt, an dem diktierter Text erscheint. Der i-Punkt darf als kleiner Aufnahmepunkt gelesen werden. Beides muss subtil bleiben, das Wort muss sich als „inlaut“ lesen.

## Leitidee für das Symbol (Vorschlag, gern variieren)

Die Einfügemarke zwischen Klang und Text: eine senkrechte Text-Caret, die zugleich der höchste Balken einer kurzen, ruhigen Schallwelle ist (z. B. 3–5 Balken, symmetrisch, der mittlere ist die Caret). Bedeutung: Sprache wird genau an der Cursorposition zu Text. Kein Mikrofon.

## macOS 27 (Golden Gate), Liquid Glass

- App-Icons werden in Icon Composer als geschichtete `.icon` gebaut: Canvas 1024 × 1024 px, das System legt die abgerundete Rechteck-Maske, Glas, Lichtkanten, Schatten und Refraktion selbst an.
- Deshalb in der Artwork **keine** eingebackenen Schatten, Glows, Bevels, Blur, Glanzlichter und keine eigene Rundung oder Maske. Vordergrund in klaren Vektorflächen, ausgerichtet an Apples Icon-Grid und zentriert.
- Maximal 4 Ebenengruppen: Hintergrund (Fläche oder einfacher Verlauf) plus 1–3 Vordergrund-Ebenen. So aufgebaut, dass das System Glas-Tiefe erzeugen kann.
- Darstellungen: Default (hell), Dark, Clear (hell/dunkel) und Tinted (hell/dunkel). Für Mono/Clear/Tinted soll eine Ebene reinweiß sein und der Rest in Graustufen funktionieren. Die Formen bleiben in allen Varianten identisch, nur Farben ändern sich.
- In macOS 27 gibt es einen Regler für die Glas-Transparenz. Alle UI-Farben müssen bei kräftigem und bei schwachem Glas lesbar sein.
- Menüleisten-Icons sind **Template-Images**: nur Schwarz mit Alpha, das System färbt sie für hell, dunkel und hervorgehoben ein. Glyphe etwa 16 pt hoch in einer 18 × 18 pt Box (Menüleiste 22 pt). Strichstärke optisch passend zu SF Symbols „regular“, aber **eigene Zeichnung**.

## Rechtliche Leitplanken (verbindlich)

- Keine SF Symbols und nichts, was ihnen „substantially or confusingly similar“ ist, im App-Icon, Logo oder in den Menüleisten-Glyphen (Lizenz von Apple). Alle Glyphen neu konstruieren.
- Keine Apple-Elemente: kein Apfel, keine Apple-Hardware, kein Siri-Orb, kein Apple-Intelligence-Regenbogenschein, nicht der Look von Voice Memos (rote Wellenform auf Dunkel), nicht das Mikrofon der macOS-Diktierfunktion.
- Abstand zu Wettbewerbern: Superwhisper (dunkles Icon mit silbernem, abgerundetem Dreieck), VoiceInk (blaues Mikrofon mit Füllfederspitze auf Schwarz), Wispr Flow (gestreiftes „W“, nur Schwarz/Weiß), Aqua Voice, MacWhisper. Also: kein Mikrofon als Hauptmotiv, kein schwarzes Icon mit Metall-Look.
- Keine Schriften von Apple (SF Pro, New York) in der Wortmarke. Entweder frei gezeichnete Buchstaben oder eine Schrift unter SIL Open Font License; Schriftname und Lizenz im Guide nennen. Am besten die Wortmarke als Pfade ausliefern.
- Keine Stock-Elemente und keine fremden Icon-Sets.

## Schritt 1: Richtungen (noch kein ZIP)

Zeig mir **drei klar unterschiedliche Richtungen**, jeweils mit:
1. App-Icon in Default und Dark (Mockup im macOS-27-Look, also mit Glas wie im Dock),
2. Wortmarke „inlaut“ hell und dunkel,
3. Menüleisten-Glyphe für „bereit“, in 16 px und 32 px, hell und dunkel,
4. Palette (5–7 Farben mit Hex) und 2 Sätzen Begründung.

Mindestens eine Richtung soll der Caret-Leitidee folgen. Farbe: Die Wettbewerber sind fast alle schwarz oder monochrom. Probier etwas Helleres, Wärmeres (z. B. papierweiß/Tinte mit einer klaren Signalfarbe für Aufnahme). Achte auf Kontrast nach WCAG AA.

## Schritt 2: das ZIP-Paket (nach meiner Auswahl)

Erzeuge mit Code (Python/SVG) eine ZIP-Datei `inlaut-design-v1.zip` mit genau dieser Struktur. Alle Vektoren als sauberes SVG mit Pfaden (keine eingebetteten Bitmaps, keine Texte als `<text>`), PNGs mit Transparenz und in sRGB, Dateinamen in Englisch und kebab-case.

```
inlaut-design-v1/
├─ README.md                         # Inhalt, Einbau in Xcode, Lizenzhinweis
├─ DESIGN_GUIDE.md                   # siehe unten
├─ LICENSE-ASSETS.md                 # Logo und Icon: alle Rechte vorbehalten, nicht GPL
├─ app-icon/
│  ├─ layers/                        # für Icon Composer, je 1024×1024 SVG
│  │  ├─ 00-background.svg
│  │  ├─ 01-foreground-*.svg         # 1–3 Ebenen, ohne Effekte
│  │  └─ layers.md                   # Reihenfolge, Farben je Darstellung (default/dark/mono), Glas an/aus je Ebene
│  ├─ preview/                       # flache Vorschau inkl. Maske, nur zur Ansicht
│  │  ├─ icon-default-1024.png
│  │  ├─ icon-dark-1024.png
│  │  ├─ icon-clear-light-1024.png
│  │  ├─ icon-clear-dark-1024.png
│  │  ├─ icon-tinted-light-1024.png
│  │  └─ icon-tinted-dark-1024.png
│  └─ flat/                          # Fallback mit Maske, für Web/README/.icns
│     ├─ icon-1024.png  icon-512.png  icon-256.png  icon-128.png  icon-64.png  icon-32.png  icon-16.png
│     └─ icon.svg
├─ menubar/                          # Template-Images: nur #000 + Alpha, ViewBox 18×18
│  ├─ menubar-ready.svg              # bereit
│  ├─ menubar-recording.svg          # nimmt auf (gefüllte Variante, eindeutig anders als bereit)
│  ├─ menubar-transcribing.svg       # erkennt / verarbeitet
│  ├─ menubar-preparing.svg          # Modell lädt / bereitet vor
│  ├─ menubar-failed.svg             # Fehler / nicht verfügbar (durchgestrichen o. ä.)
│  ├─ png/                           # jede Glyphe als @1x (18 px) und @2x (36 px)
│  └─ preview-menubar.png            # alle 5 in einer hellen und einer dunklen Menüleiste
├─ logo/
│  ├─ wordmark-inlaut-black.svg
│  ├─ wordmark-inlaut-white.svg
│  ├─ wordmark-inlaut-color.svg
│  ├─ lockup-horizontal-{color,black,white}.svg   # Symbol + Wortmarke
│  ├─ symbol-{color,black,white}.svg              # Symbol allein
│  └─ png/                                        # alle obigen als PNG mit 512 und 2048 px Breite
├─ web/
│  ├─ favicon.svg  favicon.ico (16/32/48)  apple-touch-icon-180.png
│  ├─ og-image-1200x630.png
│  └─ github-social-1280x640.png     # Repo-Vorschaubild
├─ distribution/
│  ├─ dmg-background-660x400.png  dmg-background-660x400@2x.png   # mit Pfeil App → Programme, Platz für 2 Icons bei x=170 und x=490, y=200
│  └─ readme-header-1600x400.png
└─ tokens/
   ├─ colors.json                    # Name, Hex hell, Hex dunkel, Verwendung
   └─ InlautColors.swift             # SwiftUI-Farben als Color-Extension (hell/dunkel über Asset-Namen)
```

### DESIGN_GUIDE.md muss enthalten

1. **Markenkern:** Idee, Haltung, 3 Adjektive, Bedeutung des Namens.
2. **Schreibweise:** immer „inlaut“, auch im Text, Verbote (siehe oben), Beispiele für richtig und falsch.
3. **Logo:** Aufbau, Schutzraum (in Einheiten der x-Höhe), Mindestgrößen in px und mm, erlaubte Farbvarianten, Don'ts mit Beispielen.
4. **App-Icon:** Ebenen-Aufbau, Grid, Verhalten in Default/Dark/Clear/Tinted, Schritt-für-Schritt-Anleitung für Icon Composer und den Export als `.icon` für Xcode.
5. **Menüleiste:** die 5 Zustände, wann welcher gilt, Template-Regeln, optischer Abgleich mit SF Symbols, keine Farbe, kein Animieren der Glyphe (die Aufnahme zeigt die schwebende Kapsel).
6. **Farben:** Palette mit Rollen (Akzent, Aufnahme, Text, Flächen) für hell und dunkel, Kontrastwerte. Grundsatz: In der App gelten Systemfarben und Materialien. Die Markenfarbe kommt nur sparsam als Akzent (`tint`) vor.
7. **Typografie:** In der App nur die Systemschrift (SF Pro über `.font(.body)` usw.). Auf Web und Marketing die gewählte OFL-Schrift mit Größenstufen.
8. **Liquid Glass in der App:** Aufnahme-Kapsel (`glassEffect` regular, Capsule), Aufnahmepunkt, 7 Pegelbalken (Breite 3 pt, Abstand 2,5 pt, Höhe 4–18 pt), Zustände Aufnahme / Erkennt / Hinweis, Verhalten beim Transparenz-Regler und bei „Kontrast erhöhen“ und „Bewegung reduzieren“.
9. **Bewegung:** Dauer und Kurven für das Ein- und Ausblenden der Kapsel und die Balken; Verhalten bei „Bewegung reduzieren“.
10. **Sprache und Ton:** deutsche UI-Texte, duzen, kurz, kein Marketing-Sprech, Beispiele (Berechtigungsdialoge, Fehlermeldungen, Menüeinträge).
11. **Rechtliches:** keine SF Symbols und keine Apple-Elemente in Marke und Icon, Schriftlizenz, Assets nicht unter GPL.

### Qualitätscheck vor dem Packen (bitte durchführen und berichten)

- Lesbarkeit des App-Icons bei 16 und 32 px und der Menüleisten-Glyphen bei 18 px, hell und dunkel, als Kontaktbogen-PNG `checks/contact-sheet.png` mit ins ZIP.
- Menüleisten-SVGs enthalten nur Schwarz mit Alpha.
- Alle Ebenen haben 1024 × 1024 und dieselbe Ausrichtung.
- Keine `<text>`-Elemente, keine externen Referenzen in SVGs.
- Wenn du etwas nicht exakt liefern kannst (z. B. die `.icon`-Datei selbst oder `.ico`), sag das ausdrücklich, statt es vorzutäuschen.
