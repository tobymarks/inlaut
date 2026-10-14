using System.Diagnostics;
using System.Text.Json;
using Inlaut.Platform.Windows;

namespace Inlaut.InputSmoke;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        using var host = new Form { Text = "inlaut – isolierter Eingabetest", Width = 800, Height = 500 };
        using var plain = new TextBox { Multiline = true, AcceptsReturn = true, AcceptsTab = true, Dock = DockStyle.Top, Height = 150 };
        using var rich = new RichTextBox { Dock = DockStyle.Fill };
        using var status = new Label { Dock = DockStyle.Bottom, Height = 45, Text = "Test läuft ausschließlich in diesen beiden Testfeldern. Bitte kurz nicht tippen." };
        host.Controls.Add(rich); host.Controls.Add(plain); host.Controls.Add(status);
        var results = new List<object>();
        host.Shown += async (_, _) =>
        {
            uint clipboard = NativeMethods.GetClipboardSequenceNumber();
            try
            {
                string audioRequest = Path.Combine(AppContext.BaseDirectory, "audio-request.json");
                if (File.Exists(audioRequest))
                {
                    var request = JsonSerializer.Deserialize<AudioRequest>(File.ReadAllText(audioRequest))!;
                    using var engine = await Task.Run(() => new SherpaEngine(request.Model, threads: 4));
                    var pipeline = new Inlaut.Core.TextPipeline();
                    for (int i = 0; i < request.Expected.Length; i++)
                    {
                        var (raw, audioSec, decodeSec, _) = await Task.Run(() => engine.TranscribeFile(Path.Combine(request.Audio, $"test-{i + 1}.wav")));
                        string processed = pipeline.ProcessDictation(raw);
                        if (string.IsNullOrWhiteSpace(processed)) throw new Exception("Leeres Erkennungsergebnis.");
                        rich.Clear(); rich.Focus();
                        await DirectTextInserter.InsertAsync(processed);
                        await Task.Delay(100);
                        bool exact = rich.Text == processed;
                        results.Add(new { mode = "synthetic-audio-to-editor", expected = request.Expected[i], raw, processed, actual = rich.Text, audioSec, decodeSec, exact });
                        if (!exact) throw new Exception("Erkannter Text wurde nicht vollständig eingefügt.");
                    }
                    results.Add(new { mode = "clipboard-unchanged", exact = clipboard == NativeMethods.GetClipboardSequenceNumber() });
                    File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "audio-results.json"), JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
                    status.Text = "Drei Sprachdateien erkannt und vollständig eingefügt.";
                    return;
                }
                if (args.Contains("--external") || File.Exists(Path.Combine(AppContext.BaseDirectory, "external-request.txt")))
                {
                    status.Text = "Warte auf den leeren Windows-Editor (maximal 90 Sekunden).";
                    var deadline = Stopwatch.StartNew();
                    while (deadline.Elapsed.TotalSeconds < 90)
                    {
                        var active = NativeMethods.GetForegroundWindow();
                        GetWindowThreadProcessId(active, out uint pid);
                        if (pid != 0 && Process.GetProcessById((int)pid).ProcessName.Equals("notepad", StringComparison.OrdinalIgnoreCase))
                        {
                            const string expected = "Direkte Eingabe ohne Zwischenablage: Grüße, Straße, ÄÖÜ äöü ß, 100000!\nZweite Zeile: vollständig und ohne Wiederholungen. 😀\n";
                            await DirectTextInserter.InsertAsync(expected);
                            results.Add(new { mode = "external-notepad-sent", expected, clipboardUnchanged = clipboard == NativeMethods.GetClipboardSequenceNumber() });
                            status.Text = "Testtext gesendet. Ergebnis bitte im Editor prüfen.";
                            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "external-results.json"), JsonSerializer.Serialize(results));
                            return;
                        }
                        await Task.Delay(250);
                    }
                    throw new TimeoutException("Kein aktiver Windows-Editor gefunden.");
                }
                await Task.Delay(1500);
                var focusWait = Stopwatch.StartNew();
                while (NativeMethods.GetForegroundWindow() != host.Handle && focusWait.Elapsed.TotalSeconds < 90)
                    await Task.Delay(250);
                if (NativeMethods.GetForegroundWindow() != host.Handle) throw new Exception("Testfenster ist nicht aktiv.");
                const string sentence = "Erstes Wort, danach ein vollständiger Satz: Grüße, Straße, ÄÖÜ äöü ß, 100000!";
                foreach (TextBoxBase editor in new TextBoxBase[] { plain, rich })
                {
                    editor.Focus();
                    TextInserter.InsertText(sentence);
                    await Task.Delay(500);
                    results.Add(new { target = editor.GetType().Name, mode = "legacy-burst", exact = editor.Text == sentence, actual = editor.Text });
                    editor.Clear(); editor.Focus();
                    await DirectTextInserter.InsertAsync(sentence, forcePacketForTest: true);
                    await Task.Delay(100);
                    results.Add(new { target = editor.GetType().Name, mode = "paced-packet-fallback", exact = editor.Text == sentence });
                    if (editor.Text != sentence) throw new Exception("Packet fallback differs.");
                    foreach (int repetitions in new[] { 1, 15, 40 })
                    {
                        string expected = string.Concat(Enumerable.Repeat(sentence + " 😀 e\u0301 ", repetitions));
                        editor.Clear(); editor.Focus();
                        var elapsed = Stopwatch.StartNew();
                        await DirectTextInserter.InsertAsync(expected, forcePacketForTest: true);
                        long sendMs = elapsed.ElapsedMilliseconds;
                        // SendInput acceptance is not a delivery acknowledgement.
                        // Let this test control drain its queue before comparison.
                        while (editor.Text != expected && elapsed.ElapsedMilliseconds < sendMs + 3000)
                            await Task.Delay(25);
                        bool exact = editor.Text == expected;
                        results.Add(new { target = editor.GetType().Name, mode = "fast-packet-long-text", exact, characters = expected.Length, sendMs, deliveredMs = elapsed.ElapsedMilliseconds, expected, actual = editor.Text });
                        if (!exact) throw new Exception("Fast packet long-text output differs.");
                    }
                    foreach (string expected in new[] { sentence, sentence + "\nZweite Zeile?\tUnicode: 😀 e\u0301.\n", string.Concat(Enumerable.Repeat(sentence + " ", 5)) })
                    {
                        editor.Clear(); editor.Focus();
                        var timer = Stopwatch.StartNew();
                        await DirectTextInserter.InsertAsync(expected);
                        await Task.Delay(100);
                        bool exact = editor.Text.ReplaceLineEndings("\n") == expected;
                        results.Add(new { target = editor.GetType().Name, mode = "direct-native", exact, expected, actual = editor.Text, ms = timer.ElapsedMilliseconds });
                        if (!exact) throw new Exception("Gestaffelte Eingabe weicht ab.");
                    }
                    const string original = "Vorher [ersetzen] danach";
                    editor.Text = original; editor.ClearUndo(); editor.Select(7, 10); editor.Focus();
                    await DirectTextInserter.InsertAsync("Grüße");
                    bool replaced = editor.Text == "Vorher Grüße danach";
                    editor.Undo();
                    bool undo = editor.Text == original;
                    editor.ReadOnly = true;
                    bool protectedField = false;
                    try { await DirectTextInserter.InsertAsync("NICHT EINFÜGEN"); }
                    catch (InvalidOperationException) { protectedField = editor.Text == original; }
                    editor.ReadOnly = false;
                    results.Add(new { target = editor.GetType().Name, mode = "selection-undo-readonly", exact = replaced && undo && protectedField });
                    if (!replaced || !undo || !protectedField) throw new Exception("Auswahl, Rückgängig oder Schreibschutz fehlgeschlagen.");
                }
                plain.Clear(); rich.Clear(); plain.Focus();
                var insertion = DirectTextInserter.InsertAsync(new string('a', 1000), forcePacketForTest: true);
                await Task.Delay(500);
                bool overlapRejected = false;
                try { await DirectTextInserter.InsertAsync("NO"); }
                catch (InvalidOperationException) { overlapRejected = true; }
                rich.Focus();
                bool focusRejected = false;
                try { await insertion; } catch (InvalidOperationException) { focusRejected = true; }
                // SendInput queues events. At most the last accepted scalar can be
                // dispatched after focus changes; focus checks cannot retract it.
                bool safe = overlapRejected && focusRejected && rich.Text.Length <= 1 && plain.Text.Length < 1000;
                results.Add(new { mode = "focus-and-overlap-guard", exact = safe, overlapRejected, focusRejected, firstLength = plain.Text.Length, secondLength = rich.Text.Length });
                if (!safe) throw new Exception("Fokusschutz fehlgeschlagen.");
                bool unchanged = clipboard == NativeMethods.GetClipboardSequenceNumber();
                results.Add(new { mode = "clipboard-unchanged", exact = unchanged });
                if (!unchanged) throw new Exception("Zwischenablage wurde während des Tests geändert.");
                status.Text = "Fertig: gestaffelte Eingabe und Schutzprüfungen bestanden. Ergebnisdatei gespeichert.";
            }
            catch (Exception ex) { results.Add(new { error = ex.ToString() }); status.Text = "Test abgebrochen: " + ex.Message; }
            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "input-results.json"), JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
        };
        Application.Run(host);
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    private record AudioRequest(string Model, string Audio, string[] Expected);
}
