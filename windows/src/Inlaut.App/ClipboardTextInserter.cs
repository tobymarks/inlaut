using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Inlaut.Platform.Windows;

namespace Inlaut.App;

public static class ClipboardTextInserter
{
    // Must run on the UI STA thread. A single paste avoids VK_PACKET bursts that
    // some editors turn into repetitions of the last character.
    public static async Task InsertAsync(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA)
            throw new InvalidOperationException("Clipboard insertion requires the UI thread.");

        var target = NativeMethods.GetForegroundWindow();
        var timer = Stopwatch.StartNew();
        while (ModifiersDown())
        {
            if (timer.ElapsedMilliseconds > 2000)
                throw new InvalidOperationException("Bitte Strg, Alt, Umschalt und Windows-Taste loslassen.");
            await Task.Delay(20);
        }
        await Task.Delay(50);
        if (target == IntPtr.Zero || target != NativeMethods.GetForegroundWindow())
            throw new InvalidOperationException("Das aktive Fenster hat sich geändert. Bitte erneut diktieren.");

        // Materialize formats before replacing the clipboard: the source's OLE
        // object may no longer serve its data after losing clipboard ownership.
        var previous = new DataObject();
        var original = Clipboard.GetDataObject();
        if (original != null)
        {
            foreach (string format in original.GetFormats(false))
            {
                object? value = original.GetData(format, false);
                if (value == null)
                    throw new InvalidOperationException("Die Zwischenablage konnte nicht vollständig gesichert werden.");
                if (value is MemoryStream stream) value = new MemoryStream(stream.ToArray());
                if (value is Image image) value = image.Clone();
                previous.SetData(format, false, value);
            }
        }

        var payload = new DataObject();
        payload.SetText(text.ReplaceLineEndings("\r\n"), TextDataFormat.UnicodeText);
        // https://learn.microsoft.com/windows/win32/dataxchg/clipboard-formats
        payload.SetData("ExcludeClipboardContentFromMonitorProcessing", new MemoryStream(new byte[4]));
        payload.SetData("CanIncludeInClipboardHistory", new MemoryStream(new byte[4]));
        payload.SetData("CanUploadToCloudClipboard", new MemoryStream(new byte[4]));
        Clipboard.SetDataObject(payload, true, 5, 20);
        uint sequence = NativeMethods.GetClipboardSequenceNumber();
        try
        {
            if (target != NativeMethods.GetForegroundWindow() || ModifiersDown())
                throw new InvalidOperationException("Fenster oder gedrückte Tasten haben sich geändert. Bitte erneut diktieren.");
            var keys = new[] { Key(0x11), Key(0x56), Key(0x56, true), Key(0x11, true) };
            uint sent = NativeMethods.SendInput((uint)keys.Length, keys, Marshal.SizeOf<NativeMethods.INPUT>());
            if (sent != keys.Length)
            {
                int error = Marshal.GetLastWin32Error();
                // Release any keys left down after a partially accepted shortcut.
                var releases = new[] { Key(0x56, true), Key(0x11, true) };
                NativeMethods.SendInput(2, releases, Marshal.SizeOf<NativeMethods.INPUT>());
                throw new Win32Exception(error, "Windows hat das Einfügen blockiert. Läuft das Zielprogramm als Administrator?");
            }
            // SendInput acknowledges queuing, not consumption. Keep the payload
            // available while the target processes Ctrl+V; do not block our UI.
            await Task.Delay(750);
        }
        finally
        {
            // Never overwrite something the user copied during the paste.
            if (sequence != 0 && NativeMethods.GetClipboardSequenceNumber() == sequence)
            {
                if (previous.GetFormats(false).Length == 0) Clipboard.Clear();
                else Clipboard.SetDataObject(previous, true, 5, 20);
            }
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
