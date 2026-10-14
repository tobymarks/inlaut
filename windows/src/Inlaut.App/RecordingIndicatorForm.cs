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

public class RecordingIndicatorForm : Form
{
    private IndicatorPhase _phase = IndicatorPhase.Hidden;
    private string _message = "";
    private readonly float[] _bars = new float[7] { 0.2f, 0.4f, 0.6f, 0.8f, 0.6f, 0.4f, 0.2f };
    private readonly System.Windows.Forms.Timer _animTimer;
    private Func<float>? _levelProvider;
    private int _transcribeAngle = 0;

    public RecordingIndicatorForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Size = new Size(180, 42);
        BackColor = Color.Black;
        DoubleBuffered = true;

        _animTimer = new System.Windows.Forms.Timer
        {
            Interval = 40 // ~25 FPS
        };
        _animTimer.Tick += OnAnimTimerTick;
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
        _levelProvider = levelProvider;
        _phase = IndicatorPhase.Recording;
        UpdatePosition();
        Show();
        _animTimer.Start();
        Invalidate();
    }

    public void ShowTranscribing()
    {
        _phase = IndicatorPhase.Transcribing;
        _levelProvider = null;
        UpdatePosition();
        Show();
        Invalidate();
    }

    public void ShowMessage(string message)
    {
        _message = message;
        _phase = IndicatorPhase.Message;
        _levelProvider = null;
        UpdatePosition();
        Show();
        Invalidate();
    }

    public void HideIndicator()
    {
        _animTimer.Stop();
        _phase = IndicatorPhase.Hidden;
        _levelProvider = null;
        Hide();
    }

    private void UpdatePosition()
    {
        var screen = Screen.PrimaryScreen ?? Screen.AllScreens.FirstOrDefault();
        if (screen == null) return;

        var bounds = screen.WorkingArea;
        int x = bounds.Left + (bounds.Width - Width) / 2;
        int y = bounds.Bottom - Height - 24; // 24px above taskbar
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

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

        // Draw capsule background
        var rect = new Rectangle(1, 1, Width - 3, Height - 3);
        using (var path = CreateRoundedRectanglePath(rect, Height / 2))
        {
            // Dark capsule body
            using var bgBrush = new SolidBrush(Color.FromArgb(24, 26, 32));
            g.FillPath(bgBrush, path);

            // Subtle border
            using var borderPen = new Pen(Color.FromArgb(65, 75, 90), 1.2f);
            g.DrawPath(borderPen, path);
        }

        using var textFont = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        using var textBrush = new SolidBrush(Color.FromArgb(240, 243, 248));

        if (_phase == IndicatorPhase.Recording)
        {
            // Red recording dot
            using (var dotBrush = new SolidBrush(Color.FromArgb(235, 60, 60)))
            {
                g.FillEllipse(dotBrush, 16, (Height - 8) / 2, 8, 8);
            }

            // Text "Hört zu…"
            string text = "Hört zu …";
            g.DrawString(text, textFont, textBrush, 32, (Height - 16) / 2);

            // Waveform bars
            int barsStartX = 110;
            int maxBarHeight = 18;
            int barWidth = 3;
            int barSpacing = 3;
            int centerY = Height / 2;

            using var barBrush = new SolidBrush(Color.FromArgb(90, 160, 255));
            for (int i = 0; i < _bars.Length; i++)
            {
                int h = Math.Max(4, (int)(_bars[i] * maxBarHeight));
                int bx = barsStartX + i * (barWidth + barSpacing);
                int by = centerY - h / 2;
                g.FillRectangle(barBrush, bx, by, barWidth, h);
            }
        }
        else if (_phase == IndicatorPhase.Transcribing)
        {
            // Spinning arc / loader
            using (var arcPen = new Pen(Color.FromArgb(90, 160, 255), 2.5f))
            {
                g.DrawArc(arcPen, 16, (Height - 14) / 2, 14, 14, _transcribeAngle, 260);
            }

            // Text "Transkribiert…"
            string text = "Transkribiert …";
            g.DrawString(text, textFont, textBrush, 38, (Height - 16) / 2);
        }
        else if (_phase == IndicatorPhase.Message)
        {
            g.DrawString(_message, textFont, textBrush, 16, (Height - 16) / 2);
        }
    }

    private static GraphicsPath CreateRoundedRectanglePath(Rectangle rect, int radius)
    {
        var path = new GraphicsPath();
        int d = radius * 2;

        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();

        return path;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _animTimer.Dispose();
        }
        base.Dispose(disposing);
    }
}
