# Inlaut · Design-Guide v1

Richtung A: **Setzpunkt**. Stand 8. Oktober 2026.

## 1. Markenkern

Inlaut ist der Laut im Inneren eines Wortes. Das Zeichen stellt eine Einfügemarke zwischen zwei kurzen Klangbalken dar: Sprache wird dort zu Text, wo der Cursor steht. Drei Adjektive: **ruhig, präzise, vertrauenswürdig**. Die Marke stellt das Werkzeug und die Kontrolle durch den Menschen in den Mittelpunkt. Keine Magie, kein Assistenten-Avatar, kein Glitzer.

## 2. Schreibweise

Die Wortmarke lautet immer **inlaut**, als geschlossene Einheit in einer Farbe und einem Schnitt. Im Fließtext, als App-Name, in Menüs und am Satzanfang: **Inlaut**.

Richtig: „Inlaut öffnen“, „Mit Inlaut diktieren“, unveränderte Wortmarke `inlaut`.
Falsch: „inLAUT“, „inLaut“, „in·laut“, „in laut“, farbiges oder fettes „laut“. Auch getrennte Animationen der Wortteile sind verboten. Das „l“ ist ein schlichter Stamm ohne Caret-Abschluss, damit das Wort nicht als „inIaut“ gelesen wird; die Einfügemarke lebt im Symbol. Der i-Punkt bleibt in der Wortmarkenfarbe und wird nicht zum roten Statussignal.

## 3. Logo

### Aufbau

Eigenzeichnung „Inlaut Setzpunkt Lettering v1“, keine Fontdatei. Sechs frei konstruierte Kleinbuchstaben mit gleicher optischer Stammstärke, einstöckigem a und offenem humanistischem Rhythmus. Stammstärke 18 Einheiten, x-Höhe 84 Einheiten, Grundlinie y=132. Alle Buchstaben ohne Ornament; die Einfügemarke gehört ausschließlich zum Symbol. Alle Farbvarianten verwenden identische Pfade.

Wortmarken-Canvas: 455 × 142; Symbol: 576 × 576; horizontaler Lockup: 622 × 162. Der Lockup ist verbindlich, nicht selbst mit Text nachsetzen. Seine Symbolhöhe beträgt rund 99 Einheiten; die Wortmarke bleibt dominant.

### Schutzraum und Mindestgrößen

Schutzraum um die sichtbare Wortmarke: mindestens **0,5 × x-Höhe**, um den Lockup ebenfalls 0,5 × x-Höhe seiner Wortmarke. Beim alleinstehenden Symbol: mindestens 0,25 × sichtbare Symbolhöhe. Die SVG-Canvasränder enthalten diesen zusätzlichen äußeren Schutzraum nicht vollständig; im Layout freihalten.

| Asset | Mindestbreite Bildschirm | Mindestbreite Druck |
|---|---:|---:|
| Wortmarke | 90 px | 24 mm |
| Horizontaler Lockup | 150 px | 40 mm |
| Freies Markensymbol | 24 px | 6,5 mm |
| App-/Favicon-Fallback | 16 px | nicht für Druck |

Die Größen sind optische Anwendungsempfehlungen; Druckwerte beziehen sich auf normale Betrachtungsentfernung. Unter 90 px die Wortmarke nicht weiter verkleinern, sondern das Symbol verwenden. Menüleisten-Assets sind separat für 18 pt konstruiert.

### Farbe und Don'ts

Erlaubt: Petrol auf Papier, Schwarz auf hellen Flächen, Weiß auf dunklen Flächen. Auf dunklem Markenhintergrund kann für größere Anwendungen der gesamte Pfad einheitlich Mint erhalten; als direkt mitgelieferte helle Variante steht Weiß zur Verfügung. Farbe nie innerhalb des Wortes wechseln.

Nicht strecken, drehen, mit Kontur versehen, mit Schatten/Glow ausstatten oder in einen Badge zwängen. Keine getrennte Farbe für „laut“, keine dekorative Wellenform anstelle einzelner Buchstaben. Den Markennamen nicht aus Manrope oder SF Pro nachbauen. Systemglas darf das App-Icon behandeln, nicht die normale Wortmarke.

## 4. App-Icon

### Aufbau und Grid

1024 × 1024 px, gemeinsames Zentrum (512,512), drei Gruppen: Hintergrund, zwei Klangbalken, Caret. Das eigene 8-Einheiten-Konstruktionsraster hält Achsen und Abstände zusammen; Rundungen sind optisch korrigiert. Geometrie und Farbmatrix stehen vollständig in `app-icon/layers/layers.md`.

Keine Maske, Schatten, Blur, Reflexe oder Verläufe in den Quell-SVGs. Die Außenmaske in `flat/` und `preview/` dient ausschließlich externen Ansichten. Sie ist eine Annäherung und kein exportiertes Apple-Template. Die Vordergrund- und Hintergrundquellen beim Import nie auf sichtbare Grenzen beschneiden.

### Icon Composer Schritt für Schritt

1. Xcode → Open Developer Tool → Icon Composer. Neues Dokument anlegen und macOS, 1024 × 1024 einstellen.
2. Aktuelles Apple-App-Icon-Template/Grid einblenden und die zentrierte Konstruktion kontrollieren; keine manuellen abgerundeten Ecken importieren.
3. Native Hintergrundfläche #F6F2E9 anlegen. `00-background.svg` dient als Referenz oder alternative Fläche, nicht als zusätzliche vierte Ebene.
4. `01-foreground-sound.svg` und `02-foreground-caret.svg` als separate Gruppen importieren, volle Canvasgröße und unveränderte Positionen behalten.
5. Für beide Vordergrundgruppen Liquid Glass einschalten. Gleiche Tiefe, zurückhaltende systemseitige Lichtkante; keine zusätzliche gemalte Kante. Hintergrund ohne Glas.
6. Default: Papier/Petrol. Dark: Tinte/Mint. In der Appearance-/Color-Konfiguration die Farben überschreiben, nicht die Formen verschieben.
7. Mono: Hintergrund neutralgrau #808080, beide Vordergrundgruppen #FFFFFF. Clear light/dark und Tinted light/dark aus dieser Konfiguration vom System erzeugen lassen. Mit einem hellen und einem dunklen Systemtint prüfen.
8. Im Composer sowohl kleine Größen als auch jede Appearance prüfen, zusätzlich gegen ruhigen und unruhigen Desktop-Hintergrund. Vordergrund muss als ein zusammengehöriges Zeichen wirken.
9. Dokument als `Inlaut.icon` sichern. Das ist der native Icon-Composer-Container, kein umbenanntes PNG und kein ZIP der SVGs. In Xcode aufnehmen, Target-Zugehörigkeit setzen und App-Icon-Namen `Inlaut` wählen.
10. Auf dem Zielsystem prüfen. Diese Lieferung enthält die Artwork, **keinen nativ erzeugten `.icon`-Container**. Die flachen Clear-/Tinted-PNGs simulieren nur Farbverhältnisse; weder Refraktion noch tatsächliche Systemdarstellung wurden damit getestet.

Die Form bleibt in allen Appearances identisch. 16-/32-Pixel-Fallbacks haben eine kleine optische Anpassung an ganze Pixel; höhere Größen verwenden direkt die gemeinsame Vektorkonstruktion. Kein Dock-Icon durch Änderung der App-Konfiguration aktivieren: Inlaut bleibt Menüleisten-App.

## 5. Menüleiste

Alle Dateien haben ViewBox `0 0 18 18`; zentrale Zeichenhöhe 16 pt. Originalpfade, keine SF-Symbol-Exporte oder Nachzeichnungen. Optisches Ziel ist das Gewicht regulärer Systemglyphen, kein geometrisches Matching eines bestimmten Apple-Symbols. Pixelkontrolle im Kontaktbogen durchgeführt; der abschließende optische Vergleich in einer echten Systemmenüleiste steht beim Einbau an.

| Zustand | Wann | Form |
|---|---|---|
| ready | Modell bereit, kein aktives Diktat | feiner Caret, zwei kurze Balken |
| recording | Mikrofonaufnahme läuft | deutlich breiter gefüllter Caret, längere kräftige Balken |
| transcribing | Aufnahme beendet, Erkennung läuft | Caret, links/rechts je zwei horizontale Textstriche |
| preparing | Modell lädt oder Engine wird vorbereitet | zentral unterbrochener Caret, kurze Seitenmarken |
| failed | Diktat momentan nicht verfügbar | unterbrochene Grundform mit diagonaler Sperrlinie |

Die Glyphe wird nicht animiert. Zustand zusätzlich als zugänglicher Text ausgeben: „Inlaut: bereit“, „Inlaut: nimmt auf“, „Inlaut: erkennt“, „Inlaut: wird vorbereitet“, „Inlaut: nicht verfügbar“. Systemseitige Auswahl-/Highlight-Farbe respektieren.

Nur Schwarz und Alpha in den Quellen; niemals eine weiße Fläche als Aussparung einsetzen. PNG @1x = 18 px, @2x = 36 px. In Xcode „Render As: Template Image“, in AppKit `isTemplate = true`, Anzeigegröße 18 × 18 pt. Weiß in den Vorschauen ist ausschließlich simulierte Systemfärbung. Aufnahme-Rot gehört in die Kapsel, nicht in die Menüleiste.

## 6. Farben und Kontrast

| Rolle | Hell | Dunkel |
|---|---|---|
| Markenfläche | Papier #F6F2E9 | Tinte #182E30 |
| Sekundäre Fläche | Sand #E4DCCF | #243D3E |
| Text | Tinte #182E30 | Papier #F6F2E9 |
| Akzent / bedeutungstragende Kontur | Petrol #236B63 | Mint #9AC9BB |
| Aufnahmepunkt | Ziegel #C44336 | Koralle #FF8E80 |

Sieben Hauptfarben; #243D3E ergänzt eine sekundäre Dunkelfläche. JSON-Tokens führen die semantischen Paare zusammen. Sand ist eine Fläche/dekorative Trennung, kein ausreichend kontrastierender interaktiver Rahmen.

Berechnet nach relativer sRGB-Luminanz, gerundet:

| Kombination auf primärer Markenfläche | Hell | Dunkel |
|---|---:|---:|
| Text | 12,77:1 | 12,77:1 |
| Akzent | 5,60:1 | 7,77:1 |
| Aufnahmepunkt | 4,47:1 | 6,41:1 |

Normaler Text benötigt 4,5:1, große Schrift 3:1, bedeutungstragende Nicht-Text-Grafik 3:1. **Ziegel auf Papier ist kein freigegebenes Paar für kleinen Text.** Stattdessen normalen Text in Tinte setzen und Rot auf den Punkt beschränken. Farbe nie als einzige Statusinformation verwenden.

In der App gelten Systemfarben und native Materialien: `.primary`, `.secondary`, Systemhintergründe; Markenfarbe nur sparsam über `.tint(.inlautAccent)`. Die Zahlen oben gelten für deckende Farbpaare und sind keine pauschale Freigabe für beliebige Fotos oder transparentes Glas. Lesbarkeit bei beiden Glas-Einstellungen durch Systemmaterial und die in Abschnitt 8 definierte deckende Rückfallebene sichern.

## 7. Typografie

**App:** ausschließlich Systemschrift über semantische SwiftUI-Stile: `.font(.body)`, `.headline`, `.caption`; keine Fontdateien bündeln. SF Pro wird vom System gewählt, niemals als Wortmarke exportiert.

**Web und Marketing:** Manrope, SIL Open Font License 1.1; Quelle https://github.com/google/fonts/tree/main/ofl/manrope. Copyright 2018 The Manrope Project Authors. Die gelieferten Marketingbilder verwenden Manrope Medium (500); die frei gezeichnete Wortmarke bleibt davon unabhängig. Kein Apple-Font in den Markenassets.

| Einsatz | Größe / Zeilenhöhe | Gewicht |
|---|---|---|
| Große Web-Überschrift | 48 / 56 px | 600 |
| Mobile Überschrift | 34 / 42 px | 600 |
| Abschnitt | 28 / 36 px | 600 |
| Fließtext | 18 / 28 px | 400 |
| Bedienelement / kurzer Hinweis | 16 / 24 px | 500 |
| Meta / Bildunterschrift | 14 / 20 px | 500 |

Web: `font-family: Manrope, sans-serif`; normale Laufweite, keine künstlich gesperrten Fließtexte. Überschriften möglichst 2–3 Zeilen, Fließtext 55–75 Zeichen breit. Font für Website lokal ausliefern und OFL beilegen. Fontdateien sind nicht Teil des vereinbarten ZIP-Baums; die vollständige OFL steht in LICENSE-ASSETS.md.

## 8. Liquid Glass in der App

Die schwebende Kapsel ist eine nicht aktivierende Anzeige, die den Tastaturfokus nicht übernimmt. Horizontale Innenabstände 14 pt, vertikale 10 pt, Mindesthöhe 38 pt, normale Systemschrift. Eine einzelne `glassEffect(.regular, in: Capsule())`-Fläche; keine weiteren Glasflächen ineinander stapeln. Auf unterstützten Systemen die native API verwenden, bei älteren Zielsystemen eine native Material-/deckende Fallback-Fläche.

**Aufnahme:** roter Punkt 6 pt Durchmesser, Abstand zur Balkengruppe 10 pt. Genau 7 Balken, je 3 pt breit, Abstand 2,5 pt, Höhe 4–18 pt, mittig vertikal ausgerichtet. Gruppenbreite 36 pt. Balken in `.primary`, Punkt in `.inlautRecording`; kein rotes Waveform-Icon auf schwarzer Fläche. Accessible Label „Inlaut nimmt auf“; keine fortlaufenden Pegelansagen.

**Erkennt:** Balken durch „Erkennt …“ ersetzen, Systemtext, kein dauerhaft roter Punkt mehr. Mindestens 108 pt Kapselbreite reservieren, damit der Wechsel ruhig bleibt. Kein erfundener Prozentfortschritt.

**Hinweis:** beispielsweise „Kein Ton erkannt“ oder „Mikrofon prüfen“. Bei handlungsbedürftigen Fehlern zusätzlich Menüstatus/Eintrag; den Hinweis nicht als einzige Möglichkeit zur Problemlösung nach wenigen Sekunden verschwinden lassen.

**Glas-Einstellung:** Systemmaterial auf die Nutzereinstellung reagieren lassen; keine selbst errechnete Glas-Opacity erzwingen. Bei kräftigem und schwachem Glas sowie hellem, dunklem und detailreichem Hintergrund testen. `accessibilityReduceTransparency` respektieren: deckender nativer Fensterhintergrund. Bei erhöhtem Kontrast (`colorSchemeContrast == .increased`) ebenfalls deckenden Hintergrund mit klarer Systemkontur wählen. Inhalt nicht durch reduzierte Gesamt-Opacity abschwächen. Falls Messungen eines bestimmten Hintergrunds die Text-/Punktkontraste unterschreiten, für die gesamte Kapsel den deckenden Fallback verwenden.

`accessibilityReduceMotion` beeinflusst Balken und Übergänge gemäß Abschnitt 9. Statuswechsel einmal ankündigen; Sprachaufnahme nicht wegen rein dekorativer Animationen verzögern.

## 9. Bewegung

- Einblenden: Opacity 0→1, 160 ms, ease-out; höchstens 3 pt vertikaler Versatz.
- Ausblenden: Opacity 1→0, 120 ms, ease-in. Keine Feder, kein Bounce.
- Pegel: tatsächliche gemessene Lautstärke, optisch geglättet mit ca. 70 ms Anstieg und 160 ms Abfall, lineare Höheninterpolation; maximal 30 visuelle Aktualisierungen/s.
- Zustandswechsel Aufnahme→Erkennt: 100 ms Crossfade in gleicher Kapsel, kein Größen-Bounce.
- Bewegung reduzieren: keine räumliche Bewegung, keine Pegelanimation; sieben statische Balken (4,7,11,14,11,7,4 pt) plus Punkt, zustandsabhängiger Text bleibt. Opacity maximal 80 ms oder sofort.
- Menüleisten-Glyphe bleibt immer statisch; im Leerlauf laufen keine Animations-Timer.

## 10. Sprache und Ton

Deutsch zuerst, duzen, konkrete Verben, kurze Sätze. Keine „KI-Magie“, „revolutionären Workflows“ oder unbelegten Leistungsversprechen. Datenschutzbehauptungen müssen zum tatsächlich ausgelieferten Verhalten passen: Audio/Text nicht speichern heißt nicht, dass heruntergeladene Modelle oder Einstellungen nicht lokal gespeichert werden.

| Situation | Text |
|---|---|
| Menü | „Einstellungen …“, „Modell laden …“, „Inlaut beenden“ |
| Einführung | „Halte die Taste gedrückt und sprich. Lass los, um den Text einzufügen.“ |
| Mikrofon | „Inlaut braucht Zugriff auf dein Mikrofon, um deine Stimme in Text umzuwandeln.“ |
| Bedienungshilfen | „Erlaube Inlaut den Zugriff unter Bedienungshilfen, damit der Text in deiner aktiven App erscheint.“ |
| Modell-Download | „Sprachmodell laden“ / „Der Download ist nur für die Einrichtung nötig. Danach diktierst du lokal.“ |
| Downloadfehler | „Das Modell konnte nicht geladen werden. Prüfe deine Verbindung und versuche es erneut.“ |
| Kein Audio | „Kein Ton erkannt. Prüfe dein Mikrofon und sprich erneut.“ |
| Einfügen fehlgeschlagen | „Der Text konnte nicht eingefügt werden.“ Nur bei tatsächlich verfügbarem Clipboard ergänzen: „Du kannst ihn mit ⌘V einfügen.“ |
| Bereit | „Bereit zum Diktieren“ |

Modellgröße, Downloadfortschritt und benötigten Speicher aus tatsächlichen Daten anzeigen. Berechtigungsdialoge erklären den Nutzen, erzeugen keinen Druck. Bestätigungsbuttons konkret benennen: „Einstellungen öffnen“, „Erneut versuchen“.

## 11. Rechtliches und Herkunft

Wortmarke und alle Glyphen wurden für dieses Paket aus geometrischen Pfaden konstruiert. Keine SF-Symbol-Dateien, fremden Icon-Sets, Stockgrafiken oder Apple-Marken-/Hardwareelemente wurden übernommen. SF Symbols dienen höchstens dem optischen Gewichtsvergleich der fertigen Menüleiste, nicht als Vorlage. Keine Mikrofon-, Siri-, Apple-Intelligence- oder Voice-Memos-Motive.

Die Wortmarke ist eine Eigenzeichnung. Manrope ist die separat lizenzierte Marketingschrift (SIL OFL 1.1), deren Bedingungen unverändert gelten. Logo und Icon sind ausdrücklich **nicht unter GPL**; die GPL-Lizenz des Programmcodes wird dadurch nicht verändert. Marken- und Asset-Nutzung bei Forks muss separat geklärt werden; keine implizite Markenlizenz durch den Quellcode ableiten. Vollständiger Hinweis in LICENSE-ASSETS.md. Eine rechtliche Kollisions-/Markenprüfung ist durch die geometrische Eigenkonstruktion nicht ersetzt.

## Prüfung und Grenzen

Automatisch geprüft: Dateibaum, SVG-Pfade ohne Text/Bilder/externe Referenzen/Effekte, gemeinsame 1024er Ebenen, schwarze Template-Quellen, PNG-Abmessungen und sRGB, ICO-Größen, Farbkontraste und unveränderte Logo-Geometrie über Farbvarianten. Kontaktbogen visuell geprüft: App 16/32 px, Menüleiste 18 px auf hell/dunkel. Social-/DMG-/Logo-Layouts separat kontrolliert.

Nicht geprüft: reale Icon-Composer-Renderings, macOS-Menüleisten-Integration, tatsächliche Glas-Reglerzustände und Finder-DMG-Verhalten. Diese Prüfungen erfolgen beim Einbau; die SVG-/PNG-Exporte sind keine Behauptung einer abgeschlossenen nativen App-Integration.

## Technische Quellen

- Apple, Icon Composer: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
- Apple, App icons: https://developer.apple.com/design/human-interface-guidelines/app-icons
- Apple, Template images: https://developer.apple.com/documentation/appkit/nsimage/istemplate
- Apple, SwiftUI Color: https://developer.apple.com/documentation/swiftui/color
- Apple, glassEffect: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- W3C, Textkontrast: https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
- W3C, Nicht-Text-Kontrast: https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html
- Manrope/OFL: https://github.com/google/fonts/blob/main/ofl/manrope/OFL.txt
