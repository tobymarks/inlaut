// This project executes production C# on macOS/Linux. ONLY operating-system
// boundaries are simulated. It does not validate Win32, OLE, audio or ASR.
global using System.Windows.Forms;
global using Thread = Inlaut.SimulationSmoke.StaThreadBoundary;

using System.Collections.Concurrent;
using System.Runtime.InteropServices;

namespace Inlaut.SimulationSmoke
{
    internal sealed class StaThreadBoundary
    {
        public static StaThreadBoundary CurrentThread { get; } = new();
        public ApartmentState GetApartmentState() => ApartmentState.STA;
    }

    internal sealed class Dispatcher : SynchronizationContext, IDisposable
    {
        private readonly BlockingCollection<(SendOrPostCallback Action, object? State)> _queue = new();
        public override void Post(SendOrPostCallback action, object? state) => _queue.Add((action, state));
        internal static void Run(Func<Task> action)
        {
            var previous = Current;
            using var context = new Dispatcher();
            SetSynchronizationContext(context);
            try
            {
                Task task = action();
                while (!task.IsCompleted)
                    if (context._queue.TryTake(out var item, 100)) item.Action(item.State);
                task.GetAwaiter().GetResult();
            }
            finally { SetSynchronizationContext(previous); }
        }
        public void Dispose() => _queue.Dispose();
    }
}

namespace Inlaut.App
{
    internal static class UiText { public static string Get(string text) => text; }
}

namespace System.Windows.Forms
{
    public class Control : IDisposable
    {
        public bool IsDisposed { get; private set; }
        public bool IsHandleCreated => !IsDisposed;
        public IntPtr Handle => new(1);
        public void BeginInvoke(Action action) => SynchronizationContext.Current!.Post(_ => action(), null);
        public void Dispose() => IsDisposed = true;
    }
    public sealed class Form : Control { }
    // Hotkey tests explicitly fire the production hold callback. No wall-clock
    // timer is simulated, so scheduler speed cannot start an extra recording.
    public sealed class Timer : IDisposable
    {
        public int Interval { get; set; }
        public event EventHandler? Tick { add { } remove { } }
        public void Start() { }
        public void Stop() { }
        public void Dispose() { }
    }
    public enum TextDataFormat { UnicodeText }
    public sealed class DataObject
    {
        private readonly Dictionary<string, object> _data = new();
        public void SetText(string text, TextDataFormat format) => SetData("UnicodeText", text);
        public void SetData(string format, object value) => _data[format] = value;
        public object? GetData(string format) => _data.GetValueOrDefault(format);
    }
    public static class Clipboard
    {
        public static DataObject Data { get; private set; } = new();
        public static void SetDataObject(object data, bool copy, int retries, int delay) => Data = (DataObject)data;
        public static string GetText() => Data.GetData("UnicodeText") as string ?? "";
        public static void SetText(string text)
        {
            var data = new DataObject(); data.SetText(text, TextDataFormat.UnicodeText); Data = data;
        }
    }
}

namespace Inlaut.Platform.Windows
{
    public static class DirectTextInserter
    {
        public readonly record struct InputTarget(IntPtr Window, IntPtr Control);
        public static InputTarget Current { get; set; } = new(new IntPtr(1), new IntPtr(2));
        public static InputTarget CaptureTarget() => Current;
        public static void RequireTarget(InputTarget target)
        {
            if (target != Current) throw new InvalidOperationException("Simulated focus changed.");
        }
    }
    public static class NativeMethods
    {
        public const int INPUT_KEYBOARD = 1, WH_KEYBOARD_LL = 13;
        public const uint KEYEVENTF_KEYUP = 2;
        public const int WM_KEYDOWN = 0x100, WM_KEYUP = 0x101, WM_SYSKEYDOWN = 0x104, WM_SYSKEYUP = 0x105;
        public const int VK_CONTROL = 0x11, VK_MENU = 0x12, VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3, VK_LMENU = 0xA4, VK_RMENU = 0xA5;
        public delegate IntPtr LowLevelKeyboardProc(int code, IntPtr message, IntPtr data);
        [StructLayout(LayoutKind.Sequential)]
        public struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public UIntPtr dwExtraInfo; }
        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT { public uint type; public InputUnion u; }
        [StructLayout(LayoutKind.Sequential)]
        public struct InputUnion { public KEYBDINPUT ki; }
        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public UIntPtr dwExtraInfo; }
        public static Func<INPUT[], uint>? InputQueue { get; set; }
        public static uint SendInput(uint count, INPUT[] inputs, int size) => InputQueue?.Invoke(inputs) ?? count;
        public static short GetAsyncKeyState(int key) => 0;
        public static IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data) => IntPtr.Zero;
        public static IntPtr SetWindowsHookEx(int type, LowLevelKeyboardProc callback, IntPtr module, uint thread) => throw new NotSupportedException("Native hooks are not simulated.");
        public static bool UnhookWindowsHookEx(IntPtr hook) => true;
        public static IntPtr GetModuleHandle(string? module) => IntPtr.Zero;
    }
}
