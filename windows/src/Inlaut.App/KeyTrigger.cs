using System.Diagnostics;
using System.Runtime.InteropServices;
using Inlaut.Platform.Windows;

namespace Inlaut.App;

public class KeyTrigger : IDisposable
{
    public Action? OnStart { get; set; }
    public Action? OnStop { get; set; }

    private uint _triggerVkCode;
    private Action<uint>? _captureCallback;

    private enum Phase { Idle, Pressed, Holding, HandsFree }
    private Phase _phase = Phase.Idle;
    private DateTime _lastTapAt = DateTime.MinValue;
    private readonly TimeSpan _doubleTapWindow = TimeSpan.FromMilliseconds(400);
    private readonly int _holdDelayMs = 220;

    private System.Threading.Timer? _holdTimer;
    private bool _ignoreNextRelease = false;

    private IntPtr _hookId = IntPtr.Zero;
    private NativeMethods.LowLevelKeyboardProc? _proc;
    private readonly SynchronizationContext? _syncContext;

    public KeyTrigger(uint initialTriggerVkCode = 0xA2) // Default: VK_LCONTROL
    {
        _triggerVkCode = initialTriggerVkCode;
        _syncContext = SynchronizationContext.Current;
        _holdTimer = new System.Threading.Timer(OnHoldTimerFired, null, Timeout.Infinite, Timeout.Infinite);
    }

    public void UpdateTriggerKey(uint newVkCode)
    {
        _triggerVkCode = newVkCode;
        _phase = Phase.Idle;
        _holdTimer?.Change(Timeout.Infinite, Timeout.Infinite);
    }

    public void SetCaptureMode(Action<uint> callback)
    {
        _captureCallback = callback;
    }

    public void EndCaptureMode()
    {
        _captureCallback = null;
    }

    public void Start()
    {
        if (_hookId != IntPtr.Zero) return;

        _proc = HookCallback;
        using var curProcess = Process.GetCurrentProcess();
        using var curModule = curProcess.MainModule;
        IntPtr moduleHandle = NativeMethods.GetModuleHandle(curModule?.ModuleName);
        _hookId = NativeMethods.SetWindowsHookEx(NativeMethods.WH_KEYBOARD_LL, _proc, moduleHandle, 0);
    }

    public void Stop()
    {
        if (_hookId != IntPtr.Zero)
        {
            NativeMethods.UnhookWindowsHookEx(_hookId);
            _hookId = IntPtr.Zero;
        }

        _holdTimer?.Change(Timeout.Infinite, Timeout.Infinite);
        _phase = Phase.Idle;
    }

    private bool MatchesTrigger(uint vkCode, uint flags)
    {
        // 1. Direct match with configured vkCode
        if (vkCode == _triggerVkCode) return true;

        // 2. Specific modifier subtleties
        if (_triggerVkCode == (uint)NativeMethods.VK_RCONTROL)
        {
            if (vkCode == (uint)NativeMethods.VK_CONTROL && (flags & 0x01) != 0) return true;
        }
        else if (_triggerVkCode == (uint)NativeMethods.VK_LCONTROL)
        {
            if (vkCode == (uint)NativeMethods.VK_CONTROL && (flags & 0x01) == 0) return true;
        }
        else if (_triggerVkCode == (uint)NativeMethods.VK_RMENU)
        {
            if (vkCode == (uint)NativeMethods.VK_MENU && (flags & 0x01) != 0) return true;
        }
        else if (_triggerVkCode == (uint)NativeMethods.VK_LMENU)
        {
            if (vkCode == (uint)NativeMethods.VK_MENU && (flags & 0x01) == 0) return true;
        }

        return false;
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var hookStruct = Marshal.PtrToStructure<NativeMethods.KBDLLHOOKSTRUCT>(lParam);
            int msg = wParam.ToInt32();

            // Key capture mode (for settings window)
            if (_captureCallback != null && (msg == NativeMethods.WM_KEYDOWN || msg == NativeMethods.WM_SYSKEYDOWN))
            {
                uint capturedVk = hookStruct.vkCode;
                // Refine generic modifier vkCodes to Left/Right
                if (capturedVk == (uint)NativeMethods.VK_CONTROL)
                {
                    capturedVk = (hookStruct.flags & 0x01) != 0 ? (uint)NativeMethods.VK_RCONTROL : (uint)NativeMethods.VK_LCONTROL;
                }
                else if (capturedVk == (uint)NativeMethods.VK_MENU)
                {
                    capturedVk = (hookStruct.flags & 0x01) != 0 ? (uint)NativeMethods.VK_RMENU : (uint)NativeMethods.VK_LMENU;
                }

                _captureCallback(capturedVk);
                return (IntPtr)1; // Consume key during capture
            }

            if (MatchesTrigger(hookStruct.vkCode, hookStruct.flags))
            {
                if (msg == NativeMethods.WM_KEYDOWN || msg == NativeMethods.WM_SYSKEYDOWN)
                {
                    HandleKeyDown();
                }
                else if (msg == NativeMethods.WM_KEYUP || msg == NativeMethods.WM_SYSKEYUP)
                {
                    HandleKeyUp();
                }
            }
            else
            {
                // Another key was pressed while holding our trigger key!
                // For example, user pressed Ctrl+C or Ctrl+V -> abort dictation trigger so shortcut functions normally!
                if ((msg == NativeMethods.WM_KEYDOWN || msg == NativeMethods.WM_SYSKEYDOWN) &&
                    (_phase == Phase.Pressed || _phase == Phase.Holding))
                {
                    _holdTimer?.Change(Timeout.Infinite, Timeout.Infinite);
                    if (_phase == Phase.Holding)
                    {
                        // Cancel dictation
                        TriggerStop();
                    }
                    _phase = Phase.Idle;
                    _lastTapAt = DateTime.MinValue;
                }
            }
        }

        return NativeMethods.CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private void HandleKeyDown()
    {
        // Ignore key repeat while holding
        if (_phase == Phase.Holding || _phase == Phase.Pressed)
        {
            return;
        }

        if (_phase == Phase.HandsFree)
        {
            // A single tap finishes hands-free dictation
            _phase = Phase.Idle;
            _ignoreNextRelease = true;
            _holdTimer?.Change(Timeout.Infinite, Timeout.Infinite);
            TriggerStop();
            return;
        }

        // Check for double-tap from idle
        if (_phase == Phase.Idle && (DateTime.UtcNow - _lastTapAt) < _doubleTapWindow)
        {
            _phase = Phase.HandsFree;
            _ignoreNextRelease = true;
            _lastTapAt = DateTime.MinValue;
            _holdTimer?.Change(Timeout.Infinite, Timeout.Infinite);
            TriggerStart();
            return;
        }

        // First tap / press
        _phase = Phase.Pressed;
        _holdTimer?.Change(_holdDelayMs, Timeout.Infinite);
    }

    private void HandleKeyUp()
    {
        if (_ignoreNextRelease)
        {
            _ignoreNextRelease = false;
            return;
        }

        if (_phase == Phase.Holding)
        {
            // Let go after holding -> finish dictation
            _phase = Phase.Idle;
            _holdTimer?.Change(Timeout.Infinite, Timeout.Infinite);
            TriggerStop();
            return;
        }

        if (_phase == Phase.Pressed)
        {
            // Released before holdDelay -> it was a single tap!
            _holdTimer?.Change(Timeout.Infinite, Timeout.Infinite);
            _phase = Phase.Idle;
            _lastTapAt = DateTime.UtcNow; // Wait for potential second tap
            return;
        }
    }

    private void OnHoldTimerFired(object? state)
    {
        if (_phase == Phase.Pressed)
        {
            _phase = Phase.Holding;
            TriggerStart();
        }
    }

    private void TriggerStart()
    {
        if (_syncContext != null)
        {
            _syncContext.Post(_ => OnStart?.Invoke(), null);
        }
        else
        {
            OnStart?.Invoke();
        }
    }

    private void TriggerStop()
    {
        if (_syncContext != null)
        {
            _syncContext.Post(_ => OnStop?.Invoke(), null);
        }
        else
        {
            OnStop?.Invoke();
        }
    }

    public void Dispose()
    {
        Stop();
        _holdTimer?.Dispose();
        _holdTimer = null;
    }
}
