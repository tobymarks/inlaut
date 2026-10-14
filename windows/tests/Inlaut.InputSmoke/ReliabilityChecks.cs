using System.Diagnostics;
using System.Text.Json;
using Inlaut.Platform.Windows;

namespace Inlaut.InputSmoke;

internal static class ReliabilityChecks
{
    internal sealed record Request(string Model, string Audio, int Cycles = 100);
    public static async Task Run(Request request, Form host, TextBox plain, RichTextBox rich)
    {
        var results = new List<object>();
        string report = Path.Combine(AppContext.BaseDirectory, "reliability-results.json");
        void Save() => File.WriteAllText(report, JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
        var stopwatch = Stopwatch.StartNew();
        while (NativeMethods.GetForegroundWindow() != host.Handle && stopwatch.Elapsed.TotalSeconds < 90) await Task.Delay(100);
        if (NativeMethods.GetForegroundWindow() != host.Handle) throw new Exception("Activate isolated test window.");
        uint clipboard = NativeMethods.GetClipboardSequenceNumber();
        using var engine = await Task.Run(() => new SherpaEngine(request.Model, threads: 2));
        var pipeline = new Inlaut.Core.TextPipeline();
        var previous = new Dictionary<string, string>();
        for (int i = 0; i < request.Cycles; i++)
        {
            // Alternate short speech, spoken line commands, long speech, silence,
            // 50 ms of silence, and low-level noise in the same recognizer instance.
            string name = new[] { "speech-0", "speech-1", "speech-2", "silence", "short", "noise" }[i % 6];
            var (raw, audioSec, decodeSec, _) = await Task.Run(() => engine.TranscribeFile(Path.Combine(request.Audio, name + ".wav")));
            string processed = pipeline.ProcessDictation(raw);
            bool expectEmpty = name is "silence" or "short" or "noise";
            rich.Clear(); rich.Focus();
            if (processed.Length > 0) await DirectTextInserter.InsertAsync(processed);
            bool exact = rich.Text.ReplaceLineEndings("\n") == processed.ReplaceLineEndings("\n");
            bool stable = !previous.TryGetValue(name, out string? earlier) || earlier == raw;
            previous[name] = raw;
            using var process = Process.GetCurrentProcess();
            process.Refresh();
            results.Add(new { mode = "repeat-audio-to-field", iteration = i + 1, name, raw, processed, audioSec, decodeSec,
                exact, stable, expectedSilence = expectEmpty, silencePassed = !expectEmpty || processed.Length == 0,
                privateBytes = process.PrivateMemorySize64, workingSetBytes = process.WorkingSet64, handles = process.HandleCount,
                totalSeconds = stopwatch.Elapsed.TotalSeconds });
            Save();
            if (!exact || !stable || (expectEmpty && processed.Length != 0)) throw new Exception($"Reliability failure in {name}, cycle {i + 1}.");
            host.Text = $"inlaut – Dauertest {i + 1}/{request.Cycles}";
            await Task.Delay(20);
        }

        // A cancelled request must not leave the single-insertion gate locked.
        foreach (int cancelMs in new[] { 0, 200 })
        {
            plain.Clear(); plain.Focus();
            using var cancellation = new CancellationTokenSource();
            if (cancelMs == 0) cancellation.Cancel(); else cancellation.CancelAfter(cancelMs);
            bool cancelled = false;
            try { await DirectTextInserter.InsertAsync(new string('x', 2000), cancellation.Token, forcePacketForTest: true); }
            catch (OperationCanceledException) { cancelled = true; }
            await Task.Delay(200); // Allow already queued characters to drain.
            int partial = plain.TextLength;
            plain.Clear(); plain.Focus();
            await DirectTextInserter.InsertAsync("Nach Abbruch wieder bereit.");
            bool recovered = plain.Text == "Nach Abbruch wieder bereit.";
            results.Add(new { mode = "cancel-and-recover", cancelMs, cancelled, partial, recovered });
            Save();
            if (!cancelled || !recovered || partial >= 2000) throw new Exception("Cancellation recovery failed.");
        }

        // Focus changes during decode must reject both insertion strategies before
        // they touch either editor; clipboard-mode rejection precedes clipboard use.
        foreach (bool paste in new[] { false, true })
        {
            plain.Clear(); rich.Clear(); plain.Focus();
            var target = DirectTextInserter.CaptureTarget();
            rich.Focus();
            bool rejected = false;
            try
            {
                if (paste) await Inlaut.App.ClipboardTextInserter.InsertAsync("NICHT EINFÜGEN", target);
                else await DirectTextInserter.InsertAsync("NICHT EINFÜGEN", expectedTarget: target);
            }
            catch (InvalidOperationException) { rejected = plain.TextLength == 0 && rich.TextLength == 0; }
            results.Add(new { mode = "decode-focus-change", paste, rejected });
            Save();
            if (!rejected) throw new Exception("Wrong-target input was not rejected.");
        }

        plain.Clear(); plain.Focus();
        if (NativeMethods.GetForegroundWindow() != host.Handle) throw new Exception("Test window lost focus before modifier test.");
        Task<string>? pending = null;
        bool waited;
        try
        {
            Shift(false);
            pending = DirectTextInserter.InsertAsync("Nach Loslassen bereit.", forcePacketForTest: true);
            await Task.Delay(200);
            waited = plain.TextLength == 0 && !pending.IsCompleted;
        }
        finally { Shift(true); }
        await pending!;
        await Task.Delay(100);
        bool released = plain.Text == "Nach Loslassen bereit.";
        results.Add(new { mode = "modifier-held-then-released", waited, exact = released });
        Save();
        if (!waited || !released) throw new Exception("Held modifier was not respected.");

        plain.Clear(); plain.Focus();
        var running = DirectTextInserter.InsertAsync(new string('x', 1000), forcePacketForTest: true);
        await Task.Delay(200);
        bool modifierRejected = false;
        try
        {
            Shift(false);
            try { await running; }
            catch (InvalidOperationException) { modifierRejected = true; }
        }
        finally { Shift(true); }
        await Task.Delay(200);
        int modifierPartial = plain.TextLength;
        plain.Clear(); plain.Focus();
        await DirectTextInserter.InsertAsync("Wieder bereit.");
        bool modifierRecovered = plain.Text == "Wieder bereit.";
        results.Add(new { mode = "modifier-during-insertion", modifierRejected, modifierPartial, modifierRecovered });
        Save();
        if (!modifierRejected || modifierPartial >= 1000 || !modifierRecovered) throw new Exception("Modifier interruption failed.");
        bool unchanged = clipboard == NativeMethods.GetClipboardSequenceNumber();
        results.Add(new { mode = "clipboard-unchanged", exact = unchanged });
        Save();
        if (!unchanged) throw new Exception("Clipboard changed during isolated test.");
        host.Text = "inlaut – Dauertest bestanden";
    }

    private static void Shift(bool up)
    {
        var key = new NativeMethods.INPUT { type = NativeMethods.INPUT_KEYBOARD,
            u = new NativeMethods.InputUnion { ki = new NativeMethods.KEYBDINPUT
                { wVk = 0x10, dwFlags = up ? NativeMethods.KEYEVENTF_KEYUP : 0 } } };
        if (NativeMethods.SendInput(1, new[] { key }, System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.INPUT>()) != 1)
            throw new Exception("Could not inject test modifier.");
    }
}
