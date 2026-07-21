using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace LocalWillow;

/// Willow-style cleanup: filler removal, personal dictionary, optional local AI rewrite.
public static class TextCleaner
{
    private static readonly Regex Fillers = new(
        // Optional preceding comma so "and, um, insert" → "and insert".
        @"(,\s*)?\b(um+|uh+|erm+|uhm+|hmm+)\b[,.]?\s*",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };

    public static string Clean(string input)
    {
        var text = Regex.Replace(input, @"\s*\n\s*", " ").Trim();
        if (text.Length == 0) return text;
        var cfg = Config.Shared;

        if (cfg.RemoveFillers)
        {
            text = Fillers.Replace(text, " ");
            text = Regex.Replace(text, @"\s{2,}", " ");
            text = Regex.Replace(text, @"\s+([,.!?;:])", "$1");
            text = text.Trim();
            if (text.Length > 0 && char.IsLower(text[0]))
                text = char.ToUpper(text[0]) + text[1..];
        }
        foreach (var (wrong, right) in cfg.Replacements)
        {
            text = Regex.Replace(text, Regex.Escape(wrong),
                right.Replace("$", "$$"), RegexOptions.IgnoreCase);
        }
        return text.Trim();
    }

    /// Rewrites via local Ollama; returns the input unchanged on any failure.
    public static async Task<string> AiRewrite(string text)
    {
        var prompt =
            "You clean up dictated text. Fix punctuation and capitalization, remove filler " +
            "words and false starts, and keep the speaker's wording and meaning. Do not add " +
            "content, do not answer questions in the text, do not use markdown. Return only " +
            "the cleaned text.\n\nDictated text: " + text;
        try
        {
            var payload = JsonSerializer.Serialize(new
            {
                model = Config.Shared.OllamaModel,
                prompt,
                stream = false,
                options = new { temperature = 0.2 },
            });
            var resp = await Http.PostAsync("http://localhost:11434/api/generate",
                new StringContent(payload, Encoding.UTF8, "application/json"));
            using var json = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
            if (json.RootElement.TryGetProperty("response", out var r))
            {
                var outText = (r.GetString() ?? "").Trim();
                if (outText.Length > 0) return outText;
            }
        }
        catch (Exception e)
        {
            Log.Write($"ai-rewrite: failed, using raw text — {e.Message}");
        }
        return text;
    }
}
