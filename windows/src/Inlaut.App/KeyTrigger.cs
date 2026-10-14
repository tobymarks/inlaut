using System.Diagnostics;
using System.Runtime.InteropServices;
using Inlaut.Platform.Windows;

namespace Inlaut.App;

public class KeyTrigger : IDisposable
{
    public Action? OnStart { get; set; }
    public Action? OnStop { get; set; }

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

    public KeyTrigger()
    {
        _syncContext = SynchronizationContext.Current;
        _holdTimer = new System.Threading.Timer(OnHoldTimerFired, null, Timeout.Infinite, Timeout.Infinite);
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

    private bool IsTriggerKey(uint vkCode, uint flags)
    {
        // F8 Key
        if (vkCode == (uint)NativeMethods.VK_F8) return true;

        // Right Control: VK_RCONTROL (0xA3) or VK_CONTROL with LLKHF_EXTENDED (0x01)
        if (vkCode == (uint)NativeMethods.VK_RCONTROL) return true;
        if (vkCode == (uint)NativeMethods.VK_CONTROL && (flags & 0x01) != 0) return true;

        return false;
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var hookStruct = Marshal.PtrToStructure<NativeMethods.KBDLLHOOKSTRUCT>(lParam);

            if (IsTriggerKey(hookStruct.vkCode, hookStruct.flags))
            {
                int msg = wParam.ToInt32();

                if (msg == NativeMethods.WM_KEYDOWN || msg == NativeMethods.WM_SYSKEYDOWN)
                {
                    HandleKeyDown();
                }
                else if (msg == NativeMethods.WM_KEYUP || msg == NativeMethods.WM_SYSKEYUP)
                {
                    HandleKeyUp();
                }
            }
        }

        return NativeMethods.CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private void HandleKeyDown()
    {
        // Ignore key repeat while already holding or waiting
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
