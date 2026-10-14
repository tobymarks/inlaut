# Windows handoff — 2026-10-14

Continue on branch `feature/windows-prototype` in `tobymarks/inlaut`.
Current version: **0.6.4-model-preview.1** (separate Parakeet portable trial; 0.6.3 retains the compact model). This file describes the work and open
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

- Windows continuation: the tray defaults to `DirectTextInserter`. Known native
  Unicode Edit/RichEdit fields use EM_REPLACESEL with undo and a 2-second timeout,
  targeting the original control. Read-only, disabled and password fields are
  rejected; multiline text is rejected for single-line native fields.
  Other targets use a worker-thread high-resolution timer with 4 ms waits between Unicode scalars, modifier-release
  timeout, input-field/foreground checks and a nonoverlap gate. No clipboard is
  accessed. The generic packet path rejects multiline text before insertion;
  Unicode newlines were ignored by RichEdit in tests, and Return key events can
  submit chats, so we do not use them. Use the explicit clipboard mode where needed.
- **Known packet-fallback limitation:** a focus change can redirect queued events before
  the next focus check aborts. A prior test reproduced one character in the second field;
  this is an observation, NOT a universal upper bound for slow targets.
  Already inserted text is retained; there is no automatic retry or clipboard fallback.
  Native field replacement cannot redirect text into the newly focused field.
  Metadata records `input-sent` with `native-edit`, `unicode-paced` or `clipboard`.
- The previous clipboard + Ctrl+V path remains selectable via
  **Hilfe & Diagnose → Eingabe per Zwischenablage** (unchecked by default).
  Previous clipboard formats
  are restored after 750 ms if the sequence number is unchanged. Windows history/cloud
  exclusion formats are set. This remains a timed heuristic, not target-app acknowledgement.
- **User requirement under validation:** reliable insertion without the clipboard.
  The user copies between apps while dictating and does not want interference. Do not
  describe this requirement as universally solved. Keep the working clipboard path as a comparison
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

0.6.3 fallback timing: 4 ms waitable timer, without global timer-resolution changes.
TextBox/RichTextBox preserved all 84/1260/3360 UTF-16-unit samples, including emoji
and combining marks. 1260 units took 6.2 s and 3360 units 16.4–16.6 s on this PC.
No queue-drain delay was observed at this pacing. Native replacement, selection,
undo, read-only protection, nonoverlap, focus abort and clipboard preservation passed.
An experimental 1 ms wait queued work faster than RichEdit consumed it (2.9 s
tail on a long sample); it is deliberately not shipped. SendInput completion is
still not proof of target delivery. A separate WebView2 test passed textarea and
contenteditable equality for 72/1094/2919 UTF-16 units; ~5.9–6.0 s for 1094 units.
The corpus avoids trailing spaces: Chromium turns a trailing ordinary space into
NBSP in contenteditable (observed in an earlier test, not a lost character).
Actual Codex field verification remains open; the isolated web test is not that app.

Model selection is now explicitly requested: compare German quality, disk size,
peak working set and latency before changing the default. The new opt-in
`Inlaut.ModelBenchmark` console project produces per-clip text/timing and normalized
word error rate from a local corpus (`expected.json`, `test-1.wav` etc.). Run each
model in a fresh process. Synthetic speech is only a smoke test, not a sufficient
basis for a claim of best real-world recognition quality.
See [MODEL_EVALUATION.md](MODEL_EVALUATION.md) for measured three-model results on
20 public human clips, corpus limitations, the separate Parakeet quality trial,
and the still-open broader model/default decision.

Windows 10 Enterprise 22H2 / 192 DPI validation on 2026-10-14:
- New direct path preserved sentences, umlauts, 100000, supplementary Unicode,
  combining accents and line breaks in WinForms TextBox and RichTextBox.
- Native Notepad received the fixed direct-input sample with both line breaks;
  clipboard sequence number stayed unchanged.
- Three local synthetic German WAVs (Microsoft Hedda, PCM16 mono 16 kHz) passed
  SherpaEngine → default TextPipeline → direct input → RichTextBox equality.
  All words matched the references; one internal sentence period was omitted.
  This is a tiny synthetic corpus, not a microphone/general-quality benchmark.
- Old burst insertion also passed in the isolated fields. Original punctuation
  corruption was NOT reproduced, so its root cause remains unconfirmed.
- 150 settings resizes and menu image/text separation passed. Native DrawToBitmap
  renders were visually inspected at 200%; these are control renders, not desktop
  screenshots. Menus now have measured widths, 40 logical-pixel rows, aligned icon,
  label and shortcut columns, a right-aligned arrow and a themed checkmark.
- Desktop capture repeatedly timed out. Actual hover, monitor transitions and
  other scaling/theme combinations still need verification.

`windows/tests/Inlaut.InputSmoke` is an opt-in interactive input test. It types
only into its own two fields by default and does not modify clipboard contents.
It records exact text comparisons and the bounded focus-change limitation.
`--external` waits up to 90 seconds for Notepad to become foreground and injects
a fixed sample; use only with a disposable, empty editor. An `external-request.txt`
beside the executable enables the same mode for launchers without argument support.
An `audio-request.json` beside the executable enables synthetic audio tests with
`Model`, `Audio` (test-1.wav etc.) and `Expected` string-array fields. Results stay
next to the test executable. Never commit real user recordings or transcripts.

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

## 0.7.0-beta.1 — installer and original-target protection (2026-10-14)

The app captures the native window/control at recording start and revalidates it
before both direct and optional clipboard insertion. This closes the previous
wrong-target window during recognition. It does not distinguish DOM editors with
one native HWND, nor retract queued keyboard input. Starting from the tray may
capture the tray as target; use the configured dictation key in the destination.

The tray's "Letztes Diktat…" keeps the last recognized text in memory for explicit
recovery after failures. No automatic retry, clipboard write or transcript file
is added. Open review windows retain their text until closed/app exit.

`installer/Build-Beta.ps1` builds a self-contained x64 application and per-user
Inno Setup installer, using the compact FastConformer model with four fixed
SHA-256 hashes. The CI compiler download is also hash-pinned. The beta has its
own stable installer identity; app mutex, user settings and diagnostics are shared
with portable builds. The installer refuses to install/uninstall while the app
runs, and does not force-close it. See installer/BETA.md for build and rollback.

Validation on Windows 10 / 192 DPI: CoreSmoke passed; 22 InputSmoke checks passed,
including both original-target rejection paths, long Unicode input, native
multiline, undo, readonly, overlap and unchanged clipboard. UI smoke passed 150
settings resizes, menu icon/text layout and the new readonly recovery view at its
DPI-adjusted minimum size. The focus-change idle test observed one already queued
character in the second field: this is a measured case, not a universal bound.

`--external-word` (or word-request.txt) prepares an opt-in long Word test; activate
only a verified empty disposable document. The harness checks the foreground
process, not whether a document is disposable. Actual Word validation remains
open: computer control returned "coordinate input geometry is unavailable".
The actual Codex field is also unverified. Do not infer these from isolated tests.

General release gates still open: trusted signing, Windows 11/multi-monitor DPI,
physical microphone unplug/reconnect, standby/resume, extended everyday use,
actual target-app checks, and a supported update/rollback policy. NuGet security
advisory retrieval was unavailable (NU1900); compilation and tests succeeded,
but no successful dependency advisory scan is claimed.

## Office acceptance tests and Excel fix — 0.7.0-beta.2 (2026-10-14)

Actual desktop applications were tested with DirectTextInserter, not by writing
Office document contents through an API. Word received 1,259 characters; the UI
readback matched except for its 15 sentence-initial inlaut→Inlaut corrections.
PowerPoint received 83 characters in 466 ms and another 1,260 in 6,282 ms. Its
1,343-character title readback matched exactly. The user activated the title
placeholder because computer-control clicks failed; insertion itself was tested
programmatically. The clipboard was unchanged in all cases.

Excel exposed a standard Edit control in cell-edit mode. EM_REPLACESEL returned
success (86 ms), but after Enter/save the XLSX worksheet was empty. The inserter
now excludes EXCEL from the native-edit path. Repeating with unicode-paced
(83 characters, 493 ms) persisted the exact string in A2, verified directly in
Excel's saved sharedStrings.xml and sheet1.xml; clipboard unchanged.

InputSmoke now accepts office-request.json with Process (WINWORD, POWERPNT,
EXCEL or notepad) and Text. This opt-in helper requires a verified disposable
active text field. Its sent result is NOT proof of delivery: separately read
back the app/document. No microphone or recognition test is implied by these
input-only checks. Office multiline, other placeholders/field types, Excel
outside cell-edit mode and other Office versions remain unverified.
