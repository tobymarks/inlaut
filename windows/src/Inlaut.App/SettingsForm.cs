using System.Diagnostics;
using Inlaut.Platform.Windows;

namespace Inlaut.App;

public class SettingsForm : Form
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
        Text = "inlaut — Einstellungen";
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(560, 560);
        MinimumSize = new Size(460, 460);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.Sizable;
        MaximizeBox = false;
        MinimizeBox = false;
        Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);
        BackColor = Color.FromArgb(248, 249, 251);

        // Bottom action bar (docked to bottom of form)
        var bottomPanel = new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 56,
            BackColor = Color.FromArgb(240, 242, 246),
            Padding = new Padding(16, 10, 16, 10)
        };

        var closeBtn = new Button
        {
            Text = "Fertig",
            Dock = DockStyle.Right,
            Width = 100,
            BackColor = Color.FromArgb(220, 226, 235),
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
            Cursor = Cursors.Hand
        };
        closeBtn.FlatAppearance.BorderSize = 0;
        closeBtn.Click += (s, e) => Close();
        bottomPanel.Controls.Add(closeBtn);

        var openFolderBtn = new Button
        {
            Text = "📁 Modellordner",
            Dock = DockStyle.Left,
            Width = 130,
            BackColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9f, FontStyle.Regular),
            Cursor = Cursors.Hand
        };
        openFolderBtn.FlatAppearance.BorderColor = Color.FromArgb(210, 215, 225);
        openFolderBtn.Click += (s, e) =>
        {
            string dir = ModelManager.GetModelDirectory();
            Process.Start(new ProcessStartInfo("explorer.exe", dir) { UseShellExecute = true });
        };
        bottomPanel.Controls.Add(openFolderBtn);

        Controls.Add(bottomPanel);

        // Scrollable content container
        var scrollContainer = new Panel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true,
            Padding = new Padding(20)
        };

        var contentFlow = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Width = scrollContainer.ClientSize.Width - 40
        };

        scrollContainer.Resize += (s, e) =>
        {
            contentFlow.Width = scrollContainer.ClientSize.Width - 40;
        };

        // 1. Header Title & Description
        var titleLabel = new Label
        {
            Text = "Aufnahme-Taste konfigurieren",
            Font = new Font("Segoe UI", 13f, FontStyle.Bold),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 4)
        };
        contentFlow.Controls.Add(titleLabel);

        var descLabel = new Label
        {
            Text = "Halte die Taste gedrückt zum Diktieren, oder tippe sie zweimal kurz für Daueraufnahme.",
            ForeColor = Color.FromArgb(90, 100, 115),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 16)
        };
        contentFlow.Controls.Add(descLabel);

        // 2. Current Key Card
        var cardPanel = new Panel
        {
            Width = contentFlow.Width,
            AutoSize = true,
            BackColor = Color.White,
            Padding = new Padding(16),
            Margin = new Padding(0, 0, 0, 16)
        };
        cardPanel.Paint += (s, e) =>
        {
            using var pen = new Pen(Color.FromArgb(215, 220, 230), 1.2f);
            e.Graphics.DrawRectangle(pen, 0, 0, cardPanel.Width - 1, cardPanel.Height - 1);
        };
        contentFlow.SizeChanged += (s, e) => cardPanel.Width = contentFlow.Width;

        var cardInner = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Width = cardPanel.ClientSize.Width
        };
        cardPanel.SizeChanged += (s, e) => cardInner.Width = cardPanel.ClientSize.Width - 32;

        _currentKeyLabel = new Label
        {
            Text = $"Aktuelle Taste:  {_settings.TriggerKeyName}",
            Font = new Font("Segoe UI", 11f, FontStyle.Bold),
            ForeColor = Color.FromArgb(30, 40, 55),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 12)
        };
        cardInner.Controls.Add(_currentKeyLabel);

        _captureButton = new Button
        {
            Text = "⌨️ Neue Taste durch Drücken festlegen...",
            Height = 40,
            Width = 360,
            BackColor = Color.FromArgb(30, 105, 225),
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 10f, FontStyle.Bold),
            Cursor = Cursors.Hand,
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
            Text = "Schnellauswahl für typische Tastaturen (z. B. MacBook ohne F8):",
            Font = new Font("Segoe UI", 9f, FontStyle.Regular),
            ForeColor = Color.FromArgb(100, 110, 125),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 6)
        };
        contentFlow.Controls.Add(presetLabel);

        var presetsFlow = new FlowLayoutPanel
        {
            Width = contentFlow.Width,
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            Margin = new Padding(0, 0, 0, 16)
        };
        contentFlow.SizeChanged += (s, e) => presetsFlow.Width = contentFlow.Width;

        AddPresetButton(presetsFlow, "Linke Strg (neben Fn)", 0xA2);
        AddPresetButton(presetsFlow, "Caps Lock", 0x14);
        AddPresetButton(presetsFlow, "Rechte Alt / Option", 0xA5);
        AddPresetButton(presetsFlow, "F8", 0x77);
        AddPresetButton(presetsFlow, "^ (Dach)", 0xDC);

        contentFlow.Controls.Add(presetsFlow);

        // 4. Test Area
        var testPanel = new Panel
        {
            Width = contentFlow.Width,
            Height = 65,
            BackColor = Color.FromArgb(238, 242, 248),
            Padding = new Padding(12),
            Margin = new Padding(0, 0, 0, 16)
        };
        contentFlow.SizeChanged += (s, e) => testPanel.Width = contentFlow.Width;

        _testStatusLabel = new Label
        {
            Text = "🧪 Taste hier testen: Drücke oder doppeltippe deine gewählte Taste...",
            ForeColor = Color.FromArgb(70, 80, 95),
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleCenter,
            Font = new Font("Segoe UI", 9.5f, FontStyle.Regular)
        };
        testPanel.Controls.Add(_testStatusLabel);
        contentFlow.Controls.Add(testPanel);

        scrollContainer.Controls.Add(contentFlow);
        Controls.Add(scrollContainer);

        KeyPreview = true;
        KeyDown += OnFormKeyDown;
    }

    private void AddPresetButton(FlowLayoutPanel panel, string name, uint vkCode)
    {
        var btn = new Button
        {
            Text = name,
            AutoSize = true,
            Height = 34,
            BackColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9f, FontStyle.Regular),
            Margin = new Padding(0, 0, 8, 8),
            Cursor = Cursors.Hand
        };
        btn.FlatAppearance.BorderColor = Color.FromArgb(200, 205, 215);
        btn.Click += (s, e) => ApplyKey(vkCode);
        panel.Controls.Add(btn);
    }

    private void StartKeyCapture()
    {
        _isCapturing = true;
        _captureButton.Text = "⏳ Drücke jetzt eine Taste (oder Escape)...";
        _captureButton.BackColor = Color.FromArgb(220, 60, 60);
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
            _captureButton.Text = "⌨️ Neue Taste durch Drücken festlegen...";
            _captureButton.BackColor = Color.FromArgb(30, 105, 225);
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

        _currentKeyLabel.Text = $"Aktuelle Taste:  {_settings.TriggerKeyName}";
        _captureButton.Text = "⌨️ Neue Taste durch Drücken festlegen...";
        _captureButton.BackColor = Color.FromArgb(30, 105, 225);

        _keyTrigger.UpdateTriggerKey(vkCode);
        _onSettingsChanged();

        _testStatusLabel.Text = $"✅ Taste geändert zu: {_settings.TriggerKeyName}!";
        _testStatusLabel.ForeColor = Color.FromArgb(30, 140, 50);
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
