INLAUT — SPRACHIMPULS / PETROL & MINT

Ausgewählte Richtung: Sprachimpuls 03 mit der Farbwelt von Pegel 02.

DATEIEN
logo/: Skalierbare SVG-Wortbildmarken und transparente PNGs in 440, 880 und 1760 px Breite. Petrol, Mint, Schwarz, Weiß. Alle Buchstaben als eigene Vektorformen; keine Schriftinstallation erforderlich. Separates Symbol als SVG.
app-icon/: Statische Glas-Variante in 16, 32, 64, 128, 256, 512 und 1024 px; ICNS und klassisches macOS AppIcon.appiconset.
menu-bar/: Einfarbiges Template in 18/36/54 px und als SVG; InlautTemplate.imageset mit Template-Einstellung. In AppKit NSImage.isTemplate = true verwenden, bei SwiftUI .renderingMode(.template). Native Menüleisten-Tönung dem System überlassen.
web/: SVG-Favicon, ICO (16/32/48), PNGs 16/32/48/180/192/512 und Webmanifest.
icon-composer/: Unmaskierte 1024er Hintergrund- und transparente Vordergrundebene als SVG und PNG.
design-tokens/: CSS, JSON und Swift-Grundfarben.
source/: Generierter Glas-Master.

MACOS / LIQUID GLASS
Das ICNS/AppIcon.appiconset ist ein statischer Export, kein natives mehrschichtiges .icon-Dokument. Für dynamisches Liquid Glass die Dateien in icon-composer/ in Apples Icon Composer importieren, Ebenen ausrichten und Materialeigenschaften sowie Default/Dark/Mono-Ansichten dort einstellen. Den Hintergrund vollflächig verwenden; die Plattform-Maske nicht in diese Ebenen einbacken. Das Ergebnis als .icon sichern und in Xcode integrieren. Ein natives .icon-Dokument und ein Test in Xcode/macOS sind hier nicht enthalten.
Die flachen Produktionsvektoren sind eine geometrisch vereinheitlichte Nachzeichnung des ausgewählten Entwurfs. Der generierte Glas-Master kann optisch geringfügig abweichen. Für vollständig identische Konturen die beiliegenden Vektorebenen im Icon Composer verwenden.

FARBEN
Petrol #103D3B — Markenfarbe, dunkle Flächen, Wortmarke auf Hell.
Mint #BCEBD9 — Zeichen und Akzente auf Petrol, aktive Elemente auf Dunkel.
Porzellan #F6F7F4 — heller Hintergrund.
Ink #172C2B — primäre Schrift auf Hell.
Akzent #236E64 — Buttons auf Hell, mit weißer Beschriftung.
Nacht #0C201F / Fläche #153330 — Dunkelmodus.
Aufnahme #C84442 auf Hell / #FF9389 auf Dunkel, sparsam als Status.
Mint nicht für kleine Schrift auf weißem Grund verwenden. Status immer auch mit Text oder Form kommunizieren.

GESTALTUNG
Schutzraum um das Logo: mindestens Höhe des i-Punkts, empfohlen die Höhe eines kleinen Buchstabens. Wortbildmarke ab etwa 140 CSS-px Breite; darunter das Symbol nutzen. Logo nicht strecken. Die SVG-Datei ist der verbindliche flache Master. UI-Typografie: native Systemschrift (SF Pro auf macOS); auf Webseiten Systemfont-Stack. Glaseffekte der UI über native Materialien gestalten.

WEB-EINBINDUNG (Pfade an Projekt anpassen)
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/icon-180.png">
<link rel="manifest" href="/site.webmanifest">

REFERENZEN
https://developer.apple.com/icon-composer/
https://developer.apple.com/design/human-interface-guidelines/app-icons

ENTSTEHUNG
Visueller Entwurf und statisches Glas-Icon: integrierte Bildgenerierung. Produktions-SVGs und Größenexporte: geometrische Reinzeichnung und Rasterexport.
Kernprompt: Shape of option 03 Sprachimpuls, colors of option 02 Pegel; continuous rounded waveform, small side crests and tall central crest; pale mint on deep petrol; restrained glass depth.
