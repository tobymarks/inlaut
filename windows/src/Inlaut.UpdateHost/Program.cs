using System.Diagnostics;
using Inlaut.App;
using System.Text.Json;
using Inlaut.Core;
using Inlaut.Platform.Windows;

namespace Inlaut.UpdateHost;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        UiText.Language = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "de" ? "de" : "en";
        string? application = null; bool parentExited = false;
        try
        {
            if (args.Length != 1) throw new ArgumentException(UiText.Get("Update-Auftrag fehlt."));
            string requestPath = Path.GetFullPath(args[0]);
            if (new FileInfo(requestPath).Length > 32768) throw new IOException(UiText.Get("Update-Auftrag zu groß."));
            var request = JsonSerializer.Deserialize<UpdateRequest>(File.ReadAllText(requestPath)) ?? throw new IOException(UiText.Get("Update-Auftrag ungültig."));
            UiText.Language = request.InterfaceLanguage == "en" ? "en" : "de";
            application = Path.GetFullPath(request.Application);
            if (Path.GetFileName(application) != "Inlaut.exe" || !request.Manifest.IsNewer(request.CurrentVersion, true)) throw new IOException(UiText.Get("Ungültiges Update-Ziel."));
            try
            {
                using var parent = Process.GetProcessById(request.ParentPid);
                try
                {
                    if (!parent.HasExited)
                    {
                        if (parent.StartTime.ToUniversalTime().Ticks != request.ParentStarted || !string.Equals(parent.MainModule?.FileName, application, StringComparison.OrdinalIgnoreCase)) throw new IOException(UiText.Get("inlaut-Prozess hat sich geändert."));
                        if (!parent.WaitForExit(60000)) throw new IOException(UiText.Get("inlaut wurde nicht beendet. Update abgebrochen."));
                    }
                }
                catch (InvalidOperationException) when (parent.HasExited) { /* Exit raced inspection. */ }
            }
            catch (ArgumentException) { /* The parent already exited cleanly. */ }
            parentExited = true;
            string installer = Path.Combine(Path.GetDirectoryName(requestPath)!, "update.exe");
            using (var locked = new FileStream(installer, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                UpdateSecurity.VerifyPackage(installer, request.Manifest, application);
                var start = new ProcessStartInfo(installer) { UseShellExecute = false };
                foreach (var arg in new[] { "/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/DIR=" + Path.GetDirectoryName(application) }) start.ArgumentList.Add(arg);
                using var setup = Process.Start(start) ?? throw new IOException(UiText.Get("Installation konnte nicht gestartet werden."));
                setup.WaitForExit();
                if (setup.ExitCode != 0) throw new IOException(UiText.Format("Installation nicht abgeschlossen (Code {0}). Die vorhandene Version kann weiterverwendet werden.", setup.ExitCode));
            }
            File.Delete(installer); File.Delete(requestPath);
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(UiText.Get(error.Message) + UiText.Get("\nDu kannst die Update-Suche später erneut starten."), UiText.Get("inlaut — Update nicht abgeschlossen"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
        finally
        {
            if (parentExited && application != null && File.Exists(application))
            {
                try { Process.Start(new ProcessStartInfo(application) { UseShellExecute = true }); }
                catch { MessageBox.Show(UiText.Get("Bitte inlaut über das Startmenü öffnen."), UiText.Get("inlaut — Neustart")); }
            }
        }
    }
}
