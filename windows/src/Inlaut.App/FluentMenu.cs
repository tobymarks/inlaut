using System.Drawing.Drawing2D;

namespace Inlaut.App;

internal sealed class FluentMenu : ContextMenuStrip
{
    public FluentMenu()
    {
        ShowImageMargin = true;
        ShowCheckMargin = false;
        Font = WindowsTheme.Font();
        Renderer = new FluentMenuRenderer();
        Opening += (_, _) =>
        {
            WindowsTheme.Refresh();
            Prepare(this);
            LocalDiagnostics.Write("menu-layout", new { dpi = DeviceDpi, fontPoints = Font.SizeInPoints });
        };
    }

    private static void Prepare(ToolStripDropDown menu)
    {
        menu.BackColor = WindowsTheme.Surface;
        menu.ForeColor = WindowsTheme.Text;
        menu.Renderer = new FluentMenuRenderer();
        WindowsTheme.Chrome(menu.Handle);
        float scale = menu.DeviceDpi / 96f;
        menu.Padding = new Padding((int)(4 * scale), (int)(6 * scale), (int)(4 * scale), (int)(6 * scale));
        foreach (ToolStripItem item in menu.Items)
        {
            item.ForeColor = WindowsTheme.Text;
            if (item is ToolStripSeparator) continue;
            item.Padding = new Padding((int)(4 * scale), (int)(4 * scale), (int)(12 * scale), (int)(4 * scale));
            if (item.Tag is string glyph)
            {
                // An actual Image reserves space in ToolStrip's native layout.
                // Never draw glyphs inside the text rendering callback.
                var old = item.Image;
                item.Image = Glyph(glyph, Math.Max(16, (int)Math.Round(16 * scale)));
                item.ImageScaling = ToolStripItemImageScaling.None;
                old?.Dispose();
            }
            if (item is ToolStripMenuItem { HasDropDownItems: true } parent) Prepare(parent.DropDown);
        }
    }

    private static Bitmap Glyph(string glyph, int pixels)
    {
        var bitmap = new Bitmap(pixels, pixels);
        bitmap.SetResolution(96, 96);
        using var graphics = Graphics.FromImage(bitmap);
        using var font = new Font(WindowsTheme.IconFamily, pixels, FontStyle.Regular, GraphicsUnit.Pixel);
        using var ink = new SolidBrush(WindowsTheme.Text);
        using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        graphics.DrawString(glyph, font, ink, new RectangleF(0, 0, pixels, pixels), format);
        return bitmap;
    }

    public static ToolStripMenuItem Item(string text, string glyph, EventHandler action) =>
        new(text, null, action) { Tag = glyph };
}

internal sealed class FluentMenuRenderer : ToolStripProfessionalRenderer
{
    public FluentMenuRenderer() => RoundedEdges = false;
    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) => e.Graphics.Clear(WindowsTheme.Surface);
    protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) { }
    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
    {
        using var pen = new Pen(WindowsTheme.Border);
        e.Graphics.DrawRectangle(pen, 0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
    }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        if (!e.Item.Selected || !e.Item.Enabled) return;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var shape = WindowsTheme.Rounded(new RectangleF(2, 1, e.Item.Width - 4, e.Item.Height - 2), 4 * ((e.ToolStrip?.DeviceDpi ?? 96) / 96f));
        using var brush = new SolidBrush(WindowsTheme.Hover);
        e.Graphics.FillPath(brush, shape);
    }
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = !e.Item.Enabled ? WindowsTheme.Secondary : WindowsTheme.HighContrast && e.Item.Selected ? SystemColors.HighlightText : WindowsTheme.Text;
        base.OnRenderItemText(e);
    }
    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        using var pen = new Pen(WindowsTheme.Border);
        e.Graphics.DrawLine(pen, 8, e.Item.Height / 2, e.Item.Width - 8, e.Item.Height / 2);
    }
    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
    {
        e.ArrowColor = WindowsTheme.HighContrast && e.Item?.Selected == true ? SystemColors.HighlightText : WindowsTheme.Text;
        base.OnRenderArrow(e);
    }
}
