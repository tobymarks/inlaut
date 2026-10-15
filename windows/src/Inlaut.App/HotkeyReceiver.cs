using System.Windows.Forms;
using Inlaut.Platform.Windows;

namespace Inlaut.App;

public class HotkeyReceiver : NativeWindow, IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const int HOTKEY_ID = 9001;

    public event Action? HotkeyPressed;

    public HotkeyReceiver()
    {
        CreateHandle(new CreateParams());
    }

    public bool RegisterDefaultHotkey()
    {
        // Ctrl + Alt + Space (with MOD_NOREPEAT 0x4000)
        uint fsModifiers = NativeMethods.MOD_CONTROL | NativeMethods.MOD_ALT | 0x4000;
        uint vk = 0x20; // VK_SPACE

        return NativeMethods.RegisterHotKey(Handle, HOTKEY_ID, fsModifiers, vk);
    }

    public void Unregister()
    {
        if (Handle != IntPtr.Zero)
        {
            NativeMethods.UnregisterHotKey(Handle, HOTKEY_ID);
        }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID)
        {
            HotkeyPressed?.Invoke();
            return;
        }

        base.WndProc(ref m);
    }

    public void Dispose()
    {
        Unregister();
        DestroyHandle();
    }
}
