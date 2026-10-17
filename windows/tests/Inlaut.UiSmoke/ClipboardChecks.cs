using System.ComponentModel;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using Inlaut.App;
using Inlaut.Platform.Windows;

namespace Inlaut.UiSmoke;

// Opt-in only: uses the real clipboard/keyboard on an isolated Windows desktop.
internal static class ClipboardChecks
{
    private const string Expected = "Diktat statt alter Zwischenablage: Grüße, Straße, 100000!\nZweite Zeile. 😀";
    private static readonly string[] PrivateFormats = [
        "ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory", "CanUploadToCloudClipboard"
    ];

    public static async Task Run(Form host)
    {
        using var editor = new TextBox { Multiline = true, Dock = DockStyle.Fill };
        host.Controls.Add(editor); host.Activate(); editor.Focus();
        await Task.Delay(100);
        var target = DirectTextInserter.CaptureTarget();
        Assert(target.Window == host.Handle && target.Control == editor.Handle, "Clipboard test target is not focused.");
        Clipboard.SetText("original clipboard sentinel");
        uint previousSequence = NativeMethods.GetClipboardSequenceNumber();
        bool failed = false;
        try { await ClipboardTextInserter.InsertAsync(Expected, new DirectTextInserter.InputTarget(IntPtr.Zero, IntPtr.Zero)); }
        catch (InvalidOperationException) { failed = true; }
        Assert(failed && Clipboard.GetText() == "original clipboard sentinel" && NativeMethods.GetClipboardSequenceNumber() == previousSequence,
            "Failure before clipboard placement changed existing contents.");

        // Simulate the native failure boundary, preserving real clipboard/focus
        // behavior. Even a zero/partial SendInput result is not paste acknowledgement.
        foreach (uint accepted in new uint[] { 0, 2 })
        {
            Clipboard.SetText("old content must never return");
            int calls = 0;
            failed = false;
            try
            {
                await ClipboardTextInserter.InsertAsync(Expected, target, keys =>
                {
                    calls++;
                    Assert(HasPrivateFormats(), "Clipboard privacy formats missing before input injection.");
                    if (calls == 1) return accepted;
                    Assert(keys.All(k => (k.u.ki.dwFlags & NativeMethods.KEYEVENTF_KEYUP) != 0), "Failure cleanup emitted key-down events.");
                    return (uint)keys.Length;
                });
            }
            catch (Win32Exception) { failed = true; }
            Assert(failed && calls == 2, "Blocked/partial input was not reported and released.");
            await Task.Delay(850);
            Assert(Clipboard.GetText().ReplaceLineEndings("\n") == Expected && HasPrivateFormats(), "Input failure restored old clipboard content.");
        }

        // A user/application copy immediately after placement wins, including
        // the native error path. There must be no later cleanup/restore write.
        foreach (uint accepted in new uint[] { 0, 4 })
        {
            int calls = 0;
            try
            {
                await ClipboardTextInserter.InsertAsync(Expected, target, keys =>
                {
                    if (++calls == 1) { Clipboard.SetText("new concurrent copy"); return accepted; }
                    return (uint)keys.Length;
                });
                Assert(accepted == 4, "Blocked input was accepted.");
            }
            catch (Win32Exception) when (accepted == 0) { }
            await Task.Delay(850);
            Assert(Clipboard.GetText() == "new concurrent copy", "Concurrent clipboard copy was overwritten.");
        }

        using var trigger = new KeyTrigger(host, (uint)NativeMethods.VK_LCONTROL) { Mode = "toggle" };
        int triggered = 0;
        trigger.OnStart = () => triggered++; trigger.OnStop = () => triggered++;
        trigger.Start();
        var hookField = typeof(KeyTrigger).GetField("_hookId", BindingFlags.Instance | BindingFlags.NonPublic);
        Assert(hookField != null && (IntPtr)hookField.GetValue(trigger)! != IntPtr.Zero,
            "Keyboard hook registration failed; native injected-key filtering cannot be tested.");
        await CheckSlowExternalTarget(host);
        Assert(triggered == 0, "Injected paste shortcut triggered dictation.");
        Console.WriteLine("PASS: real two-process paste reads the dictated payload after 1500ms; pre-placement failure preserves clipboard, blocked/partial input retains payload, concurrent copies survive, history/cloud/monitor exclusions and injected-key filtering preserved");
        host.Controls.Remove(editor); host.Activate();
    }

    private static async Task CheckSlowExternalTarget(Form host)
    {
        string folder = Path.Combine(Path.GetTempPath(), "inlaut-clipboard-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        using var child = new Process { StartInfo = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true } };
        child.StartInfo.ArgumentList.Add("--clipboard-target"); child.StartInfo.ArgumentList.Add(folder);
        try
        {
            host.Activate(); child.Start();
            string readyPath = Path.Combine(folder, "ready.json");
            await WaitForFile(readyPath, child);
            var ready = JsonSerializer.Deserialize<Ready>(File.ReadAllText(readyPath))!;
            Assert(ready.Pid == child.Id && ready.Pid != Environment.ProcessId, "Paste target is not a separate process.");
            var window = new IntPtr(ready.Window);
            var target = new DirectTextInserter.InputTarget(window, new IntPtr(ready.Control));
            var focus = Stopwatch.StartNew();
            bool focused = false;
            while (focus.Elapsed < TimeSpan.FromSeconds(5))
            {
                if (child.HasExited) throw new Exception("External clipboard target exited before receiving focus.");
                try
                {
                    if (DirectTextInserter.CaptureTarget() == target) { focused = true; break; }
                }
                catch (InvalidOperationException)
                {
                    // Window activation can briefly leave no focused control.
                    // Retry only this transient state within the same deadline.
                }
                SetForegroundWindow(window); await Task.Delay(50);
            }
            Assert(focused, "External clipboard target did not receive focus within five seconds.");
            DirectTextInserter.RequireTarget(target);
            Clipboard.SetText("OLD PRIVATE CONTENT MUST NOT BE PASTED");
            await ClipboardTextInserter.InsertAsync(Expected, target); // Real production SendInput path.
            string resultPath = Path.Combine(folder, "result.json");
            await WaitForFile(resultPath, child);
            var result = JsonSerializer.Deserialize<Result>(File.ReadAllText(resultPath))!;
            Assert(result.Error == null, "External paste target failed: " + result.Error);
            Assert(result.DelayMs >= 1400, "External target did not delay clipboard consumption beyond 750ms.");
            Assert(result.Text?.ReplaceLineEndings("\n") == Expected, "Slow target pasted previous clipboard content instead of dictation.");
            Assert(result.PrivateFormats, "History/cloud/monitor exclusions did not reach the external process.");
            Assert(Clipboard.GetText().ReplaceLineEndings("\n") == Expected, "Successful paste restored previous clipboard content.");
            await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
            Assert(child.ExitCode == 0, "External paste target exited unsuccessfully.");
        }
        finally
        {
            try { if (!child.HasExited) { child.Kill(true); await child.WaitForExitAsync(); } } catch (InvalidOperationException) { }
            Directory.Delete(folder, true);
        }
    }

    // Invoke before the main UiSmoke window exists: --clipboard-target <folder>.
    public static int RunSlowTargetChild(string folder)
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        using var form = new Form { Text = "inlaut — slow paste target", Width = 500, Height = 250 };
        using var editor = new SlowPasteEditor(folder) { Multiline = true, Dock = DockStyle.Fill };
        form.Controls.Add(editor);
        using var watchdog = new System.Threading.Timer(_ => Environment.Exit(2), null, 20_000, Timeout.Infinite);
        form.Shown += (_, _) =>
        {
            form.Activate(); editor.Focus();
            WriteJson(Path.Combine(folder, "ready.json"), new Ready(form.Handle.ToInt64(), editor.Handle.ToInt64(), Environment.ProcessId));
        };
        Application.Run(form);
        return 0;
    }

    private sealed class SlowPasteEditor(string folder) : TextBox
    {
        protected override bool ProcessCmdKey(ref Message message, Keys keyData)
        {
            if (keyData != (Keys.Control | Keys.V)) return base.ProcessCmdKey(ref message, keyData);
            var elapsed = Stopwatch.StartNew();
            Result result;
            try
            {
                // A blocked destination process cannot consume Ctrl+V promptly.
                // Parent UI/timers remain live, unlike a same-process editor test.
                Thread.Sleep(1500);
                string text = Clipboard.GetText(TextDataFormat.UnicodeText);
                bool privateFormats = HasPrivateFormats();
                SelectedText = text;
                result = new(Text, elapsed.ElapsedMilliseconds, privateFormats, null);
            }
            catch (Exception error) { result = new(null, elapsed.ElapsedMilliseconds, false, error.ToString()); }
            WriteJson(Path.Combine(folder, "result.json"), result);
            BeginInvoke(new Action(() => FindForm()!.Close()));
            return true;
        }
    }

    private static bool HasPrivateFormats()
    {
        var data = Clipboard.GetDataObject();
        return data != null && PrivateFormats.All(format => data.GetData(format, false) is MemoryStream stream &&
            stream.Length == 4 && stream.ToArray().All(b => b == 0));
    }

    private static async Task WaitForFile(string path, Process child)
    {
        var elapsed = Stopwatch.StartNew();
        while (!File.Exists(path))
        {
            if (child.HasExited) throw new Exception("External clipboard process exited before producing " + Path.GetFileName(path));
            if (elapsed.Elapsed > TimeSpan.FromSeconds(8)) throw new TimeoutException("External clipboard target timed out: " + Path.GetFileName(path));
            await Task.Delay(25);
        }
    }

    private static void WriteJson<T>(string path, T value)
    {
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(value)); File.Move(path + ".tmp", path);
    }
    private static void Assert(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed record Ready(long Window, long Control, int Pid);
    private sealed record Result(string? Text, long DelayMs, bool PrivateFormats, string? Error);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
}
