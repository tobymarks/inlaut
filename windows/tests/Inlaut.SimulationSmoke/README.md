# Portable regression simulation

Run on macOS, Linux or Windows with .NET 10:

```sh
dotnet run --project windows/tests/Inlaut.SimulationSmoke -c Release
```

This project source-links the production `KeyTrigger`, `ClipboardTextInserter`
and `ModelManager`, and references the actual text pipeline. No second copy of
those implementations is maintained. The hotkey and model-download checks also
run against the Windows application in `Inlaut.UiSmoke`.

The portable boundary shims replace the UI dispatcher, clipboard, foreground
window, modifier state and Win32 input queue. Hook events and recognizer output
are simulated. Tests cover shortcut cancellation (including a queued start),
normal trigger completion, text processing and paste consumption delayed beyond
the old 750 ms restoration window. They also exercise a stalled HTTP body,
cancellation, integrity rejection and successful retry against temporary files.

This is not a real microphone/recognition/desktop E2E test. Actual WinForms,
recorder-buffer disposal, clipboard formats and `SendInput` into a separate slow
Windows process run on an isolated Windows runner:

```sh
dotnet run --project windows/tests/Inlaut.UiSmoke -c Release -- --paste --transitions
```

The Windows clipboard test intentionally replaces the test desktop's clipboard.
It is not suitable for running alongside a person's active desktop work.
