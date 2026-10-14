# Windows beta

This is an unsigned, limited-test beta, not a general production release.
The per-user installer requires no administrator rights. Close inlaut before
installing, reinstalling or uninstalling. Portable and installed copies share
the application's single-instance lock and user settings. Installation does not
enable autostart or start microphone recording.

The bundled German FastConformer INT8 model runs locally. Its four files are
SHA-256 verified by Build-Beta.ps1; a changed upstream download fails the build.
Source: https://huggingface.co/csukuangfj/sherpa-onnx-nemo-transducer-stt_de_fastconformer_hybrid_large_pc-int8
Upstream model: https://huggingface.co/nvidia/stt_de_fastconformer_hybrid_large_pc
Model attribution: NVIDIA, FastConformer-Hybrid Large (de), licensed under
CC BY 4.0: https://creativecommons.org/licenses/by/4.0/ . The bundled derivative
is the ONNX-exported, INT8-quantized version distributed by csukuangfj;
inlaut makes no further changes to these model files.
See MODEL_EVALUATION.md for measured alternatives and limitations.

Uninstall through Windows Apps & Features. User settings and diagnostic files
are preserved. Keep the previous installer/portable directory for rollback;
close and uninstall the beta before reinstalling an older version. Do not
install different model families over the same app directory.

Recognized text is retained in memory for the tray command "Letztes Diktat…".
Check for partial insertion before copying it manually. Normal direct input does
not use the clipboard. Clipboard insertion is optional and must be enabled.
Native window/control changes abort insertion, but a focus change between web
editors sharing one native control is not reliably detectable. Multiline input
is supported in native Edit/RichEdit controls; unknown controls reject it rather
than sending Enter shortcuts. Previously queued characters cannot be recalled.

Before broad production release: test Word and the actual Codex field, physical
microphone removal/reconnection, standby/resume and extended everyday use;
validate Windows 11 and additional DPI configurations; arrange trusted code
signing and establish an update/recovery policy. A successful build alone does
not establish these acceptance criteria.

Build on Windows with .NET 8 and Inno Setup 6:

```powershell
./windows/installer/Build-Beta.ps1 -OutputDirectory ./publish/beta -CompilerPath 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe'
```

OutputDirectory must be fresh. An optional ModelDirectory uses a local copy,
subject to the same hashes. DotnetPath can select a portable .NET SDK.
