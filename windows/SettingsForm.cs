using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using Microsoft.Win32;

namespace LocalWillow;

/// Settings window: General (hotkey, language, sounds, launch at login, AI mode,
/// engine paths), Dictionary (vocabulary + corrections), History (last 20).
public sealed class SettingsForm : Form
{
    /// Fired after saving settings that require an engine restart.
    public Action? OnEngineSettingsChanged;

    private readonly ComboBox _hotkey = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
    private readonly CheckBox _toggleMode = new() { Text = "Toggle mode (press to start, press again to stop)", AutoSize = true };
    private readonly TextBox _language = new() { Width = 200 };
    private readonly CheckBox _removeFillers = new() { Text = "Remove filler words (um, uh…)", AutoSize = true };
    private readonly CheckBox _sounds = new() { Text = "Play sounds", AutoSize = true };
    private readonly CheckBox _launchAtLogin = new() { Text = "Launch at login", AutoSize = true };
    private readonly CheckBox _aiMode = new() { Text = "AI mode (rewrite via local Ollama)", AutoSize = true };
    private readonly TextBox _ollamaModel = new() { Width = 200 };
    private readonly TextBox _modelPath = new() { Width = 320 };
    private readonly TextBox _serverPath = new() { Width = 320 };
    private readonly TextBox _vocabulary = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, AcceptsReturn = true };
    private readonly TextBox _replacements = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, AcceptsReturn = true };
    private readonly ListBox _history = new() { Dock = DockStyle.Fill, HorizontalScrollbar = true };

    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValue = "LocalWillow";

    public SettingsForm()
    {
        Text = "LocalWillow Settings";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = true;
        ClientSize = new Size(560, 480);
        Font = new Font("Segoe UI", 9.5f);

        var tabs = new TabControl { Dock = DockStyle.Fill };
        tabs.TabPages.Add(BuildGeneralTab());
        tabs.TabPages.Add(BuildDictionaryTab());
        tabs.TabPages.Add(BuildHistoryTab());

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            FlowDirection = FlowDirection.RightToLeft,
            Height = 44,
            Padding = new Padding(8),
        };
        var save = new Button { Text = "Save", Width = 90 };
        var cancel = new Button { Text = "Cancel", Width = 90 };
        save.Click += (_, _) => { SaveSettings(); Close(); };
        cancel.Click += (_, _) => Close();
        buttons.Controls.Add(save);
        buttons.Controls.Add(cancel);
        AcceptButton = save;
        CancelButton = cancel;

        Controls.Add(tabs);
        Controls.Add(buttons);

        LoadSettings();
    }

    private TabPage BuildGeneralTab()
    {
        var page = new TabPage("General");
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            Padding = new Padding(12),
            AutoScroll = true,
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        void Row(string label, Control control)
        {
            var l = new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 8, 8, 4) };
            control.Margin = new Padding(0, 5, 0, 4);
            layout.Controls.Add(l);
            layout.Controls.Add(control);
        }
        void Full(Control control)
        {
            control.Margin = new Padding(0, 4, 0, 0);
            layout.Controls.Add(new Label { AutoSize = true });
            layout.Controls.Add(control);
        }

        foreach (var hk in Enum.GetValues<Hotkey>()) _hotkey.Items.Add(hk.Label());
        Row("Hotkey", _hotkey);
        Full(_toggleMode);
        Row("Language", _language);
        Full(new Label
        {
            Text = "\"auto\" detects per dictation (EN/KO switching); or a fixed code: en, ko, …",
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
        });
        Full(_removeFillers);
        Full(_sounds);
        Full(_launchAtLogin);
        Full(_aiMode);
        Row("Ollama model", _ollamaModel);
        Row("Whisper model", WithBrowse(_modelPath, "Model files|*.bin|All files|*.*"));
        Row("whisper-server", WithBrowse(_serverPath, "Executables|*.exe|All files|*.*"));

        page.Controls.Add(layout);
        return page;
    }

    private Control WithBrowse(TextBox box, string filter)
    {
        var panel = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = Padding.Empty };
        var browse = new Button { Text = "…", Width = 32 };
        browse.Click += (_, _) =>
        {
            using var dlg = new OpenFileDialog { Filter = filter };
            if (dlg.ShowDialog(this) == DialogResult.OK) box.Text = dlg.FileName;
        };
        panel.Controls.Add(box);
        panel.Controls.Add(browse);
        return panel;
    }

    private TabPage BuildDictionaryTab()
    {
        var page = new TabPage("Dictionary");
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 4, ColumnCount = 1, Padding = new Padding(12) };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 50));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 50));
        layout.Controls.Add(new Label
        {
            Text = "Vocabulary — one term per line; biases the transcriber toward names/jargon:",
            AutoSize = true,
        });
        layout.Controls.Add(_vocabulary);
        layout.Controls.Add(new Label
        {
            Text = "Corrections — one \"heard -> replacement\" per line:",
            AutoSize = true,
            Margin = new Padding(3, 10, 3, 0),
        });
        layout.Controls.Add(_replacements);
        page.Controls.Add(layout);
        return page;
    }

    private TabPage BuildHistoryTab()
    {
        var page = new TabPage("History");
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 2, ColumnCount = 1, Padding = new Padding(12) };
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(_history);

        var buttons = new FlowLayoutPanel { AutoSize = true, Margin = new Padding(0, 8, 0, 0) };
        var copy = new Button { Text = "Copy selected", AutoSize = true };
        copy.Click += (_, _) =>
        {
            if (_history.SelectedIndex >= 0 && _history.SelectedIndex < HistoryStore.Shared.Items.Count)
                try { Clipboard.SetText(HistoryStore.Shared.Items[_history.SelectedIndex].Text); } catch { }
        };
        var clear = new Button { Text = "Clear history", AutoSize = true };
        clear.Click += (_, _) => { HistoryStore.Shared.Clear(); RefreshHistory(); };
        buttons.Controls.Add(copy);
        buttons.Controls.Add(clear);
        layout.Controls.Add(buttons);

        page.Controls.Add(layout);
        return page;
    }

    private void RefreshHistory()
    {
        _history.Items.Clear();
        foreach (var h in HistoryStore.Shared.Items)
            _history.Items.Add($"{h.Date:MM-dd HH:mm}  {h.Text}");
    }

    private void LoadSettings()
    {
        var cfg = Config.Shared;
        _hotkey.SelectedIndex = (int)cfg.Hotkey;
        _toggleMode.Checked = cfg.ToggleDictation;
        _language.Text = cfg.LanguageRaw;
        _removeFillers.Checked = cfg.RemoveFillers;
        _sounds.Checked = cfg.Sounds;
        _aiMode.Checked = cfg.AiMode;
        _ollamaModel.Text = cfg.OllamaModel;
        _modelPath.Text = cfg.ModelPath;
        _serverPath.Text = cfg.WhisperServerPath;
        _vocabulary.Text = cfg.VocabularyRaw.Replace("\n", Environment.NewLine);
        _replacements.Text = cfg.ReplacementsRaw.Replace("\n", Environment.NewLine);
        _launchAtLogin.Checked = IsLaunchAtLogin();
        RefreshHistory();
    }

    private void SaveSettings()
    {
        var cfg = Config.Shared;
        bool engineChanged =
            cfg.LanguageRaw != _language.Text.Trim() ||
            cfg.ModelPath != _modelPath.Text.Trim() ||
            cfg.WhisperServerPath != _serverPath.Text.Trim() ||
            cfg.VocabularyRaw != Normalize(_vocabulary.Text);

        cfg.Hotkey = (Hotkey)Math.Max(0, _hotkey.SelectedIndex);
        cfg.ToggleDictation = _toggleMode.Checked;
        cfg.LanguageRaw = _language.Text.Trim();
        cfg.RemoveFillers = _removeFillers.Checked;
        cfg.Sounds = _sounds.Checked;
        cfg.AiMode = _aiMode.Checked;
        cfg.OllamaModel = _ollamaModel.Text.Trim();
        cfg.ModelPath = _modelPath.Text.Trim();
        cfg.WhisperServerPath = _serverPath.Text.Trim();
        cfg.VocabularyRaw = Normalize(_vocabulary.Text);
        cfg.ReplacementsRaw = Normalize(_replacements.Text);
        cfg.Save();
        SetLaunchAtLogin(_launchAtLogin.Checked);

        if (engineChanged) OnEngineSettingsChanged?.Invoke();
    }

    private static string Normalize(string text) => text.Replace("\r\n", "\n").Trim();

    private static bool IsLaunchAtLogin()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(RunValue) != null;
        }
        catch { return false; }
    }

    private static void SetLaunchAtLogin(bool enable)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (enable) key.SetValue(RunValue, $"\"{Application.ExecutablePath}\"");
            else key.DeleteValue(RunValue, throwOnMissingValue: false);
        }
        catch (Exception e)
        {
            Log.Write($"settings: launch-at-login update failed — {e.Message}");
        }
    }
}
