using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Media;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace LocalWillow;

/// The application controller: tray icon + menu, dictation flow, settings window.
/// Mirrors the macOS AppDelegate.
public sealed class TrayAppContext : ApplicationContext
{
    private readonly NotifyIcon _tray;
    private readonly WhisperEngine _engine = new();
    private readonly AudioRecorder _recorder = new();
    private readonly HotkeyMonitor _hotkey = new();
    private readonly OverlayForm _overlay = new();
    private readonly ToolStripMenuItem _statusItem;
    private readonly ToolStripMenuItem _historyMenu;
    private readonly ToolStripMenuItem _aiItem;
    private readonly SynchronizationContext _ui;
    private SettingsForm? _settings;
    private bool _busy;

    public TrayAppContext()
    {
        _ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        Log.Write("launch: LocalWillow for Windows starting");

        var menu = new ContextMenuStrip();
        _statusItem = new ToolStripMenuItem("…") { Enabled = false };
        _historyMenu = new ToolStripMenuItem("Recent Dictations");
        _aiItem = new ToolStripMenuItem("AI Mode (Ollama rewrite)", null, (_, _) =>
        {
            Config.Shared.AiMode = !Config.Shared.AiMode;
            Config.Shared.Save();
        });
        menu.Items.Add(_statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_historyMenu);
        menu.Items.Add(_aiItem);
        menu.Items.Add(new ToolStripMenuItem("Transcribe Audio File…", null, (_, _) => TranscribeAudioFile()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Settings…", null, (_, _) => OpenSettings()));
        menu.Items.Add(new ToolStripMenuItem("Open Log Folder", null, (_, _) =>
        {
            try { Process.Start("explorer.exe", Log.Dir); } catch { }
        }));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit LocalWillow", null, (_, _) => Quit()));
        menu.Opening += (_, _) => RefreshMenu();

        _tray = new NotifyIcon
        {
            Icon = TrayIcons.Idle,
            Text = "LocalWillow",
            Visible = true,
            ContextMenuStrip = menu,
        };
        _tray.DoubleClick += (_, _) => OpenSettings();

        _engine.Start();
        _engine.OnStatus = status => _ui.Post(_ => _overlay.SetStatus(status), null);

        _recorder.OnLevel = level => _ui.Post(_ => _overlay.PushLevel(level), null);
        _hotkey.OnPress = () => _ui.Post(_ => HandleHotkeyPress(), null);
        _hotkey.OnRelease = () => _ui.Post(_ => HandleHotkeyRelease(), null);
        _hotkey.OnCancel = () => _ui.Post(_ => CancelDictation(), null);
        _hotkey.IsTakeActive = () => _recorder.IsRecording;
        _hotkey.Start();

        Notify($"Ready — {Config.Shared.ActionHint.ToLower()} to dictate");

        // First run: engine not set up yet → open Settings so the paths are visible.
        if (!File.Exists(Config.Shared.WhisperServerPath) || !File.Exists(Config.Shared.ModelPath))
            OpenSettings();
    }

    // -- Dictation flow --------------------------------------------------------

    /// Hotkey pressed. Push-to-talk starts a take; toggle mode starts if idle,
    /// otherwise finishes the running take.
    private void HandleHotkeyPress()
    {
        if (Config.Shared.ToggleDictation && _recorder.IsRecording) EndDictation();
        else BeginDictation();
    }

    /// Hotkey released. Ends the take only in push-to-talk mode; toggle mode
    /// keeps recording until the next press.
    private void HandleHotkeyRelease()
    {
        if (!Config.Shared.ToggleDictation) EndDictation();
    }

    private void BeginDictation()
    {
        if (_busy || _recorder.IsRecording) return;
        try
        {
            _recorder.Start();
            _tray.Icon = TrayIcons.Recording;
            _overlay.ShowPhase(OverlayForm.Phase.Recording);
            PlaySound(SystemSounds.Asterisk);
        }
        catch (Exception e)
        {
            Log.Write($"record: start failed — {e.Message}");
            Notify($"Couldn't start recording: {e.Message}");
        }
    }

    private void CancelDictation()
    {
        if (!_recorder.IsRecording) return;
        var wav = _recorder.Stop();
        if (wav != null) { try { File.Delete(wav); } catch { } }
        _overlay.HideOverlay();
        _tray.Icon = TrayIcons.Idle;
        PlaySound(SystemSounds.Hand);
    }

    private async void EndDictation()
    {
        if (!_recorder.IsRecording) return;
        var wav = _recorder.Stop();
        if (wav == null)
        {
            Log.Write("record: too short or empty, ignored");
            _overlay.HideOverlay();
            _tray.Icon = TrayIcons.Idle;
            return;
        }
        if (_recorder.LastPeak < 0.005f)
        {
            // The mic recorded but delivered essentially nothing — almost always a
            // wrong default device or Windows mic privacy blocking desktop apps.
            Log.Write($"record: silent take (peak {_recorder.LastPeak:F4}) — check default mic / privacy settings");
            try { File.Delete(wav); } catch { }
            _overlay.ShowError("No audio detected — check the default microphone in Windows Sound settings");
            _tray.Icon = TrayIcons.Idle;
            return;
        }
        Log.Write($"record: captured {RecordedSeconds(wav):F1}s");
        _busy = true;
        _tray.Icon = TrayIcons.Processing;
        _overlay.ShowPhase(OverlayForm.Phase.Processing);

        try
        {
            var t0 = DateTime.Now;
            var raw = await _engine.Transcribe(wav);
            Log.Write($"transcribe: {(int)(DateTime.Now - t0).TotalMilliseconds}ms, {raw.Length} chars");
            var text = TextCleaner.Clean(raw);
            if (Config.Shared.AiMode && text.Length > 0)
                text = await TextCleaner.AiRewrite(text);
            if (text.Length == 0)
            {
                Log.Write("transcribe: empty result (silence?)");
                _overlay.HideOverlay();
                return;
            }
            Paster.Paste(text);
            HistoryStore.Shared.Add(text);
            PlaySound(SystemSounds.Beep);
            _overlay.HideOverlay();
        }
        catch (Exception e)
        {
            Log.Write($"transcribe: FAILED — {e.Message}");
            // The overlay shows the error too — notifications can be suppressed
            // by Focus Assist, and a silent failure looks like a hang.
            _overlay.ShowError(e.Message);
            Notify($"Transcription failed: {e.Message}");
        }
        finally
        {
            _busy = false;
            _tray.Icon = TrayIcons.Idle;
        }
    }

    // -- Transcribe an existing audio file -------------------------------------

    private async void TranscribeAudioFile()
    {
        if (_busy || _recorder.IsRecording)
        {
            Notify("Busy — finish the current dictation first.");
            return;
        }
        using var dlg = new OpenFileDialog
        {
            Title = "Choose an audio file to transcribe",
            Filter = AudioConverter.DialogFilter,
        };
        if (dlg.ShowDialog() != DialogResult.OK) return;
        var source = dlg.FileName;

        _busy = true;
        _tray.Icon = TrayIcons.Processing;
        Notify($"Transcribing {Path.GetFileName(source)}…");
        try
        {
            var wav = await Task.Run(() => AudioConverter.ToWhisperWav(source));
            var t0 = DateTime.Now;
            // Files can be long; give the server a generous ceiling.
            var raw = await _engine.Transcribe(wav, TimeSpan.FromHours(1));
            Log.Write($"file-transcribe: {Path.GetFileName(source)} "
                + $"{(int)(DateTime.Now - t0).TotalMilliseconds}ms, {raw.Length} chars");
            var text = TextCleaner.Clean(raw);
            if (text.Length == 0)
            {
                Notify($"No speech found in {Path.GetFileName(source)}.");
                return;
            }
            try { Clipboard.SetText(text); } catch { }
            var dest = WriteTranscript(text, source);
            Notify(dest != null
                ? $"Saved {Path.GetFileName(dest)} · copied to clipboard"
                : $"Transcribed {Path.GetFileName(source)} · copied to clipboard (couldn't write a file next to it)");
        }
        catch (Exception e)
        {
            Log.Write($"file-transcribe: FAILED — {e.Message}");
            Notify($"Transcription failed: {e.Message}");
        }
        finally
        {
            _busy = false;
            _tray.Icon = TrayIcons.Idle;
        }
    }

    /// Writes the transcript beside the source as "<name>.txt", never overwriting
    /// an existing file (falls back to "<name> (2).txt", etc.).
    private static string? WriteTranscript(string text, string source)
    {
        try
        {
            var dir = Path.GetDirectoryName(source) ?? ".";
            var baseName = Path.GetFileNameWithoutExtension(source);
            var dest = Path.Combine(dir, baseName + ".txt");
            int n = 2;
            while (File.Exists(dest)) dest = Path.Combine(dir, $"{baseName} ({n++}).txt");
            File.WriteAllText(dest, text);
            return dest;
        }
        catch { return null; }
    }

    // -- Menu / settings -------------------------------------------------------

    private void RefreshMenu()
    {
        if (!File.Exists(Config.Shared.WhisperServerPath))
            _statusItem.Text = "⚠ whisper-server missing — run setup.ps1";
        else if (!File.Exists(Config.Shared.ModelPath))
            _statusItem.Text = "⚠ Model missing — run setup.ps1";
        else if (!_engine.IsRunning && _engine.LastError != null)
            _statusItem.Text = $"⚠ Engine stopped — {_engine.LastError}";
        else
            _statusItem.Text = $"{Config.Shared.ActionHint} to dictate · Esc cancels";

        _aiItem.Checked = Config.Shared.AiMode;

        _historyMenu.DropDownItems.Clear();
        var items = HistoryStore.Shared.Items;
        if (items.Count == 0)
        {
            _historyMenu.DropDownItems.Add(new ToolStripMenuItem("Nothing yet") { Enabled = false });
        }
        else
        {
            foreach (var h in items.Take(10))
            {
                var title = h.Text.Length > 60 ? h.Text[..57] + "…" : h.Text;
                var mi = new ToolStripMenuItem(title) { ToolTipText = "Click to copy" };
                var text = h.Text;
                mi.Click += (_, _) => { try { Clipboard.SetText(text); } catch { } };
                _historyMenu.DropDownItems.Add(mi);
            }
        }
    }

    private void OpenSettings()
    {
        if (_settings == null || _settings.IsDisposed)
        {
            _settings = new SettingsForm { OnEngineSettingsChanged = () => _engine.Restart() };
        }
        _settings.Show();
        _settings.WindowState = FormWindowState.Normal;
        _settings.Activate();
    }

    private void Quit()
    {
        _hotkey.Stop();
        _engine.Stop();
        _tray.Visible = false;
        ExitThread();
    }

    // -- Helpers ---------------------------------------------------------------

    private static double RecordedSeconds(string wavPath)
    {
        try { return Math.Max(0, new FileInfo(wavPath).Length - 44) / 32000.0; }
        catch { return 0; }
    }

    private void PlaySound(SystemSound sound)
    {
        if (Config.Shared.Sounds) sound.Play();
    }

    private void Notify(string message)
    {
        Log.Write($"notify: {message}");
        _tray.ShowBalloonTip(4000, "LocalWillow", message, ToolTipIcon.None);
    }
}
