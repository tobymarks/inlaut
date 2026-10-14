using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Inlaut.App;

// WinForms adaptation of Microsoft's Windows 11 typography, geometry and colors.
// Keep system window chrome, keyboard navigation and accessibility semantics.
internal static class WindowsTheme
{
    public static bool Dark { get; private set; }
    public static bool Animations => !HighContrast && SystemParametersInfo(0x1042, 0, out bool enabled, 0) && enabled;
    public static bool HighContrast => SystemInformation.HighContrast;
    public static Color Background => HighContrast ? SystemColors.Window : Dark ? Color.FromArgb(32, 32, 32) : Color.FromArgb(243, 243, 243);
    public static Color Surface => HighContrast ? SystemColors.Window : Dark ? Color.FromArgb(44, 44, 44) : Color.White;
    public static Color Text => HighContrast ? SystemColors.WindowText : Dark ? Color.FromArgb(245, 245, 245) : Color.FromArgb(26, 26, 26);
    public static Color Secondary => HighContrast ? SystemColors.WindowText : Dark ? Color.FromArgb(198, 198, 198) : Color.FromArgb(96, 96, 96);
    public static Color Border => HighContrast ? SystemColors.WindowText : Dark ? Color.FromArgb(70, 70, 70) : Color.FromArgb(218, 218, 218);
    public static Color Hover => HighContrast ? SystemColors.Highlight : Dark ? Color.FromArgb(62, 62, 62) : Color.FromArgb(235, 235, 235);
    public static Color Accent => HighContrast ? SystemColors.Highlight : Dark ? Color.FromArgb(96, 205, 255) : Color.FromArgb(0, 95, 184);
    public static Color OnAccent => HighContrast ? SystemColors.HighlightText : Dark ? Color.Black : Color.White;
    public static string FontFamily { get; } = PickFont("Segoe UI Variable Text", "Segoe UI");
    public static string IconFamily { get; } = PickFont("Segoe Fluent Icons", "Segoe MDL2 Assets");
    public static Font Font(float points = 10.5f, FontStyle style = FontStyle.Regular) => new(FontFamily, points, style);

    private static string PickFont(string preferred, string fallback)
    {
        try { using var family = new System.Drawing.FontFamily(preferred); return family.Name; }
        catch (ArgumentException) { return fallback; }
    }

    public static void Refresh()
    {
        try { Dark = (int?)Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) == 0; }
        catch { Dark = false; }
    }

    public static void Apply(Control control)
    {
        control.BackColor = control.Tag as string == "surface" ? Surface : control.Parent?.BackColor ?? Background;
        control.ForeColor = control.Tag as string == "secondary" ? Secondary : Text;
        if (control is LinkLabel link) { link.LinkColor = Accent; link.ActiveLinkColor = Accent; link.VisitedLinkColor = Accent; }
        if (control is Label && control.Parent != null) control.BackColor = control.Parent.BackColor;
        if (control is FluentButton button) { button.Invalidate(); return; }
        foreach (Control child in control.Controls) Apply(child);
        control.Invalidate();
    }

    public static void Chrome(IntPtr handle)
    {
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000)) return;
        int dark = Dark && !HighContrast ? 1 : 0, corners = HighContrast ? 1 : 2;
        DwmSetWindowAttribute(handle, 20, ref dark, sizeof(int));
        DwmSetWindowAttribute(handle, 33, ref corners, sizeof(int));
    }

    public static GraphicsPath Rounded(RectangleF rect, float radius)
    {
        var path = new GraphicsPath();
        float d = Math.Min(radius * 2, Math.Min(rect.Width, rect.Height));
        if (d <= 0) { path.AddRectangle(rect); return path; }
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfo(uint action, uint parameter, [MarshalAs(UnmanagedType.Bool)] out bool value, uint flags);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}

public class FluentForm : Form
{
    public FluentForm()
    {
        WindowsTheme.Refresh();
        AutoScaleDimensions = new SizeF(96, 96);
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = WindowsTheme.Font();
        BackColor = WindowsTheme.Background;
        ForeColor = WindowsTheme.Text;
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        WindowsTheme.Apply(this);
        WindowsTheme.Chrome(Handle);
    }

    protected override void WndProc(ref Message m)
    {
        base.WndProc(ref m);
        if (m.Msg is 0x001A or 0x031A)
        {
            WindowsTheme.Refresh();
            WindowsTheme.Apply(this);
            WindowsTheme.Chrome(Handle);
        }
    }
}

public class FluentButton : Button
{
    public bool Accent { get; set; }
    private bool _hover, _pressed;
    public FluentButton()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        Padding = new Padding(12, 6, 12, 6);
        MinimumSize = new Size(0, 34);
        Cursor = Cursors.Default;
        UseVisualStyleBackColor = false;
    }
    protected override void OnMouseEnter(EventArgs e) { _hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { _hover = _pressed = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { _pressed = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { _pressed = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Space) { _pressed = true; Invalidate(); } base.OnKeyDown(e); }
    protected override void OnKeyUp(KeyEventArgs e) { _pressed = false; Invalidate(); base.OnKeyUp(e); }
    protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
    protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
    protected override void OnPaint(PaintEventArgs e)
    {
        float scale = DeviceDpi / 96f;
        e.Graphics.Clear(Parent?.BackColor ?? WindowsTheme.Background);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var bounds = new RectangleF(.5f, .5f, Width - 1, Height - 1);
        using var path = WindowsTheme.Rounded(bounds, 4 * scale);
        var fill = !Enabled ? WindowsTheme.Background : Accent ? WindowsTheme.Accent : _hover || _pressed ? WindowsTheme.Hover : WindowsTheme.Surface;
        using var brush = new SolidBrush(fill);
        using var border = new Pen(WindowsTheme.Border);
        e.Graphics.FillPath(brush, path);
        if (!Accent) e.Graphics.DrawPath(border, path);
        if (_pressed) { using var pressed = new SolidBrush(Color.FromArgb(20, WindowsTheme.Text)); e.Graphics.FillPath(pressed, path); }
        var textColor = !Enabled ? SystemColors.GrayText : Accent ? WindowsTheme.OnAccent : WindowsTheme.HighContrast && (_hover || _pressed) ? SystemColors.HighlightText : WindowsTheme.Text;
        TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, textColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        if (Focused && ShowFocusCues)
            ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -(int)(4 * scale), -(int)(4 * scale)), textColor, fill);
    }
}
