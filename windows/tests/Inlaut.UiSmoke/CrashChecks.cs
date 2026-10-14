using Inlaut.App;
using System.Diagnostics;

namespace Inlaut.UiSmoke;

internal static class CrashChecks
{
    public static async Task Run()
    {
        string root = Path.Combine(Path.GetTempPath(), "inlaut-crash-tests-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        try
        {
            foreach (string mode in new[] { "clean", "killed", "fault" })
            {
                string directory = Path.Combine(root, mode);
                var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
                start.ArgumentList.Add("--crash-child"); start.ArgumentList.Add(directory); start.ArgumentList.Add(mode);
                using var child = Process.Start(start)!;
                await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10));
                var restarted = new CrashJournal(directory);
                bool pending = restarted.Begin();
                string? report = restarted.ReadReport();
                if (mode == "clean" && (pending || report != null)) throw new Exception("Clean exit misreported as crash.");
                if (mode != "clean" && (!pending || report == null)) throw new Exception("Unexpected process exit not detected.");
                if (mode != "clean" && !report!.Contains("recognized")) throw new Exception("Last safe phase missing.");
                if (report != null && (report.Contains("SECRET_TRANSCRIPT") || report.Contains("Private") || report.Contains("note.txt")))
                    throw new Exception("Private exception text or path leaked into report.");
                if (mode == "fault")
                {
                    if (!report!.Contains("InvalidOperationException") || !report.Contains("Unhandled exception")) throw new Exception("Fault evidence missing.");
                    using var dialog = new CrashReportForm(restarted); dialog.Show(); await Task.Delay(80);
                    using var bitmap = new Bitmap(dialog.Width, dialog.Height);
                    dialog.DrawToBitmap(bitmap, new Rectangle(Point.Empty, dialog.Size));
                    bitmap.Save(Path.Combine(AppContext.BaseDirectory, "crash-report.png")); dialog.Close();
                    File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "crash-report-sanitized.json"), report);
                }
                restarted.EndCleanly();
                var again = new CrashJournal(directory); again.Begin();
                if (mode != "clean" && again.ReadReport() == null) throw new Exception("Deferred report lost.");
                again.Dismiss(); again.EndCleanly();
                if (again.ReadReport() != null) throw new Exception("Report not discarded.");
            }
            // Failure to write diagnostic state must not prevent application use.
            string blocked = Path.Combine(root, "not-a-directory"); File.WriteAllText(blocked, "x");
            var unavailable = new CrashJournal(blocked); unavailable.Begin(); unavailable.Record(new IOException("secret")); unavailable.EndCleanly();
            string damaged = Path.Combine(root, "damaged"); Directory.CreateDirectory(damaged); File.WriteAllText(Path.Combine(damaged, "session.json"), "broken");
            var recovered = new CrashJournal(damaged); recovered.Begin();
            if (!File.ReadAllText(Path.Combine(damaged, "session.json")).Contains("Version")) throw new Exception("Damaged marker prevented future tracking.");
            recovered.EndCleanly();
            if (!Uri.UnescapeDataString(CrashReportForm.BuildIssueUrl("{}" )).Contains("```json") ||
                CrashReportForm.BuildIssueUrl(new string('x', 10000)).Length > 1800 || !CrashReportForm.BuildIssueUrl(new string('x', 10000)).Contains("attach"))
                throw new Exception("Report URL length handling differs.");
            Console.WriteLine("PASS: child-process clean/forced/fault exits, next-start detection, deferred/discarded report, message/path redaction and unwritable diagnostics; no network actions");
        }
        finally { Directory.Delete(root, true); }
    }
}
