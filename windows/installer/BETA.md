# Windows beta

This is the public unsigned beta 0.7.0-beta.9, not a general production release.
Download only from https://inlaut.de/windows (German) or
https://inlaut.de/en/windows (English), which link to the project's GitHub release.
Windows may display SmartScreen ("Windows protected your PC") or an unknown
publisher warning because the installer and app are not digitally signed.
If offered, "More info" → "Run anyway" lets you choose to install this specific
download. Only do this if you intentionally obtained it from the official page.
Smart App Control or organization policies may block installation entirely.
Do not disable system-wide protection to install this beta.

Updates are manual: download the next installer from the website and close
inlaut before running it. The in-app updater requires trusted signatures and
cannot update this unsigned beta. No Windows update feed is published for it.

Known beta limitations: quiet speech can be cut off; spacing and capitalization
between separate dictations may need correction. See issues #20 and #23.

The per-user installer requires no administrator rights. Close inlaut before
installing, reinstalling or uninstalling. Portable and installed copies share
the application's single-instance lock and user settings. Installation does not
enable autostart or start microphone recording.

The bundled German and English FastConformer INT8 models run locally. All files are
SHA-256 verified against windows/models.json by Build-Beta.ps1 and before loading; a changed upstream download fails the build.
Source: https://huggingface.co/csukuangfj/sherpa-onnx-nemo-transducer-stt_de_fastconformer_hybrid_large_pc-int8
Upstream model: https://huggingface.co/nvidia/stt_de_fastconformer_hybrid_large_pc
Model attribution: NVIDIA, FastConformer-Hybrid Large (de), licensed under
CC BY 4.0: https://creativecommons.org/licenses/by/4.0/ . The bundled derivative
is the ONNX-exported, INT8-quantized version distributed by csukuangfj;
inlaut makes no further changes to these model files.
English model: NVIDIA FastConformer-Hybrid Large (en), CC BY 4.0.
Upstream: https://huggingface.co/nvidia/stt_en_fastconformer_hybrid_large_pc
ONNX INT8 export: https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-fast-conformer-transducer-en-24500-int8.tar.bz2
Export provenance: https://github.com/k2-fsa/sherpa-onnx/blob/master/scripts/nemo/fast-conformer-hybrid-transducer-ctc/run-transducer-non-streaming.sh
inlaut redistributes the exported files without further modification.

Choose dictation language and interface language separately in Settings.
Language changes require restarting inlaut. Both models ship in the installer;
only the selected one is loaded. Mixed-language dictation is not supported.
Existing settings retain German. New installations default to English unless
Windows uses German. The installer supports both languages.
English is beta functionality covered by automated checks, without a new
physical Windows-device acceptance test.

See MODEL_EVALUATION.md for measured alternatives and limitations.

Uninstall through Windows Apps & Features. User settings and diagnostic files
are preserved. Keep the previous installer/portable directory for rollback;
close and uninstall the beta before reinstalling an older version. Do not
install different model families over the same app directory.

Recognized text is retained in memory for the tray command "Letztes Diktat…".
Check for partial insertion before copying it manually. Normal direct input does
not use the clipboard. Clipboard insertion is optional and must be enabled.
In that mode, dictation replaces the previous clipboard contents and stays there
until something else is copied, including when the target does not accept the
paste. There is no timed restoration that could paste old content into a slow
application. Windows clipboard history and cloud-sync exclusion flags remain set.
Native window/control changes abort insertion, but a focus change between web
editors sharing one native control is not reliably detectable. Multiline input
is supported in native Edit/RichEdit controls; unknown controls reject it rather
than sending Enter shortcuts. Previously queued characters cannot be recalled.

Word, PowerPoint and Excel input/recognition checks are recorded in HANDOFF.md;
multiline Office tests used opt-in clipboard insertion, with Excel in cell-edit
mode. The user also reported successful longer physical microphone dictations.
This does not establish complete app compatibility or measured speech accuracy.

Before broad production release: complete actual Codex-field compatibility,
physical microphone removal/reconnection, standby/resume and extended everyday use;
validate Windows 11 and additional DPI configurations; arrange trusted code
signing and establish an update/recovery policy. A successful build alone does
not establish these acceptance criteria.

Build on Windows with .NET 8 and Inno Setup 6:

```powershell
./windows/installer/Build-Beta.ps1 -OutputDirectory ./publish/beta -CompilerPath 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe'
```

OutputDirectory must be fresh. An optional ModelDirectory uses a local copy,
subject to the same hashes. DotnetPath can select a portable .NET SDK.

Beta.5 settings include input method, voice commands, ß correction, microphone
selection/test, own replacements/snippets with Mac-compatible JSON import/export,
trigger mode, indicator position, sounds and optional per-user startup. Changes
apply after Save; upgrade does not enable these optional preferences. The level
test does not retain audio. Captured device audio is converted to 16 kHz mono.

After unexpected termination, a local technical report can be reviewed/discarded
or saved. Nothing is automatically sent. Preparing a GitHub issue asks for
explicit transfer consent; the final public submission is in the browser.
Reports contain no audio, dictated text, text rules or exception messages/paths.
See CRASH_REPORTS.md for details. Normal diagnostics remain metadata-only.

### Beta.6 updates
Windows can check for updates daily after you enable it, or manually through Help.
Downloads/installations require a click. Secure in-app upgrades require a signed
app, update helper and installer. This public unsigned beta intentionally refuses
in-app update installation; download updates from the website instead. See
UPDATES.md for future signed release qualification and the beta-to-stable procedure.
Spoken line/paragraph commands now retain leading/trailing breaks and explicit
punctuation. Automatic spacing/capitalization using preceding cursor text remains
under investigation; a new native two-dictation test suite documents the limits.
