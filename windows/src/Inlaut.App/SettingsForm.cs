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
        Size = new Size(520, 480);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);
        BackColor = Color.FromArgb(248, 249, 251);

        var mainPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(24),
            ColumnCount = 1,
            RowCount = 6
        };

        // 1. Header
        var titleLabel = new Label
        {
            Text = "Aufnahme-Taste konfigurieren",
            Font = new Font("Segoe UI", 13f, FontStyle.Bold),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 8)
        };
        mainPanel.Controls.Add(titleLabel);

        var descLabel = new Label
        {
            Text = "Halte die Taste gedrückt zum Diktieren, oder tippe sie zweimal für Freihand-Diktat.",
            ForeColor = Color.FromArgb(90, 100, 115),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 16)
        };
        mainPanel.Controls.Add(descLabel);

        // 2. Current Key Card
        var cardPanel = new Panel
        {
            Size = new Size(456, 120),
            BackColor = Color.White,
            Padding = new Padding(16),
            Margin = new Padding(0, 0, 0, 16)
        };
        cardPanel.Paint += (s, e) =>
        {
            using var pen = new Pen(Color.FromArgb(220, 225, 235), 1.2f);
            e.Graphics.DrawRectangle(pen, 0, 0, cardPanel.Width - 1, cardPanel.Height - 1);
        };

        _currentKeyLabel = new Label
        {
            Text = $"Aktuelle Taste:  {_settings.TriggerKeyName}",
            Font = new Font("Segoe UI", 11f, FontStyle.Bold),
            ForeColor = Color.FromArgb(30, 40, 55),
            Location = new Point(16, 16),
            AutoSize = true
        };
        cardPanel.Controls.Add(_currentKeyLabel);

        _captureButton = new Button
        {
            Text = "⌨️ Neue Taste durch Drücken festlegen...",
            Location = new Point(16, 56),
            Size = new Size(424, 38),
            BackColor = Color.FromArgb(40, 110, 230),
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 10f, FontStyle.Bold),
            Cursor = Cursors.Hand
        };
        _captureButton.FlatAppearance.BorderSize = 0;
        _captureButton.Click += (s, e) => StartKeyCapture();
        cardPanel.Controls.Add(_captureButton);

        mainPanel.Controls.Add(cardPanel);

        // 3. Quick Presets
        var presetLabel = new Label
        {
            Text = "Schnellauswahl für typische Tastaturen (z. B. MacBook ohne F8):",
            Font = new Font("Segoe UI", 9f, FontStyle.Regular),
            ForeColor = Color.FromArgb(100, 110, 125),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 6)
        };
        mainPanel.Controls.Add(presetLabel);

        var presetsFlow = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            Margin = new Padding(0, 0, 0, 16)
        };

        AddPresetButton(presetsFlow, "Linke Strg", 0xA2);
        AddPresetButton(presetsFlow, "Caps Lock", 0x14);
        AddPresetButton(presetsFlow, "Rechte Alt / Option", 0xA5);
        AddPresetButton(presetsFlow, "F8", 0x77);
        AddPresetButton(presetsFlow, "^ (Dach)", 0xDC);

        mainPanel.Controls.Add(presetsFlow);

        // 4. Test Area
        var testPanel = new Panel
        {
            Size = new Size(456, 60),
            BackColor = Color.FromArgb(238, 242, 248),
            Padding = new Padding(12),
            Margin = new Padding(0, 0, 0, 16)
        };

        _testStatusLabel = new Label
        {
            Text = "🧪 Taste hier testen: Drücke oder doppeltippe deine gewählte Taste...",
            ForeColor = Color.FromArgb(70, 80, 95),
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleCenter,
            Font = new Font("Segoe UI", 9.5f, FontStyle.Regular)
        };
        testPanel.Controls.Add(_testStatusLabel);
        mainPanel.Controls.Add(testPanel);

        // 5. Close Button
        var bottomFlow = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            Dock = DockStyle.Bottom,
            AutoSize = true
        };

        var closeBtn = new Button
        {
            Text = "Fertig",
            Size = new Size(110, 36),
            BackColor = Color.FromArgb(230, 235, 242),
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
            Cursor = Cursors.Hand
        };
        closeBtn.FlatAppearance.BorderSize = 0;
        closeBtn.Click += (s, e) => Close();
        bottomFlow.Controls.Add(closeBtn);

        var openFolderBtn = new Button
        {
            Text = "📁 Modellordner",
            Size = new Size(130, 36),
            BackColor = Color.Transparent,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9.5f, FontStyle.Regular),
            Cursor = Cursors.Hand
        };
        openFolderBtn.Click += (s, e) =>
        {
            string dir = ModelManager.GetModelDirectory();
            Process.Start(new ProcessStartInfo("explorer.exe", dir) { UseShellExecute = true });
        };
        bottomFlow.Controls.Add(openFolderBtn);

        mainPanel.Controls.Add(bottomFlow);

        Controls.Add(mainPanel);

        KeyPreview = true;
        KeyDown += OnFormKeyDown;
    }

    private void AddPresetButton(FlowLayoutPanel panel, string name, uint vkCode)
    {
        var btn = new Button
        {
            Text = name,
            AutoSize = true,
            Height = 32,
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
        _captureButton.Text = "⏳ Drücke jetzt eine Taste (oder Escape zum Abbrechen)...";
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
            _captureButton.BackColor = Color.FromArgb(40, 110, 230);
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
        _captureButton.BackColor = Color.FromArgb(40, 110, 230);

        _keyTrigger.UpdateTriggerKey(vkCode);
        _onSettingsChanged();

        _testStatusLabel.Text = $"✅ Taste geändert zu: {_settings.TriggerKeyName}! Probiere sie jetzt aus.";
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
