# inlaut for Windows

Native, hochperformante On-Device-Diktier-App für Windows 10 & 11 ohne Cloud-Zwang.

Für die Fortsetzung der Entwicklung direkt unter Windows: [HANDOFF.md](HANDOFF.md).

## Öffentliche Beta 0.7.0-beta.9

[Windows-Installer herunterladen](https://github.com/tobymarks/inlaut/releases/download/windows-v0.7.0-beta.9/inlaut-0.7.0-beta.9-windows-x64-setup.exe)
für Windows 10/11 x64. Deutsch und Englisch sind mit getrennten lokalen Modellen
enthalten; Diktat- und Oberflächensprache lassen sich unabhängig einstellen.
Sprachwechsel benötigen einen Neustart. Gemischtsprachiges Diktieren ist Mac-only.

**Diese Beta ist nicht digital signiert.** Windows kann „Der Computer wurde durch
Windows geschützt“ oder einen unbekannten Herausgeber anzeigen. Die
[Downloadseite](https://inlaut.de/windows) erklärt diese Warnung und die
Installationsschritte. Geräte mit Smart App Control oder Unternehmensrichtlinien
können die Installation vollständig blockieren.

inlaut vor der Installation über das Tray-Menü beenden. Updates werden manuell
von der Website heruntergeladen und installiert; der signierte In-App-Updater
kann diese unsignierte Beta nicht aktualisieren. Einstellungen bleiben bei einer
Neuinstallation erhalten. [Release und Prüfsumme](https://github.com/tobymarks/inlaut/releases/tag/windows-v0.7.0-beta.9).

Bekannte Grenzen: Leise Sprache kann abgeschnitten werden; Leerzeichen und
Großschreibung zwischen getrennten Diktaten benötigen mitunter Korrekturen.
Windows 11, Standby und Mikrofonwechsel sind noch nicht vollständig geprüft.
Weitere Hinweise: [installer/BETA.md](installer/BETA.md).

Die folgenden Vorschauversionen dokumentieren die Entwicklung vor dieser Beta.

## Qualitätstestversion 0.6.4-model-preview.1

Separates portables Paket mit Parakeet TDT v3 INT8 und der beschleunigten Eingabe
aus 0.6.3. Im kleinen Vergleich mit menschlichen deutschen Sprachaufnahmen erkannte
es mehr richtig als das kompakte Modell, benötigt aber etwa 640 MiB Modellplatz
und rund 1 GiB RAM. Die kleine Variante 0.6.3 bleibt verfügbar; der Standarddownload
wird noch nicht umgestellt. Messwerte und Grenzen: [MODEL_EVALUATION.md](MODEL_EVALUATION.md).

## Testversion 0.6.3-input-preview.1

Die Tray-App fügt Text jetzt standardmäßig direkt in native Windows-Textfelder
ein, ohne die Zwischenablage zu verwenden. Andere Felder erhalten einzeiligen
Text Zeichen für Zeichen. Unter **Hilfe & Diagnose → Eingabe per
Zwischenablage** lässt sich der bisherige Weg zum Vergleich einschalten.
Native Felder erhalten den Text in einem Schritt mit Rückgängig-Unterstützung.
Die beschleunigte zeichenweise Ausgabe erreicht im isolierten Test rund 200 Zeichen
pro Sekunde; 1260 Zeichen benötigen etwa 6,2 Sekunden. Das Verhalten im konkreten
ChatGPT-/Codex-Feld muss noch separat bestätigt werden.
Währenddessen bitte im Zieltextfeld bleiben: Bei Fokuswechsel oder Zusatztasten
wird abgebrochen, bereits eingefügter Text bleibt stehen. Im zeichenweisen Weg
können bereits an Windows übergebene Zeichen noch im neu fokussierten
Feld ankommen. Mehrzeilige Eingabe in anderen als nativen Windows-Textfeldern
benötigt vorerst den ausdrücklich auswählbaren Zwischenablage-Modus.
Es gibt keinen automatischen zweiten Einfügeversuch.

Das Tray-Menü hat mehr Abstand, getrennte Spalten für Symbole und Tastenkürzel
und einheitliche Untermenüs. Getestet auf Windows 10 bei 200 % Skalierung.
Details und verbleibende Prüfungen stehen in `HANDOFF.md`.

### Vorherige Diagnoseversion 0.6.1

Menüsymbole verwenden jetzt die native Bildspalte; die Aufnahmeanzeige berechnet
getrennte Bereiche für Symbol, gemessenen Text und Pegelbalken in Bildschirm-Pixeln.

### Audio und Erkennung für Tests sichern

1. Tray-Menü → **Hilfe & Diagnose → Testaufnahmen speichern** aktivieren.
2. Bis zu zehn Beispielsätze diktieren, auch mit Pausen und Fachbegriffen.
3. **Diagnoseordner öffnen** wählen. Unter `captures` liegt ein Ordner pro Testsitzung.
4. Den gewünschten Sitzungsordner als ZIP zusammenpacken und zur Auswertung teilen.
   Falls möglich, den beabsichtigten Wortlaut der fehlerhaften Beispiele dazuschreiben.

Pro Diktat enthält der Ordner:
- `recorded.wav`: vollständige Mikrofonaufnahme vor dem Kürzen.
- `recognizer-input.wav`: die tatsächlich an das Modell übergebenen Samples nach dem Kürzen.
- `result.json`: unbearbeitetes und nachbearbeitetes Transkript, Laufzeiten oder Fehlerstatus.
- `metadata.json`: App-/Modellkonfiguration und Einstellungen der Textverarbeitung.

Die WAV-Dateien sind PCM16, mono, 16 kHz wie die Aufnahme. Die Testsicherung ist
standardmäßig aus und endet nach zehn Diktaten, beim erneuten Anklicken oder beim
Beenden der App. Diese Dateien enthalten ausdrücklich Audio und diktierte Inhalte.
Sie bleiben lokal, werden nicht hochgeladen und können im Diagnoseordner gelöscht
werden. Die 1-MB-Rotation der Metadatenprotokolle gilt nicht für die Testaufnahmen.

Die Oberfläche folgt jetzt gemeinsamen Windows-11-/Fluent-Regeln: kompaktes Tray-Menü,
Windows-Symbole, Segoe-Schrift, Hell-/Dunkelmodus nach Systemeinstellung und
Kontrastfarben. Einstellungen, Infodialog, Downloadfenster und Aufnahmeanzeige
verwenden denselben Stil. Die bewährte Fenstergröße und das skalierbare Layout bleiben.
Details und Microsoft-Referenzen stehen in `DESIGN.md`.

Die Diagnose hat die Zeichenketten auf die Übergabe an das Zielprogramm eingegrenzt.
Der weiterhin verfügbare Vergleichsmodus verwendet einen einzelnen Einfügevorgang (Strg+V).
Das Diktat ersetzt den bisherigen Zwischenablage-Inhalt und bleibt dort, bis
du etwas anderes kopierst. Es gibt keine zeitgesteuerte Wiederherstellung, damit
langsame Zielprogramme nicht versehentlich den alten Inhalt einfügen. Der Diktattext wird für den
Windows-Zwischenablageverlauf und die Cloud-Synchronisation ausgeschlossen.
Das Sprachmodell lädt im Hintergrund; Einstellungen verwenden ein Layout ohne
gegenseitige Größenänderungen. Während die Einstellungen offen sind, ist Diktieren pausiert.

Vor dem Start die vorherige App über das Tray-Menü beenden und das neue ZIP in
einen eigenen Ordner entpacken. „Über inlaut“ zeigt die Build-Version samt Commit-Kennung.

Nach einem fehlerhaften Diktat: Rechtsklick auf das Tray-Icon → „Diagnoseordner öffnen“.
Die Datei `latest.jsonl` enthält Aufnahmedauer, Signalpegel, Zeichenanzahl,
Satzzeichenfolgen vor/nach der Textverarbeitung und das Absenden des Einfügebefehls (keine Bestätigung durch das Zielprogramm).
Sie enthält weder diktierte Texte noch Audio und wird nicht hochgeladen.
Die Dateien liegen unter `%LocalAppData%\inlaut\diagnostics`; maximal zwei Dateien
von jeweils ungefähr 1 MB werden aufbewahrt und können jederzeit gelöscht werden.

---

## 🚀 Schnelleinstieg für Nutzer

1. Lade den **Windows-Beta-Installer** von [inlaut.de/windows](https://inlaut.de/windows) herunter und beachte den Hinweis zur fehlenden Signatur.
2. Beende eine laufende inlaut-Version und führe den Installer aus. Administratorrechte sind nicht erforderlich.
3. Starte **inlaut Beta** über das Startmenü:
   * Die App startet direkt im Infobereich (System Tray) unten rechts in der Taskleiste.
   * Die deutschen und englischen Sprachmodelle sind bereits enthalten; das gewählte Modell wird lokal geladen.
   * Keine Konfiguration oder Terminal-Befehle notwendig!

---

## ⌨️ Bedienung

* **Diktat starten & stoppen:**
  * Tastenkürzel: **`Strg + Alt + Leertaste`**
  * Alternativ: **Doppelklick auf das inlaut-Icon** im Infobereich.
* **Während der Aufnahme:**
  * Das Taskleisten-Icon signalisiert den Aufnahmestatus mit einem roten Punkt.
* **Nach dem Diktat:**
  * Sobald du die Tastenkombination erneut drückst, wird das Gesprochene lokal auf deinem Rechner transkribiert, durch die inlaut-Textpipeline bereinigt (Scharf-S-Wiederherstellung, Sprachbefehle, Formatierungen) und **direkt an der Cursor-Position in das aktive Fenster eingefügt** (Word, Browser, Outlook, Teams, Editor...).
  * Standardmäßig bleibt die Zwischenablage unberührt. Im Zwischenablage-Modus ersetzt das Diktat den bisherigen Inhalt und bleibt dort, bis etwas anderes kopiert wird.

---

## ⚙️ Infobereich (Rechtsklick auf das Tray-Icon)

* **🎙️ Diktat starten / stoppen:** Aufnahme per Klick toggeln
* **📁 Modell-Ordner öffnen:** Öffnet den Speicherort des lokalen Sprachmodells im Windows-Explorer
* **ℹ️ Über inlaut:** Versions- und Projektinformationen
* **❌ Beenden:** Beendet die App

---

## 🛠️ Technische Architektur

* **`Inlaut.App`** (Windows-GUI / System Tray Host):
  * Leichtgewichtiger, ressourcenschonender Host für den Infobereich.
  * `AudioRecorder`: Aufnahme über Windows-Audio-Subsystem (16 kHz Mono).
  * `HotkeyReceiver`: Systemweiter Tastatur-Hook für `Strg + Alt + Leertaste`.
* **`Inlaut.Platform.Windows`**:
  * `SherpaEngine`: Lokale Inferenz mit FastConformer / Parakeet Modellen auf CPU oder DirectML via `sherpa-onnx`.
  * `TextInserter`: ursprüngliche Unicode-Ausgabe für den CLI-Prototyp und Vergleichstests. Die Tray-App verwendet standardmäßig `DirectTextInserter`; `ClipboardTextInserter` bleibt als auswählbarer Vergleichsmodus erhalten.
* **`Inlaut.Core`** (.NET 8):
  * Plattformunabhängige Textlogik (`SharpS`, `VoiceCommands`, `Replacements`, `TextPipeline`). ß-Regeln, Ersetzungen (ß und ss gelten als gleich, unabhängig von der Windows-Sprache) und das Erkennen von Textbausteinen folgen dem Mac, ebenso die ß-Voreinstellung (in der Schweiz und Liechtenstein aus). Den Text eines Textbausteins fügt Windows unverändert ein; der Mac-Editor schneidet Leerzeichen und Zeilenumbrüche am Anfang und Ende ab. Bei Satzzeichen rund um Sprachbefehle und an den Rändern eines Diktats gibt es bewusste oder noch offene Unterschiede. Beide Plattformen prüfen gemeinsame Fälle aus [`TestData/text-pipeline.json`](../TestData/text-pipeline.json), das die bekannten Unterschiede benennt. Aufräumen und Selbstkorrekturen gibt es nur auf dem Mac.

## Regressionstests

- Plattformunabhängige Textprüfung: `dotnet run --project windows/tests/Inlaut.CoreSmoke -c Release`.
- Portable Ablauf-Simulation mit echtem Produktionscode und simulierten Windows-Grenzen: `dotnet run --project windows/tests/Inlaut.SimulationSmoke -c Release`. Umfang und Grenzen stehen in [der Testbeschreibung](tests/Inlaut.SimulationSmoke/README.md).
- Windows-Layoutprüfung (150 Größen- und Beschriftungsänderungen, 30-Sekunden-Watchdog): `dotnet run --project windows/tests/Inlaut.UiSmoke -c Release`.
- Nur auf einem isolierten, interaktiven Windows-Testdesktop: denselben UI-Test mit `-- --paste` starten. Er prüft den eingefügten Text, verzögertes Einfügen in einem separaten Zielprozess, zwischenzeitliches Kopieren und das Ignorieren synthetischer Tasten durch den Diktat-Trigger. Dieser optionale Test benutzt Tastatureingaben und überschreibt die Test-Zwischenablage.

Die UI-Tests können auf macOS nur kompiliert, nicht ausgeführt werden.
