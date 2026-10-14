using System.Drawing.Drawing2D;
using System.Drawing.Text;

namespace Inlaut.App;

public enum IndicatorPhase
{
    Hidden,
    Recording,
    Transcribing,
    Message
}

public class RecordingIndicatorForm : FluentForm
{
    private IndicatorPhase _phase = IndicatorPhase.Hidden;
    private string _message = "";
    private readonly float[] _bars = new float[7] { 0.2f, 0.4f, 0.6f, 0.8f, 0.6f, 0.4f, 0.2f };
    private readonly System.Windows.Forms.Timer _animTimer;
    private readonly System.Windows.Forms.Timer _messageTimer;
    internal IndicatorPhase Phase => _phase;
    private Func<float>? _levelProvider;
    private int _transcribeAngle = 0;
    private IndicatorLayout _layout;

    public RecordingIndicatorForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None;
        ClientSize = new Size(224, 48);
        BackColor = WindowsTheme.Surface;
        Tag = "surface";
        AccessibleName = "inlaut Aufnahmestatus";
        DoubleBuffered = true;

        _animTimer = new System.Windows.Forms.Timer
        {
            Interval = 40 // ~25 FPS
        };
        _animTimer.Tick += OnAnimTimerTick;
        _messageTimer = new System.Windows.Forms.Timer();
        _messageTimer.Tick += (_, _) => HideIndicator();
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            cp.ExStyle |= 0x00000008; // WS_EX_TOPMOST
            return cp;
        }
    }

    public void ShowRecording(Func<float> levelProvider)
    {
        _messageTimer.Stop();
        _levelProvider = levelProvider;
        _phase = IndicatorPhase.Recording;
        AccessibleDescription = "Aufnahme läuft";
        UpdatePosition();
        Show();
        if (WindowsTheme.Animations) _animTimer.Start();
        Invalidate();
    }

    public void ShowTranscribing()
    {
        _messageTimer.Stop();
        _phase = IndicatorPhase.Transcribing;
        AccessibleDescription = "Sprache wird in Text umgewandelt";
        if (WindowsTheme.Animations) _animTimer.Start();
        _levelProvider = null;
        UpdatePosition();
        Show();
        Invalidate();
    }

    public void ShowMessage(string message, int durationMs = 2500)
    {
        _messageTimer.Stop();
        _animTimer.Stop();
        _message = message;
        AccessibleDescription = message;
        _phase = IndicatorPhase.Message;
        _levelProvider = null;
        UpdatePosition();
        Show();
        Invalidate();
        _messageTimer.Interval = Math.Max(1, durationMs);
        _messageTimer.Start();
    }

    public void HideIndicator()
    {
        _animTimer.Stop();
        _messageTimer.Stop();
        _phase = IndicatorPhase.Hidden;
        _levelProvider = null;
        Hide();
    }

    private void UpdatePosition()
    {
        UpdateMetrics();
        var screen = Screen.FromPoint(Cursor.Position);
        if (screen == null) return;

        var bounds = screen.WorkingArea;
        int x = bounds.Left + (bounds.Width - Width) / 2;
        int y = bounds.Bottom - Height - (int)(24 * DeviceDpi / 96f); // 24px above taskbar
        Location = new Point(x, y);
    }

    private void OnAnimTimerTick(object? sender, EventArgs e)
    {
        if (_phase == IndicatorPhase.Recording && _levelProvider != null)
        {
            float target = Math.Min(1.0f, (float)Math.Sqrt(_levelProvider()) * 1.8f);

            // Shift and smooth bars
            for (int i = 0; i < _bars.Length - 1; i++)
            {
                _bars[i] = _bars[i + 1];
            }
            float prev = _bars[^1];
            float smoothing = target > prev ? 0.6f : 0.25f;
            _bars[^1] = prev + (target - prev) * smoothing;

            Invalidate();
        }
        else if (_phase == IndicatorPhase.Transcribing)
        {
            _transcribeAngle = (_transcribeAngle + 20) % 360;
            Invalidate();
        }
    }

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        if (ClientSize.Width <= 0 || ClientSize.Height <= 0) return;
        using var shape = WindowsTheme.Rounded(ClientRectangle, 8 * DeviceDpi / 96f);
        var previous = Region;
        Region = new Region(shape);
        previous?.Dispose();
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        UpdateMetrics();
    }

    protected override void OnDpiChanged(DpiChangedEventArgs e)
    {
        base.OnDpiChanged(e);
        UpdatePosition();
    }

    private void UpdateMetrics()
    {
        if (!IsHandleCreated) return;
        using var graphics = CreateGraphics();
        string text = _phase == IndicatorPhase.Message ? _message : "Wird erkannt…";
        var measured = TextRenderer.MeasureText(graphics, text, Font, Size.Empty, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
        _layout = IndicatorLayout.Create(DeviceDpi, measured);
        ClientSize = _layout.Size;
        LocalDiagnostics.Write("indicator-layout", new { dpi = DeviceDpi, width = Width, height = Height, textRight = _layout.Text.Right, barsLeft = _layout.Bars.Left });
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        float scale = DeviceDpi / 96f;
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = WindowsTheme.Rounded(new RectangleF(.5f, .5f, ClientSize.Width - 1, ClientSize.Height - 1), 8 * scale);
        using var fill = new SolidBrush(WindowsTheme.Surface);
        using var border = new Pen(WindowsTheme.Border);
        g.FillPath(fill, path);
        g.DrawPath(border, path);
        var icon = _layout.Icon;
        string text = _phase == IndicatorPhase.Recording ? "Hört zu…" : _phase == IndicatorPhase.Transcribing ? "Wird erkannt…" : _message;
        TextRenderer.DrawText(g, text, Font, _layout.Text, WindowsTheme.Text,
            TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        if (_phase == IndicatorPhase.Recording)
        {
            using var dot = new SolidBrush(WindowsTheme.HighContrast ? WindowsTheme.Text : Color.FromArgb(196, 43, 28));
            float diameter = 8 * scale;
            g.FillEllipse(dot, icon.X + (icon.Width - diameter) / 2, icon.Y + (icon.Height - diameter) / 2, diameter, diameter);
            using var accent = new SolidBrush(WindowsTheme.Accent);
            for (int i = 0; i < _bars.Length; i++)
            {
                float height = Math.Max(4 * scale, _bars[i] * _layout.Bars.Height);
                g.FillRectangle(accent, _layout.Bars.X + i * 6 * scale, _layout.Bars.Y + (_layout.Bars.Height - height) / 2, 3 * scale, height);
            }
        }
        else if (_phase == IndicatorPhase.Transcribing)
        {
            using var pen = new Pen(WindowsTheme.Accent, 2 * scale);
            g.DrawArc(pen, icon, _transcribeAngle, 260);
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _animTimer.Dispose();
            _messageTimer.Dispose();
        }
        base.Dispose(disposing);
    }
}
