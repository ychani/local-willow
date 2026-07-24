using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace LocalWillow;

public enum Hotkey
{
    RightAlt,
    RightCtrl,
    RightShift,
    F9,
    F13,
    ScrollLock,
    Pause,
}

public static class HotkeyInfo
{
    public static string Label(this Hotkey hk) => hk switch
    {
        Hotkey.RightAlt => "Right Alt",
        Hotkey.RightCtrl => "Right Ctrl",
        Hotkey.RightShift => "Right Shift",
        Hotkey.F9 => "F9",
        Hotkey.F13 => "F13",
        Hotkey.ScrollLock => "Scroll Lock",
        Hotkey.Pause => "Pause/Break",
        _ => hk.ToString(),
    };

    /// Virtual-key codes that count as this hotkey. Korean keyboard layouts report
    /// Right Alt as VK_HANGUL (0x15) and Right Ctrl as VK_HANJA (0x19), so those
    /// are accepted as aliases — the physical key is the same.
    public static int[] VirtualKeys(this Hotkey hk) => hk switch
    {
        Hotkey.RightAlt => new[] { 0xA5, 0x15 },   // VK_RMENU, VK_HANGUL
        Hotkey.RightCtrl => new[] { 0xA3, 0x19 },  // VK_RCONTROL, VK_HANJA
        Hotkey.RightShift => new[] { 0xA1 },       // VK_RSHIFT
        Hotkey.F9 => new[] { 0x78 },               // VK_F9
        Hotkey.F13 => new[] { 0x7C },              // VK_F13
        Hotkey.ScrollLock => new[] { 0x91 },       // VK_SCROLL
        Hotkey.Pause => new[] { 0x13 },            // VK_PAUSE
        _ => Array.Empty<int>(),
    };
}

/// Persistent settings, stored as JSON at %APPDATA%\LocalWillow\config.json.
public sealed class Config
{
    public static Config Shared { get; } = Load();

    private static readonly string ConfigPath = Path.Combine(Log.Dir, "config.json");

    // -- Persisted fields (JSON) ------------------------------------------------

    [JsonPropertyName("hotkey")]
    public string HotkeyRaw { get; set; } = "RightAlt";

    [JsonPropertyName("toggleDictation")]
    public bool ToggleDictation { get; set; } = false;

    [JsonPropertyName("language")]
    public string LanguageRaw { get; set; } = "auto";

    [JsonPropertyName("removeFillers")]
    public bool RemoveFillers { get; set; } = true;

    [JsonPropertyName("sounds")]
    public bool Sounds { get; set; } = true;

    [JsonPropertyName("aiMode")]
    public bool AiMode { get; set; } = false;

    [JsonPropertyName("ollamaModel")]
    public string OllamaModel { get; set; } = "llama3.2:3b";

    [JsonPropertyName("modelPath")]
    public string ModelPath { get; set; } = DefaultModelPath;

    [JsonPropertyName("whisperServerPath")]
    public string WhisperServerPath { get; set; } = DefaultServerPath;

    /// One term per line; biases Whisper toward personal names/jargon.
    [JsonPropertyName("vocabulary")]
    public string VocabularyRaw { get; set; } = "";

    /// Lines of "wrong -> right".
    [JsonPropertyName("replacements")]
    public string ReplacementsRaw { get; set; } = "";

    /// WASAPI endpoint ID of the microphone to record from; "" = system default.
    /// Lets dictation use e.g. the laptop mic while a speakerphone stays the
    /// Windows default for calls.
    [JsonPropertyName("micDeviceId")]
    public string MicDeviceId { get; set; } = "";

    // -- Derived ---------------------------------------------------------------

    public static string DefaultModelPath =>
        Path.Combine(AppContext.BaseDirectory, "models", "ggml-large-v3-turbo-q5_0.bin");

    public static string DefaultServerPath =>
        Path.Combine(AppContext.BaseDirectory, "engine", "whisper-server.exe");

    [JsonIgnore]
    public Hotkey Hotkey
    {
        get => Enum.TryParse<Hotkey>(HotkeyRaw, out var hk) ? hk : Hotkey.RightAlt;
        set => HotkeyRaw = value.ToString();
    }

    /// An empty/garbage value makes whisper-server exit at launch — never pass one.
    [JsonIgnore]
    public string Language
    {
        get
        {
            var v = (LanguageRaw ?? "").Trim().ToLowerInvariant();
            return v.Length == 2 || v == "auto" ? v : "en";
        }
    }

    /// Human phrase for how to trigger dictation, matching the current mode.
    [JsonIgnore]
    public string ActionHint => (ToggleDictation ? "Press " : "Hold ") + Hotkey.Label();

    [JsonIgnore]
    public List<string> Vocabulary =>
        (VocabularyRaw ?? "").Split('\n')
            .Select(s => s.Trim())
            .Where(s => s.Length > 0)
            .ToList();

    [JsonIgnore]
    public List<(string Wrong, string Right)> Replacements =>
        (ReplacementsRaw ?? "").Split('\n')
            .Select(line => line.Split("->", 2))
            .Where(p => p.Length == 2 && p[0].Trim().Length > 0)
            .Select(p => (p[0].Trim(), p[1].Trim()))
            .ToList();

    // -- Load/save -------------------------------------------------------------

    private static Config Load()
    {
        try
        {
            if (File.Exists(ConfigPath))
            {
                var cfg = JsonSerializer.Deserialize<Config>(File.ReadAllText(ConfigPath));
                if (cfg != null) return cfg;
            }
        }
        catch (Exception e)
        {
            Log.Write($"config: load failed, using defaults — {e.Message}");
        }
        return new Config();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Log.Dir);
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(
                this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception e)
        {
            Log.Write($"config: save failed — {e.Message}");
        }
    }
}
