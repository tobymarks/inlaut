# Inlaut — notes for working on this repo

macOS menu bar dictation, fully local. Swift 6, SwiftUI + AppKit, macOS 26+, Apple Silicon. Maintainer: Tobias Marks (talks German; UI strings are German for now, code, comments, commits and issues are English). License GPL-3.0-or-later. Roadmap: GitHub issues on `tobymarks/inlaut`.

## Build and run

```bash
scripts/fetch-sherpa-onnx.sh   # once: pinned, SHA-256-checked sherpa-onnx C API + onnxruntime into Vendor/ (gitignored)
xcodegen generate              # after adding/removing source files; Inlaut.xcodeproj is generated and gitignored
xcodebuild -project Inlaut.xcodeproj -scheme Inlaut -configuration Debug -derivedDataPath build build
pkill -x Inlaut; open build/Build/Products/Debug/Inlaut.app
```

- Signing: `Apple Development: Tobias Marks`, team `7V4K87652E` (project.yml). Keep a stable identity — the Accessibility grant is tied to the signature and bundle ID `de.tobymarks.inlaut`. A Developer ID cert exists for notarized releases (issue #2).
- Crash reports: `~/Library/Logs/DiagnosticReports/Inlaut-*.ips`. Logs: `log show --last 10m --predicate 'subsystem == "de.tobymarks.inlaut"'` (only `notice`/`error` are persisted). Never log dictated text — lengths and timings only.
- Idle check: `ps -o cputime= -p $(pgrep -x Inlaut)` twice, 15 s apart, must not move. `footprint <pid>` for memory (~600–900 MB with Parakeet loaded is expected).

## Website

`site/` is the static site for https://inlaut.de (German, no cookies, no tracking, no third-party requests). Served by Cloudflare Workers static assets in the private Cloudflare account (tobias@familiemarks.com). The domain is registered at INWX, and its nameservers point to Cloudflare. Deploy with `cd site && npx wrangler deploy` (wrangler is logged in via OAuth). The Impressum uses the apollon address with c/o, agreed with the maintainer.

## Git and GitHub

The active `gh` account on this machine is the work account (`tmarks-apollon`); this repo belongs to the private account. Push and use `gh` with that token, without switching the global account:

```bash
GH_TOKEN=$(gh auth token -u tobymarks) git -c credential.helper= -c credential.helper='!gh auth git-credential' push
GH_TOKEN=$(gh auth token -u tobymarks) gh issue list -R tobymarks/inlaut
```

Commits use the private noreply address (already set). Commit messages explain the why.

## Testing without the hotkey

An agent cannot press the shortcut or 🌐 key (synthetic events lack permission) and cannot screenshot. So:
- Engine code: compile the Swift sources into a small CLI with `swiftc -parse-as-library -swift-version 6 -I Vendor/sherpa-onnx/include -L Vendor/sherpa-onnx/lib -Xlinker -rpath -Xlinker Vendor/sherpa-onnx/lib …` and feed WAVs.
- Pure logic (VoiceCommands, Replacements, ShortcutConflicts): same, with a tiny `main.swift`.
- SwiftUI views: render offscreen with `NSHostingView.cacheDisplay` to a PNG and look at it.
- Real recordings of the maintainer's voice live in `spike/takes/` (gitignored — never commit them). `spike/compare.py` records and runs Parakeet, Whisper and Apple side by side (`.venv` with sherpa-onnx, mlx-whisper; models under `~/.local/share/dictate/models/`).
- Then ask the maintainer to try the real flow.

## Architecture

- `AppState` — settings (UserDefaults), engine choice, model download state, dictation flow (start → record → 150 ms trailing audio → finish → voice commands → replacements → paste).
- Engines behind `TranscriptionEngine`/`TranscriptionSession`:
  - `ParakeetEngine` (default) — parakeet-primeline int8 ONNX via sherpa-onnx C API on CPU, 4 threads, kept loaded. Long audio split into 90 s pieces at pauses, quiet audio gained to peak 0.5, empty long pieces retried in 20 s parts (ported from winidi/dictate `local_stt.py`).
  - `AppleSpeechEngine` — SpeechAnalyzer/SpeechTranscriber de-DE; no download, used until Parakeet is ready.
- `ModelStore` — pinned HF revision, per-file size + SHA-256, downloads to `~/Library/Application Support/Inlaut/Models/`, file only renamed into place after the hash matches.
- Triggers: `HotKey` (Carbon `RegisterEventHotKey`, no permission) or `GlobeKeyTrigger` (NSEvent monitors under Accessibility; hold 200 ms = dictate, double tap = hands-free, fn+other key = cancel; key-down monitor only while fn is down).
- `TextInserter` — clipboard + synthetic ⌘V, marks the item transient, restores the old clipboard. Needs Accessibility; without it the text stays on the clipboard.
- `RecordingIndicator` — non-activating NSPanel, bottom centre by default (caret mode optional; Chromium/Electron report no usable caret).
- `ShortcutConflicts` — checks enabled macOS symbolic hot keys; other apps' hot keys cannot be detected (RegisterEventHotKey accepts duplicates, even exclusive). `GlobeKeySetting` reads `AppleFnUsageType` (must be 0 = do nothing for the 🌐 trigger).

## Decisions and measurements (why things are the way they are)

- Engine: on 39 s of technical German, Whisper-turbo-german ≈ 0 errors but ~2.1 GB, 2.6 s and it invents text from noise; Parakeet ≈ 4 errors, 1.2 s, ~900 MB; Apple ≈ 8 errors (DAM→Damm, AWS→ABS), 0.75 s, 19 MB. Apple's `DictationTranscriber` (old dictation) was much worse. Quality matters most → Parakeet default.
- Apple `AnalysisContext.contextualStrings` had no effect on SpeechTranscriber → custom vocabulary was replaced by Replacements.
- sherpa-onnx CoreML provider was >10× slower than CPU (recompiles per input length) → CPU.
- Parakeet-primeline (and Whisper-turbo-german, same author) writes ß as ss — issue #1.
- Swift 6 gotcha: a closure written inside a `@MainActor` method inherits main-actor isolation and traps when called on an audio/realtime thread → build such closures in `nonisolated static` functions (see `Recorder.tap`).
- Mac App Store rejects automatic pasting for dictation apps (2.4.5) → direct distribution first (issues #2, #6).
- Name "Inlaut" chosen after a collision search (Hush, Murmur, Quill, Sotto, Verba … are taken). A formal trademark check (TMview, classes 9/42) is still open — private, not an issue.
