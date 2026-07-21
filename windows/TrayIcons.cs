using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace LocalWillow;

/// Runtime-generated waveform tray icons matching the macOS app's mark.
/// Icons are created once per state and cached for the app's lifetime.
public static class TrayIcons
{
    public static readonly Icon Idle = Make(new[] { 0.30f, 0.55f, 0.85f, 0.55f, 0.30f }, Color.White);
    public static readonly Icon Recording = Make(new[] { 0.45f, 0.75f, 1.0f, 0.75f, 0.45f }, Color.FromArgb(255, 69, 58));
    public static readonly Icon Processing = Make(new[] { 0.22f, 0.38f, 0.55f, 0.38f, 0.22f }, Color.FromArgb(160, 160, 165));

    private static Icon Make(float[] heights, Color color)
    {
        const int size = 32;
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            float barW = 4.4f, gap = 2.4f;
            float total = heights.Length * barW + (heights.Length - 1) * gap;
            float x = (size - total) / 2;
            using var brush = new SolidBrush(color);
            foreach (var h in heights)
            {
                float barH = Math.Max(barW, (size - 6) * h);
                var r = new RectangleF(x, size / 2f - barH / 2, barW, barH);
                using var path = new GraphicsPath();
                float d = barW;
                path.AddArc(r.X, r.Y, d, d, 180, 90);
                path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
                path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
                path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
                path.CloseFigure();
                g.FillPath(brush, path);
                x += barW + gap;
            }
        }
        // The HICON is never destroyed — three cached icons for the app's lifetime.
        return Icon.FromHandle(bmp.GetHicon());
    }
}
