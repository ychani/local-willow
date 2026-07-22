using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

namespace LocalWillow;

/// Borderless, click-through, always-on-top pill centered near the bottom of the
/// screen — the visual anchor while dictating, like Willow's.
public sealed class OverlayForm : Form
{
    public enum Phase { Recording, Processing, Error }

    private Phase _phase = Phase.Recording;
    private string _status = "Transcribing";
    private string _errorText = "";
    private readonly float[] _bars = Enumerable.Repeat(0.05f, 24).ToArray();
    private readonly System.Windows.Forms.Timer _repaint;
    private readonly System.Windows.Forms.Timer _errorHide;
    private int _tick;

    public OverlayForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.Magenta;
        TransparencyKey = Color.Magenta;
        Size = new Size(340, 56);
        DoubleBuffered = true;

        _repaint = new System.Windows.Forms.Timer { Interval = 50 };
        _repaint.Tick += (_, _) => { _tick++; Invalidate(); };
        _errorHide = new System.Windows.Forms.Timer { Interval = 6000 };
        _errorHide.Tick += (_, _) => HideOverlay();
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            // Click-through, no focus steal, hidden from Alt-Tab.
            cp.ExStyle |= 0x20 /*WS_EX_TRANSPARENT*/ | 0x80 /*WS_EX_TOOLWINDOW*/
                        | 0x08000000 /*WS_EX_NOACTIVATE*/;
            return cp;
        }
    }

    public void ShowPhase(Phase phase)
    {
        _phase = phase;
        _errorHide.Stop();
        if (phase == Phase.Processing) _status = "Transcribing";
        var wa = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1280, 800);
        Location = new Point(wa.Left + (wa.Width - Width) / 2, wa.Bottom - Height - 60);
        if (!Visible) Show();
        _repaint.Start();
        Invalidate();
    }

    /// Replaces the "Transcribing" caption while processing (e.g. "Loading model…").
    public void SetStatus(string status)
    {
        _status = status;
        Invalidate();
    }

    /// Shows a red error pill for a few seconds, then hides itself. This makes
    /// failures visible even when Windows notifications are suppressed.
    public void ShowError(string message)
    {
        _errorText = message;
        ShowPhase(Phase.Error);
        _errorHide.Start();
    }

    public void HideOverlay()
    {
        _errorHide.Stop();
        _repaint.Stop();
        Hide();
        for (int i = 0; i < _bars.Length; i++) _bars[i] = 0.05f;
    }

    /// Ring-buffer push of the latest mic level (0..1). Call on the UI thread.
    public void PushLevel(float level)
    {
        Array.Copy(_bars, 1, _bars, 0, _bars.Length - 1);
        _bars[^1] = Math.Max(0.05f, level);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        // Pill background.
        var pill = new Rectangle(10, 8, Width - 20, Height - 16);
        using (var path = RoundedRect(pill, pill.Height / 2))
        using (var bg = new SolidBrush(Color.FromArgb(230, 20, 20, 24)))
            g.FillPath(bg, path);

        if (_phase == Phase.Recording)
        {
            // Red mic dot + waveform bars.
            using (var red = new SolidBrush(Color.FromArgb(255, 90, 84)))
                g.FillEllipse(red, pill.Left + 16, pill.Top + pill.Height / 2 - 5, 10, 10);

            float barW = 3.0f, gap = 2.5f;
            float total = _bars.Length * barW + (_bars.Length - 1) * gap;
            float x = pill.Left + (pill.Width - total) / 2 + 12;
            float midY = pill.Top + pill.Height / 2f;
            using var white = new SolidBrush(Color.FromArgb(230, 255, 255, 255));
            foreach (var v in _bars)
            {
                float h = 4 + v * 22;
                var r = new RectangleF(x, midY - h / 2, barW, h);
                using (var p = RoundedRectF(r, barW / 2)) g.FillPath(white, p);
                x += barW + gap;
            }
        }
        else if (_phase == Phase.Processing)
        {
            string dots = new string('.', 1 + _tick / 6 % 3);
            using var font = new Font("Segoe UI", 10.5f, FontStyle.Regular);
            using var white = new SolidBrush(Color.FromArgb(220, 255, 255, 255));
            var text = _status + dots;
            var sz = g.MeasureString(text, font);
            g.DrawString(text, font, white,
                pill.Left + (pill.Width - sz.Width) / 2,
                pill.Top + (pill.Height - sz.Height) / 2);
        }
        else
        {
            using var font = new Font("Segoe UI", 9.5f, FontStyle.Regular);
            using var red = new SolidBrush(Color.FromArgb(255, 120, 110));
            var text = _errorText.Length > 52 ? _errorText[..52] + "…" : _errorText;
            var sz = g.MeasureString(text, font);
            g.DrawString(text, font, red,
                pill.Left + Math.Max(8, (pill.Width - sz.Width) / 2),
                pill.Top + (pill.Height - sz.Height) / 2);
        }
    }

    private static GraphicsPath RoundedRect(Rectangle r, int radius) =>
        RoundedRectF(new RectangleF(r.X, r.Y, r.Width, r.Height), radius);

    private static GraphicsPath RoundedRectF(RectangleF r, float radius)
    {
        var path = new GraphicsPath();
        float d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
