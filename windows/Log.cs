using System;
using System.IO;

namespace LocalWillow;

/// Append-only diagnostic log at %APPDATA%\LocalWillow\LocalWillow.log.
public static class Log
{
    public static readonly string Dir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "LocalWillow");

    public static readonly string FilePath = Path.Combine(Dir, "LocalWillow.log");

    private static readonly object Gate = new();

    public static void Write(string msg)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Dir);
                File.AppendAllText(FilePath,
                    $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {msg}{Environment.NewLine}");
            }
        }
        catch
        {
            // Logging must never take the app down.
        }
    }
}
