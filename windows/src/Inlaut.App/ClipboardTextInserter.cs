using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Inlaut.Platform.Windows;

namespace Inlaut.App;

public static class ClipboardTextInserter
{
    // Must run on the UI STA thread. A single paste avoids VK_PACKET bursts that
    // some editors turn into repetitions of the last character.
    public static Task InsertAsync(string text, DirectTextInserter.InputTarget? expectedTarget = null) =>
        InsertAsync(text, expectedTarget, keys => NativeMethods.SendInput((uint)keys.Length, keys, Marshal.SizeOf<NativeMethods.INPUT>()));

    // Keep the native injection boundary replaceable for blocked/partial-input
    // regression checks; normal calls always use SendInput above.
    internal static async Task InsertAsync(string text, DirectTextInserter.InputTarget? expectedTarget,
        Func<NativeMethods.INPUT[], uint> sendInput)
    {
        if (string.IsNullOrEmpty(text)) return;
        if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA)
            throw new InvalidOperationException("Clipboard insertion requires the UI thread.");

        var target = expectedTarget ?? DirectTextInserter.CaptureTarget();
        DirectTextInserter.RequireTarget(target);
        var timer = Stopwatch.StartNew();
        while (ModifiersDown())
        {
            if (timer.ElapsedMilliseconds > 2000)
                throw new InvalidOperationException(UiText.Get("Bitte Strg, Alt, Umschalt und Windows-Taste loslassen."));
            await Task.Delay(20);
        }
        await Task.Delay(50);
        DirectTextInserter.RequireTarget(target);

        var payload = new DataObject();
        payload.SetText(text.ReplaceLineEndings("\r\n"), TextDataFormat.UnicodeText);
        // https://learn.microsoft.com/windows/win32/dataxchg/clipboard-formats
        payload.SetData("ExcludeClipboardContentFromMonitorProcessing", new MemoryStream(new byte[4]));
        payload.SetData("CanIncludeInClipboardHistory", new MemoryStream(new byte[4]));
        payload.SetData("CanUploadToCloudClipboard", new MemoryStream(new byte[4]));
        Clipboard.SetDataObject(payload, true, 5, 20);

        // Clipboard mode intentionally replaces its previous contents. Neither
        // SendInput's return value nor a timer proves the destination has read
        // Ctrl+V. Leave the payload in place even on failure; never restore old
        // data into a queued paste or overwrite something copied afterwards.
        DirectTextInserter.RequireTarget(target);
        if (ModifiersDown())
            throw new InvalidOperationException(UiText.Get("Fenster oder gedrückte Tasten haben sich geändert. Bitte erneut diktieren."));
        var keys = new[] { Key(0x11), Key(0x56), Key(0x56, true), Key(0x11, true) };
        uint sent = sendInput(keys);
        if (sent != keys.Length)
        {
            int error = Marshal.GetLastWin32Error();
            // Release any keys left down after a partially accepted shortcut.
            var releases = new[] { Key(0x56, true), Key(0x11, true) };
            sendInput(releases);
            throw new Win32Exception(error, UiText.Get("Windows hat das Einfügen blockiert. Läuft das Zielprogramm als Administrator?"));
        }
    }

    private static bool ModifiersDown() => new[] { 0x10, 0x11, 0x12, 0x5B, 0x5C }
        .Any(key => (NativeMethods.GetAsyncKeyState(key) & 0x8000) != 0);

    private static NativeMethods.INPUT Key(ushort key, bool up = false) => new()
    {
        type = NativeMethods.INPUT_KEYBOARD,
        u = new NativeMethods.InputUnion
        {
            ki = new NativeMethods.KEYBDINPUT { wVk = key, dwFlags = up ? NativeMethods.KEYEVENTF_KEYUP : 0 }
        }
    };
}
