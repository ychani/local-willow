using System;
using System.IO;

namespace LocalWillow;

/// Catalog of downloadable Whisper models (multilingual variants only —
/// needed for EN/KO switching). Files live in %LOCALAPPDATA%\LocalWillow\models.
public sealed class WhisperModel
{
    public string Name { get; }
    public string SizeLabel { get; }
    public string Note { get; }

    private WhisperModel(string name, string sizeLabel, string note)
    {
        Name = name;
        SizeLabel = sizeLabel;
        Note = note;
    }

    public string FileName => $"ggml-{Name}.bin";
    public string FilePath => Path.Combine(Config.DataDir, "models", FileName);
    public bool Downloaded => File.Exists(FilePath);
    public string Url => $"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{FileName}";
    public string Label =>
        $"{Name} ({SizeLabel}) - {Note}" + (Downloaded ? "  [downloaded]" : "");

    public static readonly WhisperModel[] All =
    {
        new("large-v3-turbo-q5_0", "547 MB", "best accuracy"),
        new("medium-q5_0", "514 MB", "high accuracy, slower"),
        new("small", "466 MB", "good balance"),
        new("small-q5_1", "181 MB", "good balance, compact"),
        new("base", "142 MB", "fast, lighter accuracy"),
        new("tiny", "75 MB", "fastest, lowest accuracy"),
    };
}
