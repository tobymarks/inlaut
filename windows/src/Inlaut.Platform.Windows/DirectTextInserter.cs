using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Inlaut.Platform.Windows;

/// <summary>Clipboard-free replacement in native Edit/RichEdit controls, with
/// paced Unicode packets for other single-line targets. Packet acceptance is not
/// acknowledgement: queued events can cross a concurrent focus change.</summary>
public static class DirectTextInserter
{
    public readonly record struct InputTarget(IntPtr Window, IntPtr Control);
    public static InputTarget CaptureTarget() => Focus();
    public static void RequireTarget(InputTarget target)
    {
        if (Focus() != target)
            throw new InvalidOperationException("Das Eingabefeld hat sich seit Beginn des Diktats geändert. Es wurde kein neuer Einfügeversuch gestartet.");
    }
    private static readonly SemaphoreSlim Gate = new(1, 1);

    public static async Task<string> InsertAsync(string text, CancellationToken cancellationToken = default, bool forcePacketForTest = false, InputTarget? expectedTarget = null)
    {
        if (string.IsNullOrEmpty(text)) return "none";
        if (!await Gate.WaitAsync(0, cancellationToken))
            throw new InvalidOperationException("Eine Texteingabe läuft bereits.");
        int inserted = 0;
        try
        {
            var target = expectedTarget ?? Focus();
            RequireTarget(target);
            var timer = Stopwatch.StartNew();
            while (ModifiersDown())
            {
                if (timer.ElapsedMilliseconds >= 2000)
                    throw new InvalidOperationException("Bitte Strg, Alt, Umschalt und Windows-Taste loslassen.");
                await Task.Delay(20, cancellationToken);
            }
            await Task.Delay(50, cancellationToken);
            if (Focus() != target || ModifiersDown())
                throw new InvalidOperationException("Das Eingabefeld hat sich geändert. Es wurde kein Text eingefügt.");
            if (!forcePacketForTest && IsNativeEditor(target.Control))
            {
                int style = GetWindowLong(target.Control, -16);
                if (!IsWindowEnabled(target.Control) || (style & (0x0800 | 0x0020)) != 0)
                    throw new InvalidOperationException("Dieses Textfeld ist schreibgeschützt, deaktiviert oder ein Kennwortfeld.");
                if ((style & 0x0004) == 0 && (text.Contains('\r') || text.Contains('\n')))
                    throw new InvalidOperationException("Dieses Textfeld unterstützt keine mehrzeilige Eingabe.");
                // EM_REPLACESEL targets the original edit control and supports undo.
                // It is marshalled by Windows across processes; no clipboard or
                // Return/Tab shortcut is involved. Run off-thread so our UI pumps
                // messages when the destination belongs to this same process.
                await Task.Run(() =>
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    if (Focus() != target || ModifiersDown())
                        throw new InvalidOperationException("Das Eingabefeld hat sich geändert. Es wurde kein Text eingefügt.");
                    if (SendMessageTimeout(target.Control, 0x00C2, new IntPtr(1), text.ReplaceLineEndings("\r\n"), 0x0002 | 0x0020, 2000, out _) == IntPtr.Zero)
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Das Textfeld hat die Eingabe nicht bestätigt. Nicht automatisch erneut einfügen: Text könnte bereits angekommen sein.");
                }, cancellationToken);
                return "native-edit";
            }
            if (text.Contains('\r') || text.Contains('\n'))
                throw new InvalidOperationException("Mehrzeiliger Text wird in diesem Feld noch nicht direkt unterstützt. Bitte für dieses Programm den Zwischenablage-Vergleichsmodus verwenden.");
            await Task.Run(() =>
            {
                using var pacer = new PacketPacer();
                foreach (var rune in text.EnumerateRunes())
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    if (Focus() != target || ModifiersDown())
                        throw new InvalidOperationException($"Texteingabe nach {inserted} Zeichen angehalten: Fokus oder Zusatztasten geändert. Bereits eingegebener Text bleibt erhalten.");
                    var inputs = new List<NativeMethods.INPUT>(4);
                    // Never emit Return/Tab virtual-key shortcuts, which can submit
                    // a chat or navigate away from its text field.
                    foreach (char unit in rune.ToString()) AddPair(inputs, unit, true);
                    uint sent = NativeMethods.SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf<NativeMethods.INPUT>());
                    if (sent != inputs.Count)
                    {
                        int error = Marshal.GetLastWin32Error();
                        // A partial batch can leave a key down; release only accepted downs.
                        for (int i = 0; i < sent; i += 2)
                            if (i + 1 >= sent) NativeMethods.SendInput(1, new[] { inputs[i + 1] }, Marshal.SizeOf<NativeMethods.INPUT>());
                        throw new Win32Exception(error, $"Windows hat die Eingabe nach {inserted} Zeichen blockiert. Der Text wird nicht automatisch erneut eingefügt.");
                    }
                    inserted++;
                    pacer.Delay();
                }
            }, cancellationToken);
            return "unicode-paced";
        }
        finally { Gate.Release(); }
    }

    private static bool ModifiersDown() => new[] { 0x10, 0x11, 0x12, 0x5B, 0x5C }
        .Any(key => (NativeMethods.GetAsyncKeyState(key) & 0x8000) != 0);

    // A normal Task.Delay(10) commonly costs a full ~15.6 ms Windows timer tick.
    // A dedicated waitable timer provides 4 ms pacing without changing global
    // timer resolution, spinning, batching characters or blocking the UI thread.
    // https://learn.microsoft.com/windows/win32/api/synchapi/nf-synchapi-createwaitabletimerexw
    private sealed class PacketPacer : WaitHandle
    {
        public PacketPacer()
        {
            var handle = CreateWaitableTimerEx(IntPtr.Zero, null, 0x2, 0x00100002);
            if (handle.IsInvalid)
            {
                int error = Marshal.GetLastWin32Error();
                handle.Dispose();
                if (error != 87) throw new Win32Exception(error);
                // Older Windows versions do not support high-resolution timers.
                handle = CreateWaitableTimerEx(IntPtr.Zero, null, 0, 0x00100002);
                if (handle.IsInvalid)
                {
                    error = Marshal.GetLastWin32Error();
                    handle.Dispose();
                    throw new Win32Exception(error);
                }
            }
            SafeWaitHandle = handle;
        }

        public void Delay()
        {
            long dueTime = -40_000; // Relative 4 ms, in 100 ns units.
            if (!SetWaitableTimer(SafeWaitHandle, ref dueTime, 0, IntPtr.Zero, IntPtr.Zero, false))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if (!WaitOne(2000)) throw new TimeoutException("Zeitsteuerung der Texteingabe antwortet nicht.");
        }
    }

    [DllImport("kernel32.dll", EntryPoint = "CreateWaitableTimerExW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern Microsoft.Win32.SafeHandles.SafeWaitHandle CreateWaitableTimerEx(IntPtr attributes, string? name, uint flags, uint access);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWaitableTimer(Microsoft.Win32.SafeHandles.SafeWaitHandle timer, ref long dueTime, int period, IntPtr callback, IntPtr argument, [MarshalAs(UnmanagedType.Bool)] bool resume);

    private static bool IsNativeEditor(IntPtr control)
    {
        var name = new StringBuilder(256);
        if (GetClassName(control, name, name.Capacity) == 0) return false;
        string value = name.ToString();
        return value.Equals("Edit", StringComparison.OrdinalIgnoreCase)
            || value.StartsWith("WindowsForms10.EDIT.", StringComparison.OrdinalIgnoreCase)
            || value.StartsWith("WindowsForms10.RichEdit", StringComparison.OrdinalIgnoreCase)
            || value.Equals("RichEdit20W", StringComparison.OrdinalIgnoreCase)
            || value.Equals("RICHEDIT50W", StringComparison.OrdinalIgnoreCase);
    }

    private static InputTarget Focus()
    {
        IntPtr window = NativeMethods.GetForegroundWindow();
        uint thread = GetWindowThreadProcessId(window, out _);
        var info = new GuiThreadInfo { cbSize = Marshal.SizeOf<GuiThreadInfo>() };
        if (window == IntPtr.Zero || thread == 0 || !GetGUIThreadInfo(thread, ref info) || info.hwndFocus == IntPtr.Zero)
            throw new InvalidOperationException("Kein aktives Eingabefeld gefunden.");
        return new InputTarget(window, info.hwndFocus);
    }

    private static void AddPair(List<NativeMethods.INPUT> inputs, ushort value, bool unicode)
    {
        foreach (bool up in new[] { false, true })
            inputs.Add(new NativeMethods.INPUT
            {
                type = NativeMethods.INPUT_KEYBOARD,
                u = new NativeMethods.InputUnion { ki = new NativeMethods.KEYBDINPUT
                {
                    wVk = unicode ? (ushort)0 : value,
                    wScan = unicode ? value : (ushort)0,
                    dwFlags = (unicode ? NativeMethods.KEYEVENTF_UNICODE : 0) | (up ? NativeMethods.KEYEVENTF_KEYUP : 0)
                } }
            });
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GuiThreadInfo
    {
        public int cbSize;
        public uint flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public int left, top, right, bottom;
    }
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetGUIThreadInfo(uint thread, ref GuiThreadInfo info);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder name, int count);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wParam, string text, uint flags, uint timeout, out UIntPtr result);
}
