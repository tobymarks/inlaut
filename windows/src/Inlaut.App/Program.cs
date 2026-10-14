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
            MessageBox.Show(
                "inlaut läuft bereits im Infobereich (unten rechts in der Taskleiste).",
                "inlaut",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information
            );
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new InlautTrayApplicationContext());
    }
}
