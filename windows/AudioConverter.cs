using System;
using System.IO;
using NAudio.Wave;

namespace LocalWillow;

/// Converts an arbitrary audio file (m4a, mp3, wav, wma, aac, mp4…) into the
/// 16 kHz mono 16-bit WAV that whisper-server expects, using Windows Media
/// Foundation (no external dependencies). The original file is never touched;
/// output goes to a temp file the caller is responsible for removing.
public static class AudioConverter
{
    /// Filter for the open-file dialog.
    public const string DialogFilter =
        "Audio files|*.wav;*.mp3;*.m4a;*.m4b;*.aac;*.mp4;*.wma;*.flac;*.ogg;*.opus|All files|*.*";

    /// Returns a temp WAV path; delete it when done.
    public static string ToWhisperWav(string sourcePath)
    {
        var outPath = Path.Combine(Path.GetTempPath(), $"localwillow-{Guid.NewGuid()}.wav");
        try
        {
            using var reader = new MediaFoundationReader(sourcePath);
            using var resampler = new MediaFoundationResampler(reader, new WaveFormat(16000, 16, 1))
            {
                ResamplerQuality = 60,
            };
            WaveFileWriter.CreateWaveFile(outPath, resampler);
            return outPath;
        }
        catch (Exception e)
        {
            try { File.Delete(outPath); } catch { }
            throw new InvalidOperationException($"Couldn't read this audio file — {e.Message}", e);
        }
    }
}
