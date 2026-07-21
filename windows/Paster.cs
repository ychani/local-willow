using System;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace LocalWillow;

/// Inserts text at the cursor of the foreground app: clipboard + synthetic Ctrl+V,
/// then restores the previous clipboard contents. Must be called on the UI thread.
public static class Paster
{
    public static void Paste(string text)
    {
        string? previous = null;
        try { if (Clipboard.ContainsText()) previous = Clipboard.GetText(); }
        catch { /* clipboard busy — skip restore */ }

        try { Clipboard.SetText(text); }
        catch (Exception e)
        {
            Log.Write($"paste: clipboard set failed — {e.Message}");
            return;
        }

        SendCtrlV();
        Log.Write($"paste: sent Ctrl+V ({text.Length} chars)");

        if (previous != null)
        {
            var restore = previous;
            _ = RestoreLater(restore);
        }
    }

    private static async Task RestoreLater(string previous)
    {
        await Task.Delay(500);  // continues on the UI thread (WinForms sync context)
        try { Clipboard.SetText(previous); } catch { }
    }

    private static void SendCtrlV()
    {
        var inputs = new INPUT[4];
        inputs[0] = Key(VK_CONTROL, down: true);
        inputs[1] = Key(VK_V, down: true);
        inputs[2] = Key(VK_V, down: false);
        inputs[3] = Key(VK_CONTROL, down: false);
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static INPUT Key(ushort vk, bool down) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = 0,
                dwFlags = down ? 0u : KEYEVENTF_KEYUP,
                time = 0,
                dwExtraInfo = IntPtr.Zero,
            },
        },
    };

    // -- Win32 -----------------------------------------------------------------

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_V = 0x56;

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
}
