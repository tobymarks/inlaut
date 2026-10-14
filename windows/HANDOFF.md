# Windows handoff — 2026-10-14

Continue on branch `feature/windows-prototype` in `tobymarks/inlaut`.
Current version: **0.6.1-diagnostics.1**. This file describes the work and open
checks from the macOS development session; the source of truth is the code.

## What the user confirmed

- Earlier builds produced a word or two followed by repeated punctuation in Windows Notepad.
  Diagnostics showed normal letter counts and no punctuation runs before insertion.
- Since 0.5.2, whole sentences paste correctly. The user also confirmed the settings
  window remains stable while resizing and changing the trigger key.
- The user wants Windows 11 / Fluent styling throughout the app. Version 0.6.0 introduced
  that styling, but their high-DPI display showed overlapping menu icons/text and HUD
  text/level bars. Version 0.6.1 addresses those overlaps; it is NOT yet user-verified.
- Recognition quality still needs investigation. One 20.4-second take produced no text.
  Metadata alone cannot establish whether the input was speech, silence or a recording issue.

## Current behavior and changes

- Tray app pastes via clipboard + Ctrl+V on the UI STA thread. Previous clipboard formats
  are restored after 750 ms if the sequence number is unchanged. Windows history/cloud
  exclusion formats are set. This remains a timed heuristic, not target-app acknowledgement.
- **Outstanding user requirement:** return to reliable insertion without the clipboard.
  The user copies between apps while dictating and does not want interference. Do not
  describe this requirement as solved. Keep the working clipboard path as a comparison
  while diagnosing/pacing/replacing the CLI's Unicode SendInput path on real Windows.
- Model initialization runs off the UI thread. Overlapping decodes are blocked.
- Trigger timer and callbacks run on the UI thread, outside the keyboard hook. Injected
  events are ignored. Dictation is paused while settings are open.
- Settings retain their stable 560 × 560 logical-pixel client area and one-way table layout.
- Shared WinForms theme: system light/dark/high-contrast colors, Segoe fonts, Windows icon
  font, native title bars/task dialogs. This is NOT WinUI 3 or real Mica.
- Menu glyphs now use actual ToolStrip images with native reserved image slots, rather
  than being painted in the text callback. HUD uses measured text and physical-pixel
  geometry without a Graphics scale transform. New layout metadata includes DPI.
- Removed the destructive repetition filter that could change `100000` to `100`.

## Audio diagnostics (explicitly requested by the user)

Tray → **Hilfe & Diagnose → Testaufnahmen speichern** enables up to ten captures.
Disabled by default, session-only, ends on app exit or manual deactivation.
Local path: `%LocalAppData%\inlaut\diagnostics\captures\<session>\<take>`.
Each take contains `recorded.wav`, `recognizer-input.wav`, `result.json`, and
`metadata.json`. WAVs are PCM16 mono 16 kHz; the prepared file is exactly the samples
passed to the model after silence trimming. JSON preserves raw/processed text, including
empty results, timings and configuration. No automatic upload or deletion.
The ordinary `latest.jsonl` remains metadata-only. Never add transcript/audio to it.
The user authorized this explicit diagnostic capture; ordinary recording remains ephemeral.
Do not commit private audio, transcripts or diagnostic bundles. Ask for intended wording
of misrecognized examples when comparing quality. Do not play audio unexpectedly.

## Start work on Windows

Read this file, `windows/README.md`, `windows/DESIGN.md` and repository instructions.
Use .NET 8 SDK and PowerShell:

```powershell
git switch feature/windows-prototype
git pull --ff-only
dotnet build windows/Inlaut.sln -c Release
dotnet run --project windows/tests/Inlaut.CoreSmoke -c Release
dotnet run --project windows/tests/Inlaut.UiSmoke -c Release
```

For a runnable portable build:

```powershell
dotnet publish windows/src/Inlaut.App/Inlaut.App.csproj -c Release -r win-x64 --self-contained true -o build/windows-local
```

Quit the running tray app before launching another build (single-instance mutex).
The app downloads a missing model on first start; GitHub Actions also bundles the model.
The Windows Build workflow produces `inlaut-windows-app` with executable, model and docs.

## Next checks on actual Windows

1. Inspect actual Windows display scale and test native menu/HUD at that DPI, then 100%,
   150%, 200% where practical, including moving between differently scaled monitors.
   Verify normal/hover/disabled/checked menu items, submenu, dark mode, keyboard focus,
   settings resize and the HUD not stealing editor focus.
2. Use the available Windows computer-control tools if enabled. Discover their documented
   capabilities on that machine; tool availability was not verified from macOS.
3. Enable test captures and record short/long German sentences, pauses, umlauts, numbers
   and technical terms. Compare captured audio, raw text and processed text before
   changing model/preprocessing. Current model is German FastConformer Transducer INT8,
   sherpa-onnx 1.13.8, modified beam search, CPU (2–4 threads in the app).
4. Investigate clipboard-free insertion against Notepad and another target, without
   regressing the currently functioning complete-sentence insertion.

Optional input smoke test on an isolated interactive Windows test desktop:
`dotnet run --project windows/tests/Inlaut.UiSmoke -c Release -- --paste`.
It operates keyboard focus and overwrites the test clipboard; do not run it against
unrelated user work. Normal UI smoke does not record audio or change saved settings.

## Validation already completed on macOS

- Windows app and UI test compile; self-contained win-x64 package publishes.
- Core text preservation, nonoverlap geometry at 100–300% DPI and enlarged text pass.
- Capture writer roundtrips all 65,536 PCM16 values exactly; prepared/empty WAVs and
  Unicode/empty transcripts pass.
- A real existing WAV was run through the actual C# SherpaEngine with capture callback:
  original and prepared sample counts and saved transcript matched the decode result.
- ZIP integrity checked. Native Windows painting, menus and keyboard injection could
  not be executed on macOS. HTML design mockups were illustrations only.
