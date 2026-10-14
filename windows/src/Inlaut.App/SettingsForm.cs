using System.Diagnostics;
using Inlaut.Platform.Windows;

namespace Inlaut.App;

public class SettingsForm : FluentForm
{
    private readonly AppSettings _settings;
    private readonly KeyTrigger _keyTrigger;
    private readonly Action _onSettingsChanged;

    private Label _currentKeyLabel = null!;
    private Button _captureButton = null!;
    private Label _testStatusLabel = null!;
    private bool _isCapturing = false;

    public SettingsForm(AppSettings settings, KeyTrigger keyTrigger, Action onSettingsChanged)
    {
        _settings = settings;
        _keyTrigger = keyTrigger;
        _onSettingsChanged = onSettingsChanged;

        InitializeComponents();
    }

    private void InitializeComponents()
    {
        SuspendLayout();
        Text = "inlaut — Einstellungen";
        AutoScaleDimensions = new SizeF(96, 96);
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(560, 560);
        MinimumSize = new Size(460, 460);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.Sizable;
        MaximizeBox = false;
        MinimizeBox = false;
        Font = WindowsTheme.Font();
        BackColor = WindowsTheme.Background;

        // Bottom action bar (docked to bottom of form)
        var bottomPanel = new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 56,
            BackColor = WindowsTheme.Background,
            Padding = new Padding(16, 10, 16, 10)
        };

        var closeBtn = new FluentButton
        {
            Text = "Fertig",
            Accent = true,
            Dock = DockStyle.Right,
            Width = 100,
            BackColor = WindowsTheme.Surface,
            FlatStyle = FlatStyle.Flat,
            Font = WindowsTheme.Font(),
            Cursor = Cursors.Default
        };
        closeBtn.FlatAppearance.BorderSize = 0;
        closeBtn.Click += (s, e) => Close();
        bottomPanel.Controls.Add(closeBtn);

        var openFolderBtn = new FluentButton
        {
            Text = "Modellordner",
            Dock = DockStyle.Left,
            Width = 150,
            BackColor = WindowsTheme.Surface,
            Tag = "surface",
            FlatStyle = FlatStyle.Flat,
            Font = WindowsTheme.Font(),
            Cursor = Cursors.Default
        };
        openFolderBtn.FlatAppearance.BorderColor = WindowsTheme.Border;
        openFolderBtn.Click += (s, e) =>
        {
            string dir = ModelManager.GetModelDirectory();
            Process.Start(new ProcessStartInfo("explorer.exe", dir) { UseShellExecute = true });
        };
        bottomPanel.Controls.Add(openFolderBtn);


        // Scrollable content container
        var scrollContainer = new Panel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true,
            Padding = new Padding(24)
        };

        // One-way layout: the table owns widths; children only request height.
        // No SizeChanged handlers may write widths back into their parents.
        var contentFlow = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            ColumnCount = 1,
            GrowStyle = TableLayoutPanelGrowStyle.AddRows,
            Padding = Padding.Empty,
            Margin = Padding.Empty
        };
        contentFlow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        // 1. Header Title & Description
        var titleLabel = new Label
        {
            Text = "Diktieren",
            Font = WindowsTheme.Font(20, FontStyle.Bold),
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 4)
        };
        contentFlow.Controls.Add(titleLabel);

        var descLabel = new Label
        {
            Text = "Halte die Taste gedrückt zum Diktieren, oder tippe sie zweimal kurz für Daueraufnahme.",
            ForeColor = WindowsTheme.Secondary,
            Tag = "secondary",
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 16)
        };
        contentFlow.Controls.Add(descLabel);

        // 2. Current Key Card
        var cardPanel = new Panel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            BackColor = WindowsTheme.Surface,
            Tag = "surface",
            Padding = new Padding(16),
            Margin = new Padding(0, 0, 0, 16)
        };
        cardPanel.Paint += (s, e) =>
        {
            using var pen = new Pen(WindowsTheme.Border, 1.2f);
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using var outline = WindowsTheme.Rounded(new RectangleF(0, 0, cardPanel.Width - 1, cardPanel.Height - 1), 4 * DeviceDpi / 96f);
            e.Graphics.DrawPath(pen, outline);
        };

        var cardInner = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 1,
            GrowStyle = TableLayoutPanelGrowStyle.AddRows
        };

        cardInner.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        _currentKeyLabel = new Label
        {
            Text = $"Aktuelle Taste:  {AppSettings.GetFriendlyKeyName(_settings.TriggerVkCode)}",
            Font = WindowsTheme.Font(11, FontStyle.Bold),
            ForeColor = WindowsTheme.Text,
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 12)
        };
        cardInner.Controls.Add(_currentKeyLabel);

        _captureButton = new FluentButton
        {
            Text = "Taste ändern…",
            Height = 40,
            Dock = DockStyle.Top,
            AutoSize = true,
            BackColor = WindowsTheme.Surface,
            ForeColor = WindowsTheme.Text,
            FlatStyle = FlatStyle.Flat,
            Font = WindowsTheme.Font(),
            Cursor = Cursors.Default,
            Margin = new Padding(0, 0, 0, 4)
        };
        _captureButton.FlatAppearance.BorderSize = 0;
        _captureButton.Click += (s, e) => StartKeyCapture();
        cardInner.Controls.Add(_captureButton);

        cardPanel.Controls.Add(cardInner);
        contentFlow.Controls.Add(cardPanel);

        // 3. Quick Presets
        var presetLabel = new Label
        {
            Text = "Oder eine Taste auswählen",
            Font = WindowsTheme.Font(),
            ForeColor = WindowsTheme.Secondary,
            Tag = "secondary",
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 6)
        };
        contentFlow.Controls.Add(presetLabel);

        var presetsFlow = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            Margin = new Padding(0, 0, 0, 16)
        };

        AddPresetButton(presetsFlow, "Strg links", 0xA2);
        AddPresetButton(presetsFlow, "Caps Lock", 0x14);
        AddPresetButton(presetsFlow, "Alt rechts", 0xA5);
        AddPresetButton(presetsFlow, "F8", 0x77);
        AddPresetButton(presetsFlow, "^ / °", 0xDC);

        contentFlow.Controls.Add(presetsFlow);

        // 4. Test Area
        var testPanel = new Panel
        {
            Dock = DockStyle.Top,
            Height = 65,
            BackColor = WindowsTheme.Background,
            Padding = new Padding(12),
            Margin = new Padding(0, 0, 0, 16)
        };

        _testStatusLabel = new Label
        {
            Text = "Diktieren ist pausiert, solange die Einstellungen geöffnet sind.",
            ForeColor = WindowsTheme.Text,
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleCenter,
            Font = WindowsTheme.Font()
        };
        testPanel.Controls.Add(_testStatusLabel);
        contentFlow.Controls.Add(testPanel);

        scrollContainer.Controls.Add(contentFlow);
        Controls.Add(scrollContainer);
        Controls.Add(bottomPanel);

        AcceptButton = closeBtn;
        CancelButton = closeBtn;
        KeyPreview = true;
        KeyDown += OnFormKeyDown;
        FormClosed += (_, _) =>
        {
            _isCapturing = false;
            _keyTrigger.EndCaptureMode();
        };
        ResumeLayout(true);
    }

    private void AddPresetButton(FlowLayoutPanel panel, string name, uint vkCode)
    {
        var btn = new FluentButton
        {
            Text = name,
            AutoSize = true,
            Height = 34,
            BackColor = WindowsTheme.Surface,
            Tag = "surface",
            FlatStyle = FlatStyle.Flat,
            Font = WindowsTheme.Font(),
            Margin = new Padding(0, 0, 8, 8),
            Cursor = Cursors.Default
        };
        btn.FlatAppearance.BorderColor = WindowsTheme.Border;
        btn.Click += (s, e) => ApplyKey(vkCode);
        panel.Controls.Add(btn);
    }

    private void StartKeyCapture()
    {
        _isCapturing = true;
        _captureButton.Text = "Taste drücken · Esc zum Abbrechen";
        _captureButton.BackColor = WindowsTheme.Surface;
        _keyTrigger.SetCaptureMode(OnKeyCaptured);
    }

    private void OnKeyCaptured(uint vkCode)
    {
        if (InvokeRequired)
        {
            BeginInvoke(new Action(() => OnKeyCaptured(vkCode)));
            return;
        }

        if (!_isCapturing) return;

        if (vkCode == (uint)Keys.Escape)
        {
            _isCapturing = false;
            _captureButton.Text = "Taste ändern…";
            _captureButton.BackColor = WindowsTheme.Surface;
            _keyTrigger.EndCaptureMode();
            return;
        }

        ApplyKey(vkCode);
    }

    private void ApplyKey(uint vkCode)
    {
        _isCapturing = false;
        _keyTrigger.EndCaptureMode();

        _settings.TriggerVkCode = vkCode;
        _settings.TriggerKeyName = AppSettings.GetFriendlyKeyName(vkCode);
        _settings.Save();

        _currentKeyLabel.Text = $"Aktuelle Taste:  {AppSettings.GetFriendlyKeyName(_settings.TriggerVkCode)}";
        _captureButton.Text = "Taste ändern…";
        _captureButton.BackColor = WindowsTheme.Surface;

        _keyTrigger.UpdateTriggerKey(vkCode);
        _onSettingsChanged();

        _testStatusLabel.Text = $"Gespeichert: {AppSettings.GetFriendlyKeyName(vkCode)}";
        _testStatusLabel.ForeColor = WindowsTheme.Text;
    }

    private void OnFormKeyDown(object? sender, KeyEventArgs e)
    {
        if (_isCapturing)
        {
            OnKeyCaptured((uint)e.KeyCode);
            e.Handled = true;
        }
    }
}
