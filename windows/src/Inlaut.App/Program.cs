using System.Threading;
using System.Windows.Forms;
using System.Diagnostics;
using Inlaut.Core;

namespace Inlaut.App;

internal static class Program
{
    internal const string AppMutexName = "Local\\Inlaut-Windows-App-SingleInstance";

    [STAThread]
    static void Main()
    {
        UiText.Language = AppSettings.Load().InterfaceLanguage;
        Mutex mutex;
        bool isOnlyInstance;
        try { mutex = new Mutex(true, AppMutexName, out isOnlyInstance); }
        catch (Exception error) when (error is UnauthorizedAccessException or IOException or WaitHandleCannotBeOpenedException)
        {
            ApplicationConfiguration.Initialize();
            AppDialog.Error("inlaut", UiText.Get("inlaut konnte in dieser Windows-Sitzung nicht gestartet werden. Bitte abmelden und erneut anmelden oder den Support kontaktieren."));
            Environment.ExitCode = 1;
            return;
        }
        using var instanceLock = mutex;
        // beta.8 used a global name. Keep it present so an old binary started
        // after us also exits, but never use its existence to block another session.
        using var legacyLock = isOnlyInstance ? LegacyInstanceGuard.HoldCompatibilityMutex() : null;

        if (!isOnlyInstance || LegacyInstanceGuard.HasOtherInstanceInCurrentSession())
        {
            ApplicationConfiguration.Initialize();
            AppDialog.Information(UiText.Get("inlaut läuft bereits"), UiText.Get("Du findest inlaut im Infobereich der Taskleiste."));
            return;
        }

        var journal = CrashJournal.Current;
        journal.Begin();
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            if (e.ExceptionObject is Exception error) journal.Record(error);
        };
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) =>
        {
            journal.Record(e.Exception);
            Environment.Exit(1); // Do not continue with potentially corrupt UI state.
        };
        try
        {
            ApplicationConfiguration.Initialize();
            Application.Run(new InlautTrayApplicationContext());
        }
        catch (Exception error) { journal.Record(error); Environment.ExitCode = 1; }
        finally { journal.EndCleanly(); }
    }
}

internal static class LegacyInstanceGuard
{
    internal const string MutexName = "Global\\Inlaut-Windows-App-SingleInstance";
    private static readonly ReleaseVersion FirstSessionLocalVersion = ReleaseVersion.Parse("0.7.0-beta.9");

    internal static Mutex? HoldCompatibilityMutex(string name = MutexName)
    {
        try { return new Mutex(false, name); }
        // Another user's old instance may own the global object. It must not
        // prevent the new session-local app from starting.
        catch (Exception error) when (error is UnauthorizedAccessException or IOException or WaitHandleCannotBeOpenedException)
        { return null; }
    }

    internal static bool IsOtherInstance(int processId, int sessionId, int currentProcessId, int currentSessionId) =>
        processId != currentProcessId && sessionId == currentSessionId;

    internal static bool RequiresLegacyCheck(string? executablePath, string? productVersion, string? currentExecutablePath)
    {
        // Called only after acquiring the local mutex. Another copy of this
        // executable can only be waiting in its already-running dialog.
        if (!string.IsNullOrEmpty(executablePath) && !string.IsNullOrEmpty(currentExecutablePath) &&
            executablePath.Equals(currentExecutablePath, StringComparison.OrdinalIgnoreCase)) return false;
        if (string.IsNullOrEmpty(productVersion)) return true;
        try
        {
            // SDK apphosts include the source revision as SemVer build metadata.
            string version = productVersion.Split('+', 2)[0];
            return ReleaseVersion.Parse(version).CompareTo(FirstSessionLocalVersion) < 0;
        }
        catch (Exception error) when (error is FormatException or OverflowException) { return true; }
    }

    internal static bool HasOtherInstanceInCurrentSession()
    {
        using var current = Process.GetCurrentProcess();
        bool found = false;
        foreach (var process in Process.GetProcessesByName("Inlaut"))
        {
            using (process)
            {
                try
                {
                    if (!IsOtherInstance(process.Id, process.SessionId, current.Id, current.SessionId)) continue;
                    string? path = null, version = null;
                    try
                    {
                        var module = process.MainModule;
                        path = module?.FileName;
                        version = module?.FileVersionInfo.ProductVersion;
                    }
                    catch (System.ComponentModel.Win32Exception) { } // Unknown same-session binary: block conservatively.
                    found |= RequiresLegacyCheck(path, version, Environment.ProcessPath);
                }
                catch (InvalidOperationException) { } // Exited during enumeration.
                catch (System.ComponentModel.Win32Exception) { } // No access to a different user's process.
            }
        }
        return found;
    }
}
