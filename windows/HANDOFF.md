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

## Multiline Office validation and compact feedback — 0.7.0-beta.3

Empty recognition now shows "Keine Sprache erkannt" in the nonactivating HUD
for 2.5 seconds, rather than a Windows notification. Recordings below 100 ms
show "Zu kurz aufgenommen". Model preparation also uses the HUD. A dedicated
message timer is cancelled by recording/transcribing/hide/dispose; the stop
handler preserves the final message instead of hiding it immediately in finally.
UiSmoke covers timeout and immediate subsequent recording/transcription. CoreSmoke
also checks German new-line/new-paragraph command conversion. Other actionable
errors retain their previous notifications; no error diagnostics are suppressed.

Actual Office multiline tests used the EXISTING OPT-IN CLIPBOARD MODE. No automatic
clipboard fallback or preference change was introduced. A sample with two lines,
a blank line and a final line was checked:
- Word readback exactly matched (867 ms send duration).
- PowerPoint title readback matched after converting U+000B soft line breaks to
  LF (925 ms). This establishes line breaks, not native paragraph objects.
- Excel in F2 cell-edit mode persisted all lines in one cell A3, verified in
  its saved XLSX sharedStrings.xml and sheet1.xml (881 ms).

Direct multiline Office input remains rejected. In Excel, enter cell-edit mode
before using clipboard dictation; otherwise paste can distribute lines into
multiple cells. Clipboard sequence numbers necessarily changed during these
runs. The existing restoration logic ran, but these observations do not prove
arbitrary rich clipboard formats restored perfectly. These are input tests with
fixed text, not microphone-to-Office recognition tests.

InputSmoke office-request.json now optionally accepts UseClipboard=true, and
records the target control class. Default remains false. Run only in a verified
isolated text field and independently compare the resulting document contents.

## Audio-to-Office and repeat/guard tests — 2026-10-14

Test-only changes; installed application remains 0.7.0-beta.3.
InputSmoke now supports reliability-request.json with Model, Audio and Cycles
(default 100; 0 runs guard checks only). GenerateReliabilityAudio.ps1 -Destination
<folder> generates the six WAV fixtures using Microsoft Hedda Desktop, 16 kHz
mono PCM. Run on Windows with System.Speech and that voice installed. Publish
InputSmoke, place the request beside the executable, then activate its isolated
window. Do not type or switch applications during the automated guard checks:
they synthesize Shift down/up (released in finally), cancellation and focus changes.
The request has priority over audio-request.json and office-request.json; remove
it before running Office tests. Results are incrementally saved beside the exe.

100 cycles through one loaded INT8 recognizer (2 CPU threads) completed in 140 s:
17 short sentences, 17 spoken line/paragraph-command samples, 17 ~77 s samples,
17 ten-second silences, 16 fifty-millisecond silences, 16 low-amplitude noise
samples (seed 17, PCM values -30..30). All 51 speech results were stable across
repeats and matched the inserted field text; all 49 negative samples were empty.
This is not a representative accuracy benchmark: output equality checks transport,
repeat equality checks stability, and noise here is below the silence threshold.
The 50 ms sample is silence, not clipped speech. Maximum decode times were 0.56 s,
0.60 s and 7.63 s respectively. No microphone capture or physical hotkey tested.

Private bytes: 259 MiB minimum, 1328 MiB after first long sample, 1360 MiB maximum,
1348 MiB at completion. Maximum working set 1129 MiB. No unbounded growth observed
in this 140-second run; this does NOT establish leak freedom or low memory use for
long dictations. Long-audio memory remains a production optimization candidate.

Guard checks passed: cancellation before input (0 chars), cancellation after
200 ms (23 queued chars delivered), subsequent insertion succeeds; changed target
rejects direct AND clipboard input before touching a field; held Shift delays
input until release; Shift during paced input aborts (31 chars delivered), then
subsequent insertion succeeds. Clipboard sequence unchanged in isolated tests.
Queued input is not retractable, so partial delivery on interruption is expected.

OfficeRequest additionally accepts AudioFile and Model. It captures the target
BEFORE recognition and passes that target through both insertion methods. The
same spoken command sample was recognized, processed and pasted through the
existing opt-in clipboard path into the owned Word, PowerPoint and Excel test
files. Global clipboard preference remains false. Independent readback confirmed:
- Word: exact appended result, with one additional automatic separating space.
- PowerPoint title: exact appended result with one separating space and U+000B
  soft line breaks normalized to LF. Native paragraph semantics not established.
- Excel: first attempt rejected a changed target. Repeat with active F2 cell edit
  persisted the entire exact result in A5; verified sharedStrings and worksheet
  XML after saving. Existing A2/A3 were preserved, A4 remained empty.
This validates file-audio -> recognizer -> text pipeline -> Office, not microphone
or hotkey capture. Multiline Office still requires opt-in clipboard mode; Excel
requires cell-edit mode. Arbitrary rich clipboard format preservation unverified.

## Handoff to macOS and release work — 2026-10-14

Windows session is complete for this test round; no further automated run is
needed merely to repeat passing checks. Installed Windows version remains
0.7.0-beta.3, an unsigned limited-test beta, NOT a production release.
Test code and results through the reliability round are committed at 7cc9da9.

The user subsequently confirmed that longer real microphone dictations work
well on this Windows machine. This is a subjective hardware-path confirmation,
not a measured accuracy score or a full microphone/hotkey regression suite.
No private microphone recordings or dictated content are added to the repository.

The transition investigation executed ten cases against Windows TextPipeline.
Five desired corrections are absent: spacing/capitalization after sentence end,
capitalization after an existing space/newline, spacing for sentence continuation,
and repairing a missing separator within a recognized string. Correctly formatted
text, a decimal number, a domain, an abbreviation and spoken paragraph commands
were preserved. Concatenation with existing text was simulated; these were not
additional native UI tests. Production behavior has NOT been changed.

Cross-platform follow-up is tracked in issue #20:
https://github.com/tobymarks/inlaut/issues/20
It contains synthetic examples, acceptance criteria, shared Swift/C# test corpus
requirements, links to #16/#17, and transferable robustness/performance checks.
macOS TextPipeline/TextInserter were inspected and do not receive preceding-cursor
text context; macOS behavior has NOT been tested from this Windows machine.
Keep verified Windows findings distinct from pending macOS validation.

Next session on the Mac:
1. Fetch feature/windows-prototype and read this handoff and #20. Inspect current
   main/branch divergence before integrating; do not assume the prototype branch
   is already the final macOS release base.
2. Run physical microphone/hotkey and two-take boundary checks in native and
   browser fields, including caret movement, selection replacement, existing
   whitespace, punctuation, line/paragraph commands and technical strings.
3. Implement applicable shared behavior with the same expected test cases on
   both platforms; keep OS-specific input and signing mechanisms separate.
4. Follow the existing README release procedure and scripts/release.sh on the
   maintainer's Mac: build/test the exact intended release source, Developer ID
   signing, accepted notarization, stapling/Gatekeeper checks, exported-app smoke
   test and previous-version update test, then GitHub artifacts and signed feed.
   These release steps are pending; no signing, notarization or publication was
   performed during this Windows session.

Windows follow-up before general availability: actual Codex field compatibility
and paced output, physical microphone disconnect/reconnect, sleep/resume, Windows
11 and additional real DPI configurations, extended use, long-audio memory,
trusted Windows signing and update/rollback policy. Existing limits remain:
multiline Office requires opt-in clipboard; Excel requires cell edit; DOM fields
sharing one native control are not reliably distinguished; queued characters
cannot be recalled; arbitrary rich clipboard restoration is not fully verified.

Release assessment: suitable as a candidate for a clearly labelled, limited
Windows public beta to collect early-user feedback, not a stable/general release.
Before linking it from the website, verify the exact downloadable installer and
checksum, provide installation/rollback and feedback instructions, and disclose
unsigned status (possible Windows launch warnings), supported test environment,
Office multiline requirements and known input/formatting limits. Windows signing
remains open and is independent of macOS Developer ID/notarization. This assessment
is not a claim that publication, final download verification or signing is done.

## Tray icon fix and settings UX review — beta.4

Fixed clipping by fitting actual glyph outlines into a padded bitmap instead of
using font em size as image bounds. Menu layout now runs after current status,
recording icon and shortcut updates. UiSmoke passed: nine glyphs at seven sizes
(100–300%) have visible ink with transparent outer borders; image/text separation,
150 settings resizes, status timer and recovery-view checks passed. Native main
and submenu renders visually inspected at this machine's 200% DPI. Actual mixed-
monitor placement remains unverified. No recognition/input behavior changed.

See UX_REVIEW.md for the heuristic settings audit, Mac parity matrix and priorities.
The audit identifies missing input-method controls, persisted voice-command/ß
switches, microphone/model status, device selection, key-conflict feedback and
save-error handling. Existing capabilities and future backend work are separated.
Settings expansion is proposed, not implemented in beta.4.

## Settings, microphone selection and opt-in crash reports — beta.5

Implemented the Windows settings follow-up from #21: five grouped tabs, explicit
Save/Close with draft isolation and discard warning, atomic settings replacement,
visible save/load errors, constrained key selection, hold/toggle/combined modes,
direct/clipboard input, voice commands, German ß correction, microphone selection
by stable endpoint ID, 30-second maximum non-retaining level test, active model
information, literal replacements, whole-dictation snippets, Mac-compatible JSON
import/export/merge, indicator top/bottom, optional short start/end tones and
per-user autostart. No preference is enabled automatically during upgrade.
Autostart registry entry is removed by uninstall; settings remain preserved.

Audio capture uses WASAPI device selection and converts native device samples to
16 kHz mono before recognition. Optional diagnostic captures therefore represent
that converted recognizer input, not an untouched native device-format recording.
Default endpoint is resolved at every start; unavailable explicit devices fail
visibly, without silently switching microphones. A device error ends the recording
with an actionable error. Physical unplug/replug remains unverified.

Text rules use the Mac lower-camel-case replacements/snippets JSON schema. Imports
merge into an unsaved draft and reject invalid/duplicate normalized phrases.
Windows validation is stricter than the Mac's permissive empty-entry filtering.
Snippets match the whole normalized phrase and preserve their literal whitespace;
replacement text is now literal, including dollar signs. Existing Office multiline
constraints remain. No language/engine picker, Apple Intelligence correction,
automatic updater or between-dictation spacing fix is implied by these settings.

New local crash handling and explicit report handoff are described in
CRASH_REPORTS.md. There is no automatic transmission. The initial report preview
is local; a separate confirmation discloses transfer to GitHub when opening a
prefilled issue. Final public submission is user-controlled in the browser.

Validation on this Windows machine:
- UiSmoke real controls -> save -> reload -> pipeline options/rules passed.
  Actual multiline snippet dialog was populated and saved; import/export,
  malformed import isolation, write-failure rollback and corrupt-file preservation
  passed. Tests use isolated settings files, not the user's preferences.
- Synthetic speech -> sample conversion -> actual recognizer -> enabled command
  processing/replacement -> actual native text field matched exactly.
- Physical default and explicit endpoint recording, non-retaining preview,
  nonexistent endpoint rejection and restart recovery passed. No captured speech
  from these hardware probes was saved.
- Actual HKCU autostart registration/readback/removal passed, restoring the prior
  registration in finally. Actual login is not tested. Short tones were invoked;
  audibility across output devices remains a manual check.
- Hold, toggle, double-tap and repeat suppression state-machine tests passed;
  no physical shortcut injection implied. Actual top/bottom HUD positioning,
  150 settings resizes, menu/HUD/recovery regression checks passed.
- Isolated clean/forced/fault child-process exits produce the correct next-start
  report state; message/path redaction, defer/discard, corrupt/unwritable marker
  handling and large-URL fallback tested. No report was sent.
- CoreSmoke passed. Native UI renders at 200% were visually inspected, including
  tabs, the multiline editor and crash preview; real mixed-monitor DPI remains open.

Before broader rollout: physical unplug/replug and sleep/resume, longer everyday
use of the new recorder, actual login, Windows 11, large text/high contrast and
mixed-monitor checks; signing/update policy and #20 transition work remain open.

## Signed-update preparation and transition regression — beta.6 (2026-10-15)

User selected SignPath.io for Windows signing. Implemented a daily opt-in update
check and manual check, beta/stable channels with beta-to-final promotion, bounded
HTTPS feed/download, progress/cancellation, SHA-256 and Authenticode checks, exact
installed-certificate trust, and a separately built single-file helper that waits
for clean app exit, verifies again, installs to the same directory and restarts.
No installation during recording/transcription or while settings are open. No
background download/install, no telemetry and no crash-report upload. See UPDATES.md
for the protocol, signing order, feed generation and certificate-rotation caveat.
New-UpdateManifest.ps1 refuses unsigned or mismatched packages. No production feed,
website deployment, signed artifact or public release has been published.

The updater's complete successful signed upgrade remains a release gate: this
machine currently has unsigned development builds. Sign app and helper, package,
then sign installer with the same SignPath certificate; test two signed versions
before website rollout. Signature rejection is intentional, not bypassed for tests.
Tests cover semantic versions (including beta.9/beta.10), beta-to-final, channels,
downgrade rejection, invalid/oversized feeds, 404/offline, download/cancellation,
untrusted redirects, existing-file preservation, size/hash mismatches, unsigned
package/app rejection and busy UI gating. The helper builds independently. Real
installer failure/restart and power-loss recovery still need signed qualification.

Further native transition testing uses two real insertions in an isolated RichTextBox,
not just string concatenation. It uncovered leading/trailing spoken line/paragraph
commands being stripped and explicit punctuation disappearing around short lines.
Fixed Windows VoiceCommands/TextPipeline trimming and punctuation handling; pure
line/paragraph commands now reach insertion. Direct multiline input remains limited
to native editors; Office/web paths still need the existing clipboard option.
15 native cases plus selection replacement and moved-cursor probes are covered.
Four desired context corrections remain open in #20: separation/capitalization
after a sentence, capitalization after a space/newline, and continuation spacing.
No guesses are made from stale previous dictations or shared browser window handles.

Mac transfer: Sources/VoiceCommands.swift currently trims .whitespacesAndNewlines
and removes the final period from short lines (code inspection only). Reuse the
synthetic CoreSmoke/TransitionChecks cases on Mac and adapt those behaviors there;
macOS code has not been changed or run in this Windows session.

Website German and English privacy text now distinguishes local normal dictation,
last-dictation memory, stored rules, optional local test captures, local crash reports,
explicit GitHub handoff/public posting, update-check/download connection metadata,
and Windows certificate validation. This is a source change, not a live deployment
or a claim of completed legal review.

## Modal update-consent fix — beta.7 (2026-10-15)
User reported roughly thirty repeated update-consent dialogs. Root cause: the timer
reentered its handler through MessageBox's nested message loop before the old
checking flag was set. A UI-thread gate now covers the entire consent/save/network
operation, including early returns and exceptions. Regression exercises a real
modal Form with repeated 20 ms WinForms timer ticks, then an async continuation;
only one operation enters and the gate releases after completion/failure. UiSmoke
passed. The affected installed process was stopped to close the dialog stack;
no update preference was silently enabled or changed.
