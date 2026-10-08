# Inlaut

A tiny macOS menu bar app for dictation that never leaves your Mac. Hold a key combination, speak, let go — the text appears in whatever text field has the cursor.

- **Local only.** Speech is recognised on this Mac. No account, no cloud, nothing stored.
- **German first.** Uses [parakeet-primeline](https://huggingface.co/primeline/parakeet-primeline), a German fine-tune of NVIDIA Parakeet, which handles technical terms and anglicisms far better than the recogniser built into macOS. A 10-second dictation is text in about 0.3 s on an M3.
- **Instant.** The model (≈ 670 MB, downloaded and checksum-verified once on first start) stays loaded, so dictation starts the moment you press the key. That costs about 900 MB of memory; there is no CPU use while idle and the microphone is only open while you dictate.
- **Replacements.** Fix what the recogniser keeps getting wrong ("Dum" → "DAM").
- **Fallback.** Apple's on-device recogniser (`SpeechAnalyzer`) works without any download and is used until the model is ready.

## Status

Early prototype. Works on Apple Silicon with macOS 26 or later.

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/fetch-sherpa-onnx.sh   # pinned, checksum-verified sherpa-onnx C API into Vendor/
xcodegen generate
xcodebuild -project Inlaut.xcodeproj -scheme Inlaut -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Inlaut.app
```

`project.yml` signs with the maintainer's team; change `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` for your own builds.

## Permissions

- **Microphone** — asked on the first dictation.
- **Accessibility** — needed to paste into other apps (the text goes on the clipboard, a ⌘V is sent, and your previous clipboard comes back). Without it the text stays on the clipboard for a manual ⌘V.

The global shortcut uses Carbon hot keys and needs no permission.

## spike/

Measurements that led to the engine choice (on technical German, Whisper-turbo-german made the fewest errors but needs ~2 GB and invents text from noise; Parakeet came close at half the memory and speed; Apple's recogniser failed most technical terms and ignores custom vocabulary): Apple `SpeechAnalyzer` against [parakeet-primeline](https://huggingface.co/primeline/parakeet-primeline) (sherpa-onnx) and [whisper-large-v3-turbo-german](https://huggingface.co/primeline/whisper-large-v3-turbo-german) (MLX), on the same recordings. `try_parakeet.py` reuses `local_stt.py` from [winidi/dictate](https://github.com/winidi/dictate) (MIT).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE). Model and library licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
