using System;
using System.Threading;
using System.Windows.Forms;

namespace LocalWillow;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        // Single-instance guard: two copies would each install a keyboard hook,
        // so every dictation would be recorded — and pasted — twice.
        using var mutex = new Mutex(true, @"Local\LocalWillowSingleInstance", out bool isNew);
        if (!isNew)
        {
            Log.Write("launch: another instance already running — exiting");
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayAppContext());
    }
}
