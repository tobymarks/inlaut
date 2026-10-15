using Microsoft.Win32;

namespace Inlaut.App;

internal static class StartupRegistration
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(KeyPath, true);
        if (enabled) key.SetValue("inlaut", "\"" + Application.ExecutablePath + "\"");
        else key.DeleteValue("inlaut", false);
    }
    public static bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
        return string.Equals(key?.GetValue("inlaut") as string, "\"" + Application.ExecutablePath + "\"", StringComparison.OrdinalIgnoreCase);
    }
}
