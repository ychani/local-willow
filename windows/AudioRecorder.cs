using System;
using System.IO;
using NAudio.Wave;

namespace LocalWillow;

/// Captures the default microphone at 16 kHz mono Int16 (winmm resamples for us)
/// and reports a smoothed input level for the waveform overlay.
public sealed class AudioRecorder
{
    private WaveInEvent? _waveIn;
    private MemoryStream _samples = new();
    private readonly object _gate = new();

    public bool IsRecording { get; private set; }

    /// Called on a background thread with a 0..1 level.
    public Action<float>? OnLevel;

    public void Start()
    {
        if (IsRecording) return;
        if (WaveInEvent.DeviceCount == 0)
            throw new InvalidOperationException("No microphone found");

        lock (_gate) _samples = new MemoryStream();

        var waveIn = new WaveInEvent
        {
            WaveFormat = new WaveFormat(16000, 16, 1),
            BufferMilliseconds = 50,
        };
        waveIn.DataAvailable += (_, e) =>
        {
            lock (_gate) _samples.Write(e.Buffer, 0, e.BytesRecorded);

            // Level for the overlay (RMS of the int16 buffer).
            double sum = 0;
            int n = e.BytesRecorded / 2;
            for (int i = 0; i < n; i++)
            {
                short s = BitConverter.ToInt16(e.Buffer, i * 2);
                double f = s / 32768.0;
                sum += f * f;
            }
            float rms = (float)Math.Sqrt(sum / Math.Max(n, 1));
            OnLevel?.Invoke(Math.Min(1.0f, rms * 12));
        };
        waveIn.StartRecording();
        _waveIn = waveIn;
        IsRecording = true;
    }

    /// Stops capture and returns a WAV file path, or null if the take was too short.
    public string? Stop()
    {
        if (!IsRecording) return null;
        IsRecording = false;
        try
        {
            _waveIn?.StopRecording();
            _waveIn?.Dispose();
        }
        catch (Exception e)
        {
            Log.Write($"record: stop error — {e.Message}");
        }
        _waveIn = null;

        byte[] audio;
        lock (_gate)
        {
            audio = _samples.ToArray();
            _samples = new MemoryStream();
        }

        // Under ~0.3 s is an accidental tap, not dictation.
        if (audio.Length < (int)(16000 * 0.3) * 2) return null;

        var path = Path.Combine(Path.GetTempPath(), $"willow-{Guid.NewGuid()}.wav");
        File.WriteAllBytes(path, WavData(audio));
        return path;
    }

    private static byte[] WavData(byte[] pcm)
    {
        using var ms = new MemoryStream();
        using var w = new BinaryWriter(ms);
        w.Write("RIFF"u8);
        w.Write((uint)(36 + pcm.Length));
        w.Write("WAVE"u8);
        w.Write("fmt "u8);
        w.Write(16u);
        w.Write((ushort)1);       // PCM
        w.Write((ushort)1);       // mono
        w.Write(16000u);          // sample rate
        w.Write(16000u * 2);      // byte rate
        w.Write((ushort)2);       // block align
        w.Write((ushort)16);      // bits per sample
        w.Write("data"u8);
        w.Write((uint)pcm.Length);
        w.Write(pcm);
        w.Flush();
        return ms.ToArray();
    }
}
