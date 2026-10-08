# Inlaut

A tiny macOS menu bar app for dictation that never leaves your Mac. Hold a key combination, speak, let go — the text appears in whatever text field has the cursor.

- **Local only.** Speech is recognised on the device by macOS (`SpeechAnalyzer`, macOS 26+). No account, no cloud, nothing stored.
- **Small.** Under 1 MB on disk, about 20 MB of memory, no CPU use while idle. The microphone is only open while you dictate.
- **German first.** Correct umlauts and ß, numbers as digits, and a list of your own names and terms the recogniser should prefer.

## Status

Early prototype. Works on Apple Silicon with macOS 26 or later.

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
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

Measurements that led to the engine choice: Apple `SpeechAnalyzer` against [parakeet-primeline](https://huggingface.co/primeline/parakeet-primeline) (sherpa-onnx) and [whisper-large-v3-turbo-german](https://huggingface.co/primeline/whisper-large-v3-turbo-german) (MLX), on the same recordings. `try_parakeet.py` reuses `local_stt.py` from [winidi/dictate](https://github.com/winidi/dictate) (MIT).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
