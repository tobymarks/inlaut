using System.Threading;
using System.Windows.Forms;

namespace Inlaut.App;

internal static class Program
{
    private const string AppMutexName = "Global\\Inlaut-Windows-App-SingleInstance";

    [STAThread]
    static void Main()
    {
        using var mutex = new Mutex(true, AppMutexName, out bool isOnlyInstance);

        if (!isOnlyInstance)
        {
            ApplicationConfiguration.Initialize();
            AppDialog.Information("inlaut läuft bereits", "Du findest inlaut im Infobereich der Taskleiste.");
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new InlautTrayApplicationContext());
    }
}
