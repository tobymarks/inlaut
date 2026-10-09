# inlaut — notes for working on this repo

Brand name is always written in lowercase: "inlaut", even at the start of a sentence (UI, website, docs, social posts, comments). Technical identifiers keep their existing form (`Inlaut.app`, scheme/target `Inlaut`, `Inlaut.icon`).

macOS menu bar dictation, fully local. Swift 6, SwiftUI + AppKit, macOS 26+, Apple Silicon. Maintainer: Tobias Marks (talks German; code, comments, commits and issues are English). UI strings are written in English in the source; German lives in `Resources/Localizable.xcstrings` (and `InfoPlist.xcstrings` for permission texts). Non-view strings use `String(localized:)`, `EngineError` takes a `String.LocalizationValue`. After adding UI text, build and run `python3 scripts/check-localizations.py`, then add the German entry (xcodebuild does not update the catalog, only the Xcode app does). License GPL-3.0-or-later. Roadmap: GitHub issues on `tobymarks/inlaut`.

## Build and run

```bash
xcodegen generate              # after adding/removing source files; Inlaut.xcodeproj is generated and gitignored
xcodebuild -project Inlaut.xcodeproj -scheme Inlaut -configuration Debug -derivedDataPath build build
pkill -x Inlaut; open build/Build/Products/Debug/Inlaut.app
```

- Signing: `Apple Development: Tobias Marks`, team `7V4K87652E` (project.yml). Keep a stable identity — the Accessibility grant is tied to the signature and bundle ID `de.tobymarks.inlaut`. Release uses Developer ID signing; `scripts/release.sh prepare` archives and exports with nested signatures. `scripts/release.sh notarize` uses the `Inlaut` notarytool Keychain profile, staples, checks Gatekeeper, and packages a signed Sparkle feed. See README for the publishing order.
- Crash reports: `~/Library/Logs/DiagnosticReports/Inlaut-*.ips`. Logs: `log show --last 10m --predicate 'subsystem == "de.tobymarks.inlaut"'` (only `notice`/`error` are persisted). Never log dictated text — lengths and timings only.
- Idle check: `ps -o cputime= -p $(pgrep -x Inlaut)` twice, 15 s apart, must not move. `footprint <pid>` for memory (~50 MB with Parakeet loaded is expected; the Core ML weights live outside the process, ~150 MB system-wide).

## Design

`design/inlaut-brand-kit/` is the current brand master ("Sprachimpuls / Petrol & Mint"); read `README.txt` and `Brand-Guide.html`. UI typography is the native system font on both macOS and web. Run `python3 scripts/sync-brand.py` to sync the kit's colours, template images and web assets. It uses `scripts/outline-brand.swift` to turn the stroked waveform into a filled outline for native Icon Composer materials. `Resources/Inlaut.icon` is the native layered icon, and `Resources/Assets.xcassets` contains adaptive colours plus five distinct monochrome menu states. Keep native glass and the recording indicator's reduced-motion/transparency fallbacks. See `design/README.md` for integration details. The previous `design/build-support/` generator is archived and must not be used for the current brand. Logo and icons retain the existing asset licensing policy (`design/LICENSE-ASSETS.md`).

## Website

`site/` is the static site for https://inlaut.de (German at `/`, English at `/en` with legal notice and privacy translations; no cookies, no tracking, no third-party requests). Keep both languages in step and linked via `hreflang`. Served by Cloudflare Workers static assets in the private Cloudflare account (tobias@familiemarks.com). The domain is registered at INWX, and its nameservers point to Cloudflare. Deploy with `cd site && npx wrangler deploy` (wrangler is logged in via OAuth). The Impressum uses the apollon address with c/o, agreed with the maintainer. hallo@inlaut.de is forwarded by Cloudflare Email Routing to the maintainer's private address. After editing the FAQ (`#fragen`, `/en#faq`), run `python3 scripts/sync-faq-schema.py` so the FAQPage JSON-LD of both pages matches the visible text. AI-generated images (personas) carry the `.ki-badge` ("KI" / "AI"), an alt text starting with "KI-generiertes Bild:" (English: "AI-generated image:") and IPTC `trainedAlgorithmicMedia` XMP.

## Git and GitHub

The active `gh` account on this machine is the work account (`tmarks-apollon`); this repo belongs to the private account. Push and use `gh` with that token, without switching the global account:

```bash
GH_TOKEN=$(gh auth token -u tobymarks) git -c credential.helper= -c credential.helper='!gh auth git-credential' push
GH_TOKEN=$(gh auth token -u tobymarks) gh issue list -R tobymarks/inlaut
```

Commits use the private noreply address (already set). Commit messages explain the why.

## Testing without the hotkey

An agent cannot press the shortcut or 🌐 key (synthetic events lack permission) and cannot screenshot. So:
- Engine code: a small SwiftPM executable depending on `Packages/InlautSpeech` (or FluidAudio directly) that loads the model with `AsrModels.loadLocal` and feeds WAVs; the benchmark harness from #5 lives in `~/Developer/inlaut-spike/fabench`.
- End to end: the Debug build reads `-testAudioFile /path.wav` (launch argument) instead of the microphone. Post synthetic 🌐/fn CGEvents (keyCode 63, `.flagsChanged`, `.maskSecondaryFn`) from a tiny Swift CLI — this shell is Accessibility-trusted — into a fresh TextEdit document and read the text back with osascript. Never play audio: the maintainer often wears Bluetooth earbuds.
- Pure logic (VoiceCommands, Replacements, ShortcutConflicts): same, with a tiny `main.swift`.
- SwiftUI views: render offscreen with `NSHostingView.cacheDisplay` to a PNG and look at it.
- Real recordings of the maintainer's voice live in `spike/takes/` (gitignored — never commit them). `spike/compare.py` records and runs Parakeet, Whisper and Apple side by side (`.venv` with sherpa-onnx, mlx-whisper; models under `~/.local/share/dictate/models/`).
- Then ask the maintainer to try the real flow.

## Architecture

- `DictationLanguage` (Deutsch / English / Deutsch + English) drives Apple's locale, voice commands and the interface language (per-app `AppleLanguages`, applied after a relaunch). `SpeechModel` in `ModelStore.swift` is the pinned model catalogue; a switch downloads and loads the new model while the old one keeps dictating, then deletes the old one unless "Keep both models" is on.
- `AppState` — settings (UserDefaults), engine choice, model download state, dictation flow (start → record → 150 ms trailing audio → finish → voice commands → replacements → paste).
- Engines behind `TranscriptionEngine`/`TranscriptionSession`:
  - `ParakeetEngine` (default) — Parakeet Ultra as Core ML (Preprocessor, Encoder, Decoder, JointDecisionv3) on the Neural Engine via FluidAudio (`Packages/InlautSpeech` wraps it with the NemoTextProcessing trait off). Loaded from our own pinned, checksummed copy with `AsrModels.loadLocal` — FluidAudio's downloader is never used. First load after a download compiles for the Neural Engine (~10–30 s, Apple dictates meanwhile), later loads take ~0.2 s; a take on a resting model records against the reload. ~50 MB app footprint, RTF ≈ 0.008, ~0.01 s CPU per audio second. FluidAudio splits long takes into 15 s windows and rejects audio under 0.3 s (we pad).
  - `AppleSpeechEngine` — SpeechAnalyzer/SpeechTranscriber de-DE; may download system language assets, prepared independently from Parakeet.
- `ModelStore` — pinned HF revision, per-file size + SHA-256, downloads to `~/Library/Application Support/Inlaut/Models/`, file only renamed into place after the hash matches.
- Triggers: `HotKey` (Carbon `RegisterEventHotKey`, no permission) or `GlobeKeyTrigger` (NSEvent monitors under Accessibility; hold 200 ms = dictate, double tap = hands-free, fn+other key = cancel; key-down monitor only while fn is down).
- `TextInserter` — clipboard + synthetic ⌘V, marks the item transient, restores the old clipboard. Needs Accessibility; without it the text stays on the clipboard.
- `RecordingIndicator` — non-activating NSPanel, 12 pt above the physical bottom edge by default (caret mode optional; Chromium/Electron report no usable caret).
- `ShortcutConflicts` — checks enabled macOS symbolic hot keys; other apps' hot keys cannot be detected (RegisterEventHotKey accepts duplicates, even exclusive). `GlobeKeySetting` reads `AppleFnUsageType` (must be 0 = do nothing for the 🌐 trigger).

## Decisions and measurements (why things are the way they are)

- Engine: on 39 s of technical German, Whisper-turbo-german ≈ 0 errors but ~2.1 GB, 2.6 s and it invents text from noise; Parakeet ≈ 4 errors, 1.2 s, ~900 MB; Apple ≈ 8 errors (DAM→Damm, AWS→ABS), 0.75 s, 19 MB. Apple's `DictationTranscriber` (old dictation) was much worse. Quality matters most → Parakeet default.
- Apple `AnalysisContext.contextualStrings` had no effect on SpeechTranscriber → custom vocabulary was replaced by Replacements.
- 2026-10-10 (#5): sherpa-onnx (CPU) replaced by FluidAudio Core ML. On the maintainer's takes and FLEURS, Parakeet Ultra beat primeline (German) and v2 (English) — real mixed 5.9 vs 10.2 % WER, real English 5.5 vs 8.3 %, FLEURS de 4.4 vs 5.7 % — at ~6× speed, ~20× less CPU and ~550 MB less memory. Even the same primeline weights were more accurate as Core ML (FLEURS de 4.5 vs 5.7 %) than as sherpa int8. Only on synthetic TTS mixed sentences primeline stayed ahead. sherpa-onnx's own CoreML provider had been >10× slower than CPU (recompiles per input length).
- Parakeet-primeline (and Whisper-turbo-german, same author) writes ß as ss — issue #1. Ultra writes ß itself; SharpS stays as a harmless safety net.
- Ultra ends salutations and sign-offs before a voice command with a full stop ("Best regards. New line."); VoiceCommands turns a full stop after a short line (≤ 4 words) into a comma.
- Python model conversion (mobius, NeMo, Python 3.10) on macOS 27: old SciPy/cffi wheels fail to load ("__thread_bss has a zero-fill section type, but offset field is not zero"). Zero that section offset in the .so files and re-sign ad hoc (`~/Developer/inlaut-spike/fix_tbss.py`).
- Swift 6 gotcha: a closure written inside a `@MainActor` method inherits main-actor isolation and traps when called on an audio/realtime thread → build such closures in `nonisolated static` functions (see `Recorder.tap`).
- Mac App Store rejects automatic pasting for dictation apps (2.4.5) → direct distribution first (issues #2, #6).
- Name "inlaut" chosen after a collision search (Hush, Murmur, Quill, Sotto, Verba … are taken). A formal trademark check (TMview, classes 9/42) is still open — private, not an issue.

## Updates and validation

- `AppUpdater` wraps Sparkle 2.10.0; daily checks, manual installation, no profiling, signed feed and archives. Disabled in Debug. Checks/relaunches are deferred during dictation.
- Feed: `site/public/updates/appcast.xml` → inlaut.de; archives: public GitHub Releases. Never publish an appcast before the corresponding notarized ZIP is downloadable.
- Website downloads use the signed, notarized drag-to-install DMG. `scripts/release.sh dmg` packages the exported/stapled app without altering the existing Sparkle ZIP or feed. DMGs live separately in `build/release/downloads/<version>-<build>/`; upload the DMG and its `.dmg.sha256` before deploying the website link. Do not replace published archives. See README for the full pipeline and Retina layout verification.
- Sparkle private key stays in Keychain under account `de.tobymarks.inlaut`; do not print or commit it. Notarization profile: `Inlaut` (one-time user setup).
- `xcodebuild -project Inlaut.xcodeproj -scheme Inlaut -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build test` runs the isolated tests. Tests must not touch the general clipboard or microphone.
