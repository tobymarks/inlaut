# inlaut for Windows

Native, hochperformante On-Device-Diktier-App für Windows 10 & 11 ohne Cloud-Zwang.

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
  * Sobald du die Tastenkombination erneut drückst, wird das Gesprochene lokal auf deinem Rechner transkribiert, durch die inlaut-Textpipeline bereinigt (Scharf-S-Wiederherstellung, Sprachbefehle, Formatierungen) und **direkt an der Cursor-Position in das aktive Fenster eingetippt** (Word, Browser, Outlook, Teams, Editor...).
  * Deine Windows-Zwischenablage bleibt dabei unberührt!

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
  * `TextInserter`: Direkte Unicode-Tasteninjektion über die Win32-API (`SendInput`), kein Überschreiben der Zwischenablage.
* **`Inlaut.Core`** (.NET 8):
  * Plattformunabhängige Textlogik (`SharpS`, `VoiceCommands`, `Replacements`, `TextPipeline`), identisch zur macOS-Version.
