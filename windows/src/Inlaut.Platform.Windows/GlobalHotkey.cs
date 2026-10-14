using System.Runtime.InteropServices;

namespace Inlaut.Platform.Windows;

public class GlobalHotkey : IDisposable
{
    public const uint MOD_ALT = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_SHIFT = 0x0004;
    public const uint MOD_WIN = 0x0008;
    public const uint MOD_NOREPEAT = 0x4000;

    private readonly IntPtr _hwnd;
    private readonly int _id;
    private bool _registered;

    public GlobalHotkey(IntPtr hwnd, int id, uint modifiers, uint vk)
    {
        _hwnd = hwnd;
        _id = id;
        _registered = NativeMethods.RegisterHotKey(_hwnd, _id, modifiers | MOD_NOREPEAT, vk);
    }

    public bool IsRegistered => _registered;

    public void Dispose()
    {
        if (_registered)
        {
            NativeMethods.UnregisterHotKey(_hwnd, _id);
            _registered = false;
        }
    }
}
