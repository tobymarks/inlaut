# Setzpunkt · Icon-Composer-Ebenen

Alle SVGs: 1024 × 1024, ViewBox `0 0 1024 1024`, identischer Ursprung, nur gefüllte Pfade. Kein Zuschnitt, keine individuelle Skalierung. Drei Ebenengruppen insgesamt.

| Reihenfolge hinten → vorn | Datei | Default | Dark | Mono-Quelle | Glas |
|---|---|---|---|---|---|
| 0 Hintergrund | 00-background.svg | #F6F2E9 | #182E30 | #808080 | aus; native Background-Füllung |
| 1 Klang | 01-foreground-sound.svg | #236B63 | #9AC9BB | #FFFFFF | an; beide Balken gemeinsam |
| 2 Caret | 02-foreground-caret.svg | #236B63 | #9AC9BB | #FFFFFF | an; eine zusammenhängende Form |

Den Hintergrund als native flächige Background-Füllung anlegen; das SVG ist die genaue Farbreferenz und eine importierbare Alternative. Nicht zusätzlich beide Hintergrund-Versionen übereinanderlegen. Klang und Caret auf gleiche visuelle Tiefe setzen, keine dramatische Staffelung. Effektstärke zunächst auf dem Systemstandard belassen; bei weich werdender Silhouette reduzieren. Keine zusätzliche gemalte Lichtkante.

## Geometrie

Canvaszentrum (512, 512). Konstruktionsraster 8 Einheiten, optische Rundungen 10 Einheiten. Symbolgrenzen x=282…742, y=264…760; horizontal und vertikal zentriert. Caretstamm x=476…548, Enden x=432…592. Seitenbalken x=282…350 und 674…742, y=404…620. Freie Flächen sind Teil der Marke. Das Raster ist die Inlaut-Konstruktion innerhalb des Apple-Templates, keine Behauptung einer verbindlichen Apple-Sicherheitszone.

## Darstellungen

Default/Dark verwenden identische Pfade. In der Mono-Konfiguration sind beide Vordergrundebenen reinweiß; das System erzeugt Clear und Tinted daraus. Keine vorgefärbte Tinted-Datei als Composer-Quelle verwenden.

Die sechs Dateien in `../preview/` sind **flache Farb- und Silhouettenproben mit transparenter Umgebung**. Clear-Light: #E8E8E8/#292929, Clear-Dark: #292929/#FFFFFF; Tinted-Light: #DFEBE5/#254F47, Tinted-Dark: #1C312D/#A5D2C3. Diese Farben illustrieren die Wirkung, sie bilden weder Refraktion noch einen benutzergewählten Systemtint exakt ab.

Die Vorschau-/Fallback-Maske (24 Einheiten Rand, abgerundete Fläche) ist eine Annäherung für externe Anwendungen. **Nicht in Icon Composer importieren.** Dort bestimmt das System die endgültige Maske. Die 16-/32-Pixel-Fallbacks sind optisch auf das Pixelraster angepasst; sie ersetzen nicht die hochauflösenden Quellpfade.

Siehe DESIGN_GUIDE.md, Abschnitt 4, für den Import und die Prüfung aller Darstellungen.
