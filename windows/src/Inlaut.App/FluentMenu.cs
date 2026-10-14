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
    }

    protected override void OnOpening(System.ComponentModel.CancelEventArgs e)
    {
        // Consumers update status, shortcut and recording glyph in Opening.
        // Measure only after those updates, including on subsequent openings.
        base.OnOpening(e);
        if (e.Cancel) return;
        WindowsTheme.Refresh();
        Prepare(this, Font);
        LocalDiagnostics.Write("menu-layout", new { dpi = DeviceDpi, fontPoints = Font.SizeInPoints });
    }

    private static void Prepare(ToolStripDropDown menu, Font font)
    {
        menu.BackColor = WindowsTheme.Surface;
        menu.ForeColor = WindowsTheme.Text;
        menu.Font = font;
        menu.Renderer = new FluentMenuRenderer();
        WindowsTheme.Chrome(menu.Handle);
        float scale = menu.DeviceDpi / 96f;
        menu.Padding = new Padding((int)(8 * scale), (int)(8 * scale), (int)(8 * scale), (int)(8 * scale));
        int width = (int)(300 * scale);
        foreach (ToolStripItem item in menu.Items)
        {
            int textWidth = TextRenderer.MeasureText(item.Text, font).Width;
            int shortcutWidth = item is ToolStripMenuItem entry && !string.IsNullOrEmpty(entry.ShortcutKeyDisplayString)
                ? TextRenderer.MeasureText(entry.ShortcutKeyDisplayString, font).Width + (int)(24 * scale) : 0;
            width = Math.Max(width, textWidth + shortcutWidth + (int)(96 * scale));
        }
        int totalHeight = menu.Padding.Vertical;
        foreach (ToolStripItem item in menu.Items)
        {
            item.ForeColor = WindowsTheme.Text;
            item.AutoSize = false;
            item.Padding = Padding.Empty;
            item.Margin = Padding.Empty;
            int height = item is ToolStripSeparator ? (int)(12 * scale)
                : Math.Max((int)(40 * scale), TextRenderer.MeasureText(item.Text, font).Height + (int)(16 * scale));
            item.Size = new Size(width - menu.Padding.Horizontal, height);
            totalHeight += height;
            if (item is ToolStripSeparator)
            {
                continue;
            }
            if (item.Tag is string glyph)
            {
                // An actual Image reserves space in ToolStrip's native layout.
                // Never draw glyphs inside the text rendering callback.
                var old = item.Image;
                item.Image = Glyph(glyph, Math.Max(20, (int)Math.Round(20 * scale)));
                item.ImageScaling = ToolStripItemImageScaling.None;
                old?.Dispose();
            }
            if (item is ToolStripMenuItem { HasDropDownItems: true } parent) Prepare(parent.DropDown, font);
        }
        menu.AutoSize = false;
        menu.Size = new Size(width, totalHeight);
    }

    internal static Bitmap Glyph(string glyph, int pixels)
    {
        var bitmap = new Bitmap(pixels, pixels);
        bitmap.SetResolution(96, 96);
        using var graphics = Graphics.FromImage(bitmap);
        using var family = new FontFamily(WindowsTheme.IconFamily);
        using var ink = new SolidBrush(WindowsTheme.Text);
        // Font em size is not the visible glyph bounds. Fit the actual outline
        // with a transparent safety inset so ascenders/descenders never clip.
        using var outline = new GraphicsPath();
        outline.AddString(glyph, family, (int)FontStyle.Regular, pixels, PointF.Empty, StringFormat.GenericTypographic);
        var bounds = outline.GetBounds();
        if (bounds.Width <= 0 || bounds.Height <= 0) return bitmap;
        float inset = Math.Max(2, pixels * .1f);
        float factor = Math.Min((pixels - 2 * inset) / bounds.Width, (pixels - 2 * inset) / bounds.Height);
        using var transform = new Matrix(factor, 0, 0, factor,
            (pixels - bounds.Width * factor) / 2 - bounds.Left * factor,
            (pixels - bounds.Height * factor) / 2 - bounds.Top * factor);
        outline.Transform(transform);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.FillPath(ink, outline);
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
        float scale = (e.ToolStrip?.DeviceDpi ?? 96) / 96f;
        int left = (int)(44 * scale), right = (int)(20 * scale);
        e.TextRectangle = new Rectangle(left, 0, Math.Max(1, e.Item.Width - left - right), e.Item.Height);
        e.TextFormat = TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
            (e.Item is ToolStripMenuItem item && e.Text == item.ShortcutKeyDisplayString
                ? TextFormatFlags.Right : TextFormatFlags.Left);
        e.TextColor = !e.Item.Enabled ? WindowsTheme.Secondary : WindowsTheme.HighContrast && e.Item.Selected ? SystemColors.HighlightText : WindowsTheme.Text;
        base.OnRenderItemText(e);
    }
    protected override void OnRenderItemImage(ToolStripItemImageRenderEventArgs e)
    {
        float scale = (e.ToolStrip?.DeviceDpi ?? 96) / 96f;
        if (e.Image != null)
        {
            var bounds = new Rectangle((int)(12 * scale), (e.Item.Height - e.Image.Height) / 2, e.Image.Width, e.Image.Height);
            base.OnRenderItemImage(new ToolStripItemImageRenderEventArgs(e.Graphics, e.Item, e.Image, bounds));
        }
    }
    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        using var pen = new Pen(WindowsTheme.Border);
        int inset = (int)(12 * ((e.ToolStrip?.DeviceDpi ?? 96) / 96f));
        e.Graphics.DrawLine(pen, inset, e.Item.Height / 2, e.Item.Width - inset, e.Item.Height / 2);
    }
    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
    {
        float scale = (e.Item?.Owner?.DeviceDpi ?? 96) / 96f;
        e.ArrowRectangle = new Rectangle((e.Item?.Width ?? 0) - (int)(18 * scale), 0, (int)(10 * scale), e.Item?.Height ?? 0);
        e.ArrowColor = WindowsTheme.HighContrast && e.Item?.Selected == true ? SystemColors.HighlightText : WindowsTheme.Text;
        base.OnRenderArrow(e);
    }
    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
    {
        float scale = (e.ToolStrip?.DeviceDpi ?? 96) / 96f;
        float x = 12 * scale, y = e.Item.Height / 2f;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var pen = new Pen(WindowsTheme.HighContrast && e.Item.Selected ? SystemColors.HighlightText : WindowsTheme.Accent, 2 * scale);
        e.Graphics.DrawLines(pen, new[] { new PointF(x + 2 * scale, y), new PointF(x + 7 * scale, y + 5 * scale), new PointF(x + 17 * scale, y - 6 * scale) });
    }
}
