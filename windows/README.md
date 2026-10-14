# inlaut for Windows

Native, hochperformante On-Device-Diktier-App für Windows 10 & 11 ohne Cloud-Zwang.

Für die Fortsetzung der Entwicklung direkt unter Windows: [HANDOFF.md](HANDOFF.md).

## Testversion 0.6.1-diagnostics.1

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
Diese Version verwendet deshalb einen einzelnen Einfügevorgang (Strg+V).
Die Zwischenablage wird vorübergehend genutzt und danach wiederhergestellt,
sofern zwischenzeitlich nichts Neues kopiert wurde. Der Diktattext wird für den
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

1. Lade das fertige **`inlaut-windows-app.zip`** herunter (z. B. aus den GitHub Actions Artefakten oder dem Release).
2. Entpacke das ZIP in einen beliebigen Ordner.
3. Starte **`Inlaut.exe`** per Doppelklick:
   * Die App startet direkt im Infobereich (System Tray) unten rechts in der Taskleiste.
   * Das deutsche On-Device Sprachmodell ist bereits im Ordner `models/` enthalten und wird sofort geladen.
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
  * Die vorherige Zwischenablage wird nach dem Einfügen wiederhergestellt, solange nichts Neues kopiert wurde.

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
  * `TextInserter`: Unicode-Eingabe für den CLI-Prototyp. Die Tray-App verwendet `ClipboardTextInserter` mit einem Strg+V-Befehl und Wiederherstellung der Zwischenablage.
* **`Inlaut.Core`** (.NET 8):
  * Plattformunabhängige Textlogik (`SharpS`, `VoiceCommands`, `Replacements`, `TextPipeline`), identisch zur macOS-Version.

## Regressionstests

- Plattformunabhängige Textprüfung: `dotnet run --project windows/tests/Inlaut.CoreSmoke -c Release`.
- Windows-Layoutprüfung (150 Größen- und Beschriftungsänderungen, 30-Sekunden-Watchdog): `dotnet run --project windows/tests/Inlaut.UiSmoke -c Release`.
- Nur auf einem isolierten, interaktiven Windows-Testdesktop: denselben UI-Test mit `-- --paste` starten. Er prüft den eingefügten Text, Zwischenablage-Wiederherstellung, zwischenzeitliches Kopieren und das Ignorieren synthetischer Tasten durch den Diktat-Trigger. Dieser optionale Test benutzt Tastatureingaben und überschreibt die Test-Zwischenablage.

Die UI-Tests können auf macOS nur kompiliert, nicht ausgeführt werden.
