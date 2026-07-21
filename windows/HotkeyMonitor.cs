using System;
using System.Linq;
using System.Runtime.InteropServices;

namespace LocalWillow;

/// Global hold-to-talk hotkey via a low-level keyboard hook (WH_KEYBOARD_LL).
/// Listen-only: events are always passed through. No special permissions are
/// required on Windows. Install from the UI thread (the hook needs its message pump).
public sealed class HotkeyMonitor : IDisposable
{
    public Action? OnPress;
    public Action? OnRelease;
    /// Esc pressed while a take is active — abort the dictation.
    public Action? OnCancel;
    /// Whether a dictation take is currently in progress. In toggle mode the
    /// hotkey isn't physically held, so `_held` alone can't gate Esc-cancel.
    public Func<bool>? IsTakeActive;

    private IntPtr _hook = IntPtr.Zero;
    private LowLevelKeyboardProc? _proc;  // kept alive so the GC can't collect the callback
    private bool _held;

    public bool IsActive => _hook != IntPtr.Zero;

    public bool Start()
    {
        if (IsActive) return true;
        _proc = HookCallback;
        _hook = SetWindowsHookExW(WH_KEYBOARD_LL, _proc, GetModuleHandleW(null), 0);
        if (_hook == IntPtr.Zero)
        {
            Log.Write($"hotkey: SetWindowsHookEx failed (error {Marshal.GetLastWin32Error()})");
            return false;
        }
        Log.Write("hotkey: low-level keyboard hook active");
        return true;
    }

    public void Stop()
    {
        if (_hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
        _proc = null;
        _held = false;
    }

    public void Dispose() => Stop();

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            try { Handle((int)wParam, Marshal.ReadInt32(lParam)); }
            catch (Exception e) { Log.Write($"hotkey: handler error — {e.Message}"); }
        }
        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private void Handle(int message, int vkCode)
    {
        bool down = message is WM_KEYDOWN or WM_SYSKEYDOWN;
        bool up = message is WM_KEYUP or WM_SYSKEYUP;
        if (!down && !up) return;

        // Esc cancels an active take — while physically held (push-to-talk) or
        // while a toggle take is running (key not held).
        if (vkCode == VK_ESCAPE && down && (_held || IsTakeActive?.Invoke() == true))
        {
            _held = false;
            Log.Write("hotkey: cancelled with Esc");
            OnCancel?.Invoke();
            return;
        }

        if (!Config.Shared.Hotkey.VirtualKeys().Contains(vkCode)) return;
        Transition(down);
    }

    private void Transition(bool down)
    {
        if (down && !_held)
        {
            _held = true;
            Log.Write("hotkey: pressed");
            OnPress?.Invoke();
        }
        else if (!down && _held)
        {
            _held = false;
            Log.Write("hotkey: released");
            OnRelease?.Invoke();
        }
    }

    // -- Win32 -----------------------------------------------------------------

    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const int VK_ESCAPE = 0x1B;

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookExW(int idHook, LowLevelKeyboardProc lpfn,
                                                   IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandleW(string? lpModuleName);
}
