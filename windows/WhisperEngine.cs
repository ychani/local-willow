using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace LocalWillow;

/// Manages a localhost whisper-server child process (model stays warm in memory)
/// and transcribes WAV files against it. The child is placed in a kill-on-close
/// job object so it can never outlive the app, even on a crash.
public sealed class WhisperEngine
{
    private Process? _process;
    private const int Port = 8178;
    private static readonly HttpClient Http = new() { Timeout = Timeout.InfiniteTimeSpan };

    public string? LastError { get; private set; }

    public bool IsRunning => _process is { HasExited: false };

    /// Kills any whisper-server left behind by a previous crashed/killed run.
    private static void ReapOrphans()
    {
        foreach (var p in Process.GetProcessesByName("whisper-server"))
        {
            try { p.Kill(); p.WaitForExit(2000); }
            catch { /* already gone or not ours to kill */ }
            finally { p.Dispose(); }
        }
    }

    public void Start()
    {
        if (IsRunning) return;
        ReapOrphans();
        var cfg = Config.Shared;
        if (!File.Exists(cfg.WhisperServerPath))
        {
            LastError = $"whisper-server not found at {cfg.WhisperServerPath} — run setup.ps1";
            Log.Write($"engine: {LastError}");
            return;
        }
        if (!File.Exists(cfg.ModelPath))
        {
            LastError = $"Model not found at {cfg.ModelPath} — run setup.ps1";
            Log.Write($"engine: {LastError}");
            return;
        }

        var psi = new ProcessStartInfo
        {
            FileName = cfg.WhisperServerPath,
            WorkingDirectory = Path.GetDirectoryName(cfg.WhisperServerPath) ?? "",
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        psi.ArgumentList.Add("-m"); psi.ArgumentList.Add(cfg.ModelPath);
        psi.ArgumentList.Add("-l"); psi.ArgumentList.Add(cfg.Language);
        psi.ArgumentList.Add("--host"); psi.ArgumentList.Add("127.0.0.1");
        psi.ArgumentList.Add("--port"); psi.ArgumentList.Add(Port.ToString());
        var vocab = cfg.Vocabulary;
        if (vocab.Count > 0)
        {
            psi.ArgumentList.Add("--prompt");
            psi.ArgumentList.Add("Glossary: " + string.Join(", ", vocab) + ".");
            psi.ArgumentList.Add("--carry-initial-prompt");
        }

        try
        {
            var p = Process.Start(psi);
            if (p == null) throw new InvalidOperationException("Process.Start returned null");
            ChildJob.Attach(p);
            _process = p;
            LastError = null;
            Log.Write($"engine: whisper-server started, pid {p.Id}");

            // A bad argument (e.g. invalid language) makes it exit within ms — catch
            // that and say so instead of failing silently at the next dictation.
            _ = Task.Delay(2000).ContinueWith(_ =>
            {
                if (_process == p && p.HasExited)
                {
                    LastError = "Transcription engine exited right after launch — check language/model settings";
                    Log.Write($"engine: {LastError} (exit code {p.ExitCode})");
                }
            });
        }
        catch (Exception e)
        {
            LastError = $"Failed to launch whisper-server: {e.Message}";
            Log.Write($"engine: launch FAILED — {e.Message}");
        }
    }

    public void Stop()
    {
        try
        {
            if (_process is { HasExited: false }) _process.Kill();
        }
        catch { }
        _process?.Dispose();
        _process = null;
        ReapOrphans();
    }

    /// Restart to pick up changed model/language/vocabulary settings.
    public void Restart()
    {
        Stop();
        _ = Task.Delay(500).ContinueWith(_ => Start());
    }

    /// Transcribes a WAV file; deletes it when done. Retries briefly while the
    /// server is still loading the model after launch.
    public async Task<string> Transcribe(string wavPath, TimeSpan? timeout = null)
    {
        try
        {
            if (!IsRunning) Start();
            if (!IsRunning && LastError != null) throw new InvalidOperationException(LastError);

            var wavBytes = await File.ReadAllBytesAsync(wavPath);
            for (int attempt = 0; ; attempt++)
            {
                using var form = new MultipartFormDataContent();
                form.Add(new StringContent("json"), "response_format");
                form.Add(new StringContent("0.0"), "temperature");
                var file = new ByteArrayContent(wavBytes);
                file.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("audio/wav");
                form.Add(file, "file", "audio.wav");

                using var cts = new CancellationTokenSource(timeout ?? TimeSpan.FromSeconds(120));
                try
                {
                    var resp = await Http.PostAsync($"http://127.0.0.1:{Port}/inference", form, cts.Token);
                    var body = await resp.Content.ReadAsStringAsync(cts.Token);
                    using var json = JsonDocument.Parse(body);
                    if (json.RootElement.TryGetProperty("error", out var err))
                        throw new InvalidOperationException(err.GetString() ?? "whisper-server error");
                    if (!json.RootElement.TryGetProperty("text", out var text))
                        throw new InvalidOperationException("Bad response from whisper-server");
                    return (text.GetString() ?? "").Trim();
                }
                catch (HttpRequestException) when (attempt < 40)
                {
                    // Server not accepting connections yet — model still loading.
                    await Task.Delay(500);
                }
                catch (SocketException) when (attempt < 40)
                {
                    await Task.Delay(500);
                }
            }
        }
        finally
        {
            try { File.Delete(wavPath); } catch { }
        }
    }
}

/// A Windows job object with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: children assigned
/// to it are terminated by the OS when this process exits for any reason.
internal static class ChildJob
{
    private static IntPtr _job = IntPtr.Zero;
    private static readonly object Gate = new();

    public static void Attach(Process p)
    {
        try
        {
            lock (Gate)
            {
                if (_job == IntPtr.Zero)
                {
                    _job = CreateJobObjectW(IntPtr.Zero, null);
                    if (_job == IntPtr.Zero) return;
                    var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                    info.BasicLimitInformation.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE
                    int len = Marshal.SizeOf<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>();
                    IntPtr ptr = Marshal.AllocHGlobal(len);
                    try
                    {
                        Marshal.StructureToPtr(info, ptr, false);
                        SetInformationJobObject(_job, 9 /*ExtendedLimitInformation*/, ptr, (uint)len);
                    }
                    finally { Marshal.FreeHGlobal(ptr); }
                }
            }
            AssignProcessToJobObject(_job, p.Handle);
        }
        catch (Exception e)
        {
            Log.Write($"engine: job object attach failed — {e.Message}");
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateJobObjectW(IntPtr lpJobAttributes, string? lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(IntPtr hJob, int infoClass,
                                                       IntPtr lpInfo, uint cbInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);
}
