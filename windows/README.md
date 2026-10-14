# inlaut for Windows (Prototype & Architecture)

Dies ist der native Windows-Zweig von **inlaut**. Ziel ist eine hochperformante, datenschutzkonforme On-Device-Diktier-App für Windows 10/11 ohne Cloud-Zwang.

---

## 1. Architektur im Überblick

Die Windows-Lösung ist modular und nativ in **C# / .NET 8/9** aufgebaut:

* **`Inlaut.Core`** (Plattformunabhängig .NET):
  * Beinhaltet die gesamte Textaufbereitung identisch zur macOS-Version:
    * `VoiceCommands`: „neue Zeile“, „neuer Absatz“, Komma- & Satzende-Logik.
    * `SharpS`: Gezielte `ß`-Regeln für Modelle ohne natives Scharf-S.
    * `Replacements`: Wortgenaue Ersetzungen (`From -> To`), längere Phrasen zuerst.
    * `TextPipeline`: Zentrale Pipeline, die nach jeder Transkription greift.
* **`Inlaut.Platform.Windows`** (Windows-spezifisch):
  * `TextInserter`: Direkte Injektion von Zeichenfolgen über Win32 `SendInput` mit `KEYEVENTF_UNICODE`.
    * **Vorteil gegenüber macOS:** Die Windows-Zwischenablage (Clipboard) wird **nicht** überschrieben oder angetastet!
  * `GlobalHotkey`: Registrierung systemweiter Tastenkürzel (`RegisterHotKey` / Low-Level Hooks).
* **`Inlaut.Cli`** (Test-Harness & Benchmark):
  * Nutzt **`sherpa-onnx`** (`org.k2fsa.sherpa.onnx`) zur Ausführung von NeMo FastConformer / Parakeet Modellen auf der CPU (AVX2/AVX-512) oder per DirectML/CUDA.
  * Misst Audio-Länge, Dekodierzeit, RTF (Real-Time Factor) und testet optional die direkte Text-Injektion.

---

## 2. Schnellstart auf dem Windows-Rechner

### Voraussetzungen
1. **.NET 8 SDK** (oder neuer):
   Kann im Windows-Terminal einfach per WinGet installiert werden:
   ```powershell
   winget install Microsoft.DotNet.SDK.8
   ```
2. **Ein exportiertes ONNX-Modell:**
   Zum Testen kann jedes von `sherpa-onnx` unterstützte NeMo CTC- oder Transducer-Modell verwendet werden (z. B. das deutsche FastConformer-Modell `sherpa-onnx-nemo-fast-conformer-ctc-de-2024-03-18` oder ein Parakeet-ONNX-Export).
   
   Beispiel-Download eines vortrainierten Modells:
   ```powershell
   curl.exe -L -O https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-fast-conformer-ctc-de-2024-03-18.tar.bz2
   tar -xvf sherpa-onnx-nemo-fast-conformer-ctc-de-2024-03-18.tar.bz2
   ```

### Benchmark & Testlauf ausführen

1. Wechsel in das Verzeichnis:
   ```powershell
   cd windows
   ```
2. Führe die CLI mit einer 16 kHz Mono-WAV-Datei aus:
   ```powershell
   dotnet run --project src/Inlaut.Cli -- --model "C:\Pfad\Zum\Modell" --file "C:\Pfad\Zu\test.wav"
   ```
3. **Mit Text-Injektion testen:**
   Wenn du `--inject` anhängst, wartet das Tool 3 Sekunden (damit du z. B. in den Windows Editor / Notepad klicken kannst) und tippt den erkannten und aufbereiteten Text direkt hinein:
   ```powershell
   dotnet run --project src/Inlaut.Cli -- --model "C:\Pfad\Zum\Modell" --file "C:\Pfad\Zu\test.wav" --inject
   ```

---

## 3. Nächste Ausbaustufe: Die WinUI-3 / Tray-App

Für die finale Benutzeroberfläche:
1. **System-Tray-Icon:** Die App läuft diskret im Infobereich der Taskleiste.
2. **Echtzeit-Audio:** Kontinuierliche Audioaufnahme über WASAPI mit Ringpuffer beim Halten der Dictate-Taste.
3. **Mica / Fluent-UI:** Ein schlankes Einstellungsfenster (WinUI 3) für Vokabular, Tastenkürzel und Modellstatus.
