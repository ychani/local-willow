using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace LocalWillow;

public sealed record HistoryItem(Guid Id, string Text, DateTime Date);

/// Last 20 dictations, persisted locally. Nothing leaves the machine.
public sealed class HistoryStore
{
    public static HistoryStore Shared { get; } = new();

    private static readonly string HistoryPath = Path.Combine(Log.Dir, "history.json");
    private readonly List<HistoryItem> _items = new();

    public IReadOnlyList<HistoryItem> Items => _items;

    private HistoryStore()
    {
        try
        {
            if (File.Exists(HistoryPath))
            {
                var loaded = JsonSerializer.Deserialize<List<HistoryItem>>(File.ReadAllText(HistoryPath));
                if (loaded != null) _items = loaded;
            }
        }
        catch (Exception e)
        {
            Log.Write($"history: load failed — {e.Message}");
        }
    }

    public void Add(string text)
    {
        _items.Insert(0, new HistoryItem(Guid.NewGuid(), text, DateTime.Now));
        if (_items.Count > 20) _items.RemoveRange(20, _items.Count - 20);
        Persist();
    }

    public void Clear()
    {
        _items.Clear();
        Persist();
    }

    private void Persist()
    {
        try
        {
            Directory.CreateDirectory(Log.Dir);
            File.WriteAllText(HistoryPath, JsonSerializer.Serialize(_items));
        }
        catch (Exception e)
        {
            Log.Write($"history: save failed — {e.Message}");
        }
    }
}
