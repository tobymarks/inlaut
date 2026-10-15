using System.Diagnostics;
using System.Text.Json;
using Inlaut.Platform.Windows;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Web.WebView2.Core;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        using var host = new Form { Text = "inlaut – isolierter Browser-Eingabetest", Width = 900, Height = 600 };
        using var browser = new WebView2 { Dock = DockStyle.Fill };
        host.Controls.Add(browser);
        host.Shown += async (_, _) =>
        {
            var results = new List<object>();
            try
            {
                var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: Path.Combine(AppContext.BaseDirectory, "test-profile"));
                await browser.EnsureCoreWebView2Async(environment);
                var loaded = new TaskCompletionSource();
                browser.NavigationCompleted += (_, _) => loaded.TrySetResult();
                browser.NavigateToString("<html><body><h1>Lokaler Eingabetest</h1><textarea id='plain' style='width:95%;height:160px'></textarea><div id='rich' contenteditable='true' style='border:1px solid gray;height:200px'></div></body></html>");
                await loaded.Task;
                var focusWait = Stopwatch.StartNew();
                while (NativeMethods.GetForegroundWindow() != host.Handle && focusWait.Elapsed.TotalSeconds < 90) await Task.Delay(250);
                if (NativeMethods.GetForegroundWindow() != host.Handle) throw new Exception("Testfenster ist nicht aktiv.");
                uint clipboard = NativeMethods.GetClipboardSequenceNumber();
                foreach (string id in new[] { "plain", "rich" })
                foreach (int repetitions in new[] { 1, 15, 40 })
                {
                    string expected = string.Concat(Enumerable.Repeat("Erstes Wort, vollständiger Satz: Grüße, Straße, ÄÖÜ äöü ß, 100000! 😀 e\u0301 ", repetitions)).TrimEnd();
                    browser.Focus();
                    await browser.CoreWebView2.ExecuteScriptAsync($"document.getElementById('{id}').value='';document.getElementById('{id}').textContent='';document.getElementById('{id}').focus();");
                    await Task.Delay(100);
                    var timer = Stopwatch.StartNew();
                    string method = await DirectTextInserter.InsertAsync(expected);
                    long sentMs = timer.ElapsedMilliseconds;
                    string actual;
                    do
                    {
                        actual = JsonSerializer.Deserialize<string>(await browser.CoreWebView2.ExecuteScriptAsync($"document.getElementById('{id}')." + (id == "plain" ? "value" : "textContent")))!;
                        if (actual == expected) break;
                        await Task.Delay(25);
                    } while (timer.ElapsedMilliseconds < sentMs + 3000);
                    bool exact = actual == expected;
                    results.Add(new { id, method, characters = expected.Length, sentMs, deliveredMs = timer.ElapsedMilliseconds, exact, expected, actual });
                    if (!exact) throw new Exception("Browser output differs.");
                }
                bool unchanged = clipboard == NativeMethods.GetClipboardSequenceNumber();
                results.Add(new { mode = "clipboard-unchanged", exact = unchanged });
                if (!unchanged) throw new Exception("Clipboard changed.");
                host.Text = "inlaut – Browser-Eingabetest bestanden";
            }
            catch (Exception ex) { results.Add(new { error = ex.ToString() }); host.Text = "inlaut – Browser-Eingabetest fehlgeschlagen"; }
            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "browser-results.json"), JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
        };
        Application.Run(host);
    }
}
