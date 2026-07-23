using System;
using System.IO;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace LocalWillow;

/// Captures the Windows default microphone via WASAPI (the modern audio API —
/// follows the default-device setting and shows up in the mic privacy activity
/// list), converts to 16 kHz mono Int16 for whisper, and reports a smoothed
/// input level for the waveform overlay. Falls back to legacy winmm capture if
/// WASAPI fails.
public sealed class AudioRecorder
{
    private IWaveIn? _capture;
    private MMDevice? _device;
    private MemoryStream _samples = new();
    private readonly object _gate = new();
    private float _peak;
    private int _buffers;
    private bool _usingWasapi;
    /// Sticky for the app run: set when a WASAPI take dies or delivers nothing,
    /// so later takes go straight to the winmm fallback.
    private static bool _wasapiBroken;

    // Linear-resampler state, carried across buffers.
    private double _pos;
    private float _prevSample;
    private bool _hasPrev;
    private int _srcRate;
    private int _srcChannels;
    private bool _srcIsFloat;

    public bool IsRecording { get; private set; }

    /// Loudest raw sample (0..1) of the last take — ~0 means the mic was dead.
    public float LastPeak { get; private set; }

    /// Called on a background thread with a 0..1 level.
    public Action<float>? OnLevel;

    /// Capture died mid-take (device error). Called on a background thread.
    public Action<string>? OnError;

    public void Start()
    {
        if (IsRecording) return;
        lock (_gate) _samples = new MemoryStream();
        _peak = 0;
        _buffers = 0;
        _pos = 0;
        _hasPrev = false;

        if (_wasapiBroken)
        {
            StartWinmm();
        }
        else
        {
            try
            {
                StartWasapi();
            }
            catch (Exception e)
            {
                Log.Write($"record: WASAPI failed ({e.Message}) — falling back to winmm");
                _wasapiBroken = true;
                StartWinmm();
            }
        }
        IsRecording = true;
    }

    private void StartWasapi()
    {
        using var enumerator = new MMDeviceEnumerator();
        var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
        Log.Write($"record: WASAPI default mic: {device.FriendlyName}");

        // Event-driven mode: the recommended WASAPI mode; polling mode is known
        // to stall on some processed endpoints (echo-cancelling speakerphones etc.)
        var capture = new WasapiCapture(device, true, 50);
        var wf = capture.WaveFormat;
        _srcRate = wf.SampleRate;
        _srcChannels = Math.Max(1, wf.Channels);
        _srcIsFloat = wf.BitsPerSample == 32;
        if (!_srcIsFloat && wf.BitsPerSample != 16)
            throw new InvalidOperationException($"Unsupported capture format ({wf.BitsPerSample}-bit)");
        Log.Write($"record: capture format {_srcRate} Hz, {_srcChannels} ch, {wf.BitsPerSample}-bit, event-driven");

        capture.DataAvailable += (_, e) => ProcessBuffer(e.Buffer, e.BytesRecorded);
        capture.RecordingStopped += (_, e) =>
        {
            // NAudio reports capture-thread failures here; without this handler
            // a dying device looks like silence.
            if (e.Exception != null)
            {
                Log.Write($"record: WASAPI capture DIED — {e.Exception.Message}");
                _wasapiBroken = true;
                OnError?.Invoke($"Mic capture failed: {e.Exception.Message}");
            }
        };
        capture.StartRecording();
        _capture = capture;
        _device = device;
        _usingWasapi = true;
    }

    private void StartWinmm()
    {
        int count = WaveInEvent.DeviceCount;
        if (count == 0) throw new InvalidOperationException("No microphone found");
        for (int i = 0; i < count; i++)
        {
            try { Log.Write($"record: winmm device {i}: {WaveInEvent.GetCapabilities(i).ProductName}"); }
            catch { }
        }
        _srcRate = 16000;
        _srcChannels = 1;
        _srcIsFloat = false;
        // WAVE_MAPPER (-1, the default device) first; some drivers only open by index.
        Exception? last = null;
        foreach (int deviceNumber in new[] { -1, 0 })
        {
            var waveIn = new WaveInEvent
            {
                DeviceNumber = deviceNumber,
                WaveFormat = new WaveFormat(16000, 16, 1),
                BufferMilliseconds = 50,
            };
            waveIn.DataAvailable += (_, e) => ProcessBuffer(e.Buffer, e.BytesRecorded);
            waveIn.RecordingStopped += (_, e) =>
            {
                if (e.Exception != null)
                {
                    Log.Write($"record: winmm capture DIED — {e.Exception.Message}");
                    OnError?.Invoke($"Mic capture failed: {e.Exception.Message}");
                }
            };
            try
            {
                waveIn.StartRecording();
                Log.Write($"record: winmm capture on device {deviceNumber}");
                _capture = waveIn;
                _usingWasapi = false;
                return;
            }
            catch (Exception e)
            {
                last = e;
                Log.Write($"record: winmm device {deviceNumber} failed — {e.Message}");
                waveIn.Dispose();
            }
        }
        throw last ?? new InvalidOperationException("No usable microphone");
    }

    /// Downmixes to mono float, tracks level/peak, resamples to 16 kHz, appends Int16.
    private void ProcessBuffer(byte[] buffer, int bytes)
    {
        _buffers++;
        int bytesPerSample = _srcIsFloat ? 4 : 2;
        int frames = bytes / (bytesPerSample * _srcChannels);
        if (frames <= 0) return;

        var mono = new float[frames];
        double sum = 0;
        for (int f = 0; f < frames; f++)
        {
            float acc = 0;
            for (int c = 0; c < _srcChannels; c++)
            {
                int off = (f * _srcChannels + c) * bytesPerSample;
                acc += _srcIsFloat
                    ? BitConverter.ToSingle(buffer, off)
                    : BitConverter.ToInt16(buffer, off) / 32768.0f;
            }
            float s = acc / _srcChannels;
            mono[f] = s;
            sum += s * s;
            float a = Math.Abs(s);
            if (a > _peak) _peak = a;
        }
        float rms = (float)Math.Sqrt(sum / frames);
        OnLevel?.Invoke(Math.Min(1.0f, rms * 12));

        // Linear resample _srcRate -> 16000, phase carried across buffers.
        double step = _srcRate / 16000.0;
        int prev = _hasPrev ? 1 : 0;
        int vlen = frames + prev;
        float V(int i) => i < prev ? _prevSample : mono[i - prev];

        using var outStream = new MemoryStream();
        using var w = new BinaryWriter(outStream);
        while (_pos < vlen - 1)
        {
            int i0 = (int)_pos;
            double frac = _pos - i0;
            float s = (float)(V(i0) * (1 - frac) + V(i0 + 1) * frac);
            short q = (short)Math.Clamp((int)Math.Round(s * 32767f), short.MinValue, short.MaxValue);
            w.Write(q);
            _pos += step;
        }
        _pos -= vlen - 1;
        _prevSample = mono[frames - 1];
        _hasPrev = true;
        w.Flush();

        var chunk = outStream.ToArray();
        if (chunk.Length > 0)
            lock (_gate) _samples.Write(chunk, 0, chunk.Length);
    }

    /// Stops capture and returns a WAV file path, or null if the take was too short.
    public string? Stop()
    {
        if (!IsRecording) return null;
        IsRecording = false;
        try
        {
            _capture?.StopRecording();
            _capture?.Dispose();
            _device?.Dispose();
        }
        catch (Exception e)
        {
            Log.Write($"record: stop error — {e.Message}");
        }
        _capture = null;
        _device = null;

        byte[] audio;
        lock (_gate)
        {
            audio = _samples.ToArray();
            _samples = new MemoryStream();
        }
        LastPeak = _peak;
        Log.Write($"record: {(_usingWasapi ? "wasapi" : "winmm")} take — "
            + $"{_buffers} buffers, {audio.Length / 32000.0:F1}s, peak {LastPeak:F4}");
        if (_usingWasapi && _buffers == 0)
        {
            _wasapiBroken = true;
            Log.Write("record: WASAPI delivered no data — switching to winmm for the next take");
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
