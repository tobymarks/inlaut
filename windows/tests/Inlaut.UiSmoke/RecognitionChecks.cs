using System.Diagnostics;
using Inlaut.Core;
using Inlaut.Platform.Windows;

namespace Inlaut.UiSmoke;

internal static class RecognitionChecks
{
    // Called after the packaged English model has decoded its real reference WAV.
    // This tests the resulting text through the production pipeline and inserter;
    // no microphone, clipboard, or synthetic recognition result is involved.
    public static int Run(string recognizedEnglish)
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        using var host = new Form { Text = "inlaut — WAV to editor check", Width = 640, Height = 360 };
        using var editor = new RichTextBox { Dock = DockStyle.Fill };
        host.Controls.Add(editor);
        using var watchdog = new System.Threading.Timer(_ =>
        {
            Console.Error.WriteLine("WAV-to-editor check timed out.");
            Environment.Exit(2);
        }, null, 30_000, Timeout.Infinite);

        int exitCode = 1;
        host.Shown += async (_, _) =>
        {
            try
            {
                var target = new DirectTextInserter.InputTarget(host.Handle, editor.Handle);
                var focusWait = Stopwatch.StartNew();
                bool focused = false;
                while (focusWait.Elapsed < TimeSpan.FromSeconds(5))
                {
                    host.Activate(); editor.Focus();
                    await Task.Delay(50);
                    try
                    {
                        if (DirectTextInserter.CaptureTarget() == target) { focused = true; break; }
                    }
                    catch (InvalidOperationException) { } // Activation may briefly have no focused control.
                }
                if (!focused) throw new Exception("The isolated WAV-to-editor target did not receive focus.");

                var pipeline = new TextPipeline { Languages = [SpokenLanguage.English] };
                string expected = pipeline.ProcessDictation(recognizedEnglish);
                if (string.IsNullOrWhiteSpace(expected)) throw new Exception("The reference recording produced no text.");
                uint clipboard = NativeMethods.GetClipboardSequenceNumber();
                string method = await DirectTextInserter.InsertAsync(expected, expectedTarget: target);
                AssertExact(editor.Text, expected);
                Console.WriteLine($"PASS: real packaged English reference WAV -> production text pipeline -> native editor ({method}, {expected.Length} characters), exact text verified");

                // Separately exercise Unicode and CRLF transport alongside the
                // real recognition result, without labelling fixture text as ASR.
                const string transportFixture = "\r\nGrüße, Straße, ÄÖÜ, 😀, e\u0301.\r\nSecond line.\r\n";
                await DirectTextInserter.InsertAsync(transportFixture, expectedTarget: target);
                AssertExact(editor.Text, expected + transportFixture);
                if (NativeMethods.GetClipboardSequenceNumber() != clipboard)
                    throw new Exception("WAV-to-editor direct insertion modified the clipboard.");
                Console.WriteLine("PASS: separate Unicode/CRLF insertion fixture preserves the recognised text and leaves the clipboard unchanged");
                exitCode = 0;
            }
            catch (Exception error) { Console.Error.WriteLine(error); }
            finally { host.Close(); }
        };
        Application.Run(host);
        return exitCode;
    }

    private static void AssertExact(string actual, string expected)
    {
        if (!string.Equals(actual.ReplaceLineEndings("\n"), expected.ReplaceLineEndings("\n"), StringComparison.Ordinal))
            throw new Exception("The native editor text differs from the expected pipeline output.");
    }
}
