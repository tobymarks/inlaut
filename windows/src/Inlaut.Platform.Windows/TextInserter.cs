using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Inlaut.Platform.Windows;

public static class TextInserter
{
    /// <summary>
    /// Waits until modifier keys (Ctrl, Alt, Shift, Win) are physically released.
    /// This prevents keystrokes from being interpreted as shortcuts like Ctrl+A, Ctrl+R, etc.
    /// </summary>
    public static void WaitForModifiersReleased(int timeoutMs = 1000)
    {
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < timeoutMs)
        {
            bool ctrl = (NativeMethods.GetAsyncKeyState(NativeMethods.VK_CONTROL) & 0x8000) != 0;
            bool alt = (NativeMethods.GetAsyncKeyState(NativeMethods.VK_MENU) & 0x8000) != 0;
            bool shift = (NativeMethods.GetAsyncKeyState(NativeMethods.VK_SHIFT) & 0x8000) != 0;
            bool win = (NativeMethods.GetAsyncKeyState(NativeMethods.VK_LWIN) & 0x8000) != 0 ||
                       (NativeMethods.GetAsyncKeyState(NativeMethods.VK_RWIN) & 0x8000) != 0;

            if (!ctrl && !alt && !shift && !win)
            {
                break;
            }
            Thread.Sleep(20);
        }
        // Small delay to let Windows message queues settle
        Thread.Sleep(30);
    }

    public static void InsertText(string text)
    {
        if (string.IsNullOrEmpty(text)) return;

        WaitForModifiersReleased();

        var inputs = new List<NativeMethods.INPUT>();

        foreach (char c in text)
        {
            // Key Down (Unicode)
            inputs.Add(new NativeMethods.INPUT
            {
                type = NativeMethods.INPUT_KEYBOARD,
                u = new NativeMethods.InputUnion
                {
                    ki = new NativeMethods.KEYBDINPUT
                    {
                        wVk = 0,
                        wScan = c,
                        dwFlags = NativeMethods.KEYEVENTF_UNICODE,
                        time = 0,
                        dwExtraInfo = UIntPtr.Zero
                    }
                }
            });

            // Key Up (Unicode)
            inputs.Add(new NativeMethods.INPUT
            {
                type = NativeMethods.INPUT_KEYBOARD,
                u = new NativeMethods.InputUnion
                {
                    ki = new NativeMethods.KEYBDINPUT
                    {
                        wVk = 0,
                        wScan = c,
                        dwFlags = NativeMethods.KEYEVENTF_UNICODE | NativeMethods.KEYEVENTF_KEYUP,
                        time = 0,
                        dwExtraInfo = UIntPtr.Zero
                    }
                }
            });
        }

        NativeMethods.SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf<NativeMethods.INPUT>());
    }
}
