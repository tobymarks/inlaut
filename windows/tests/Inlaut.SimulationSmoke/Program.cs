using Inlaut.App;
using Inlaut.Core;
using Inlaut.Platform.Windows;
using Inlaut.SimulationSmoke;
using Inlaut.UiSmoke;

Dispatcher.Run(async () =>
{
    using var host = new Form();
    await HotkeyCancellationChecks.Run(host);
    await ModelDownloadChecks.Run();

    // Simulated recognizer output -> real text pipeline -> real clipboard
    // insertion orchestration -> delayed target reading the fake OS clipboard.
    // Native Windows has a separate process integration test for this boundary.
    const string previous = "PRIVATE previous clipboard";
    Clipboard.SetText(previous);
    string text = new TextPipeline().ProcessDictation("draussen neue Zeile füsse.");
    const string expected = "draußen\r\nFüße.";
    Task<string>? consumed = null;
    NativeMethods.InputQueue = inputs =>
    {
        if (inputs.Length != 4 || inputs[0].u.ki.wVk != 0x11 || inputs[1].u.ki.wVk != 0x56)
            throw new Exception("Unexpected paste shortcut.");
        consumed = ReadDelayed();
        return (uint)inputs.Length;
    };
    await ClipboardTextInserter.InsertAsync(text);
    if (consumed == null || await consumed != expected || Clipboard.GetText() != expected)
        throw new Exception("Delayed simulated target received old clipboard data.");
    foreach (string format in new[] { "ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory", "CanUploadToCloudClipboard" })
        if (Clipboard.Data.GetData(format) is not MemoryStream data || !data.ToArray().SequenceEqual(new byte[4]))
            throw new Exception("Clipboard privacy flag missing: " + format);

    NativeMethods.InputQueue = inputs => { Clipboard.SetText("new user copy"); return (uint)inputs.Length; };
    await ClipboardTextInserter.InsertAsync(text);
    await Task.Delay(900);
    if (Clipboard.GetText() != "new user copy") throw new Exception("Later copy overwritten.");

    NativeMethods.InputQueue = _ => 0;
    try { await ClipboardTextInserter.InsertAsync(text); throw new Exception("Blocked input accepted."); }
    catch (System.ComponentModel.Win32Exception) { }
    if (Clipboard.GetText() != expected) throw new Exception("Input failure restored private clipboard.");

    Clipboard.SetText(previous);
    try
    {
        await ClipboardTextInserter.InsertAsync(text, new DirectTextInserter.InputTarget(new IntPtr(9), new IntPtr(9)));
        throw new Exception("Changed target accepted.");
    }
    catch (InvalidOperationException) { }
    if (Clipboard.GetText() != previous) throw new Exception("Pre-placement failure changed clipboard.");
    Console.WriteLine("PASS: simulated recognizer -> production text pipeline -> clipboard orchestration -> target delayed 1200 ms; privacy flags, later copy, blocked input and focus failure");
    Console.WriteLine("LIMIT: OS boundaries/audio/ASR are simulated here; Windows CI separately exercises actual WinForms, clipboard and SendInput.");
});

static async Task<string> ReadDelayed()
{
    await Task.Delay(1200);
    return Clipboard.GetText();
}
