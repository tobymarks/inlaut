using System.Threading;
using System.Windows.Forms;

namespace Inlaut.App;

internal static class Program
{
    private const string AppMutexName = "Global\\Inlaut-Windows-App-SingleInstance";

    [STAThread]
    static void Main()
    {
        UiText.Language = AppSettings.Load().InterfaceLanguage;
        using var mutex = new Mutex(true, AppMutexName, out bool isOnlyInstance);

        if (!isOnlyInstance)
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
