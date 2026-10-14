using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Windows.Forms;
using Inlaut.Core;
using Inlaut.Platform.Windows;

namespace Inlaut.App;

public class InlautTrayApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _notifyIcon;
    private readonly AudioRecorder _recorder;
    private readonly HotkeyReceiver _hotkeyReceiver;
    private readonly KeyTrigger _keyTrigger;
    private readonly RecordingIndicatorForm _indicator;
    private readonly TextPipeline _pipeline;
    private readonly AppSettings _settings;
    private ToolStripMenuItem? _dictateMenuItem;
    private SettingsForm? _settingsForm;
    private SherpaEngine? _engine;
    private bool _isModelReady;
    private Icon _defaultIcon = null!;
    private Icon _recordingIcon = null!;

    public InlautTrayApplicationContext()
    {
        _settings = AppSettings.Load();
        _recorder = new AudioRecorder();
        _pipeline = new TextPipeline();
        _hotkeyReceiver = new HotkeyReceiver();
        _keyTrigger = new KeyTrigger(_settings.TriggerVkCode);
        _indicator = new RecordingIndicatorForm();

        InitIcons();

        var contextMenu = new ContextMenuStrip();
        _dictateMenuItem = new ToolStripMenuItem($"🎙️ Diktat starten / stoppen ({_settings.TriggerKeyName})", null, (s, e) => ToggleDictation());
        var settingsItem = new ToolStripMenuItem("⚙️ Einstellungen (Taste festlegen)...", null, (s, e) => OpenSettings());
        var openFolderItem = new ToolStripMenuItem("📁 Modell-Ordner öffnen", null, (s, e) => OpenModelFolder());
        var aboutItem = new ToolStripMenuItem("ℹ️ Über inlaut", null, (s, e) => ShowAbout());
        var exitItem = new ToolStripMenuItem("❌ Beenden", null, (s, e) => Exit());

        contextMenu.Items.Add(_dictateMenuItem);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add(settingsItem);
        contextMenu.Items.Add(openFolderItem);
        contextMenu.Items.Add(aboutItem);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add(exitItem);

        _notifyIcon = new NotifyIcon
        {
            Icon = _defaultIcon,
            ContextMenuStrip = contextMenu,
            Text = "inlaut - Initialisiere Sprachmodell...",
            Visible = true
        };

        _notifyIcon.DoubleClick += (s, e) => ToggleDictation();

        // 1. Single Key Hold-to-Talk & Double-Tap Hands-Free
        _keyTrigger.OnStart = () => StartDictation();
        _keyTrigger.OnStop = () => StopDictation();
        _keyTrigger.Start();

        // 2. Global Shortcut fallback (Ctrl+Alt+Space)
        _hotkeyReceiver.HotkeyPressed += ToggleDictation;
        _hotkeyReceiver.RegisterDefaultHotkey();

        _ = InitializeModelAsync();
    }

    private void InitIcons()
    {
        try
        {
            var assembly = Assembly.GetExecutingAssembly();
            using var stream = assembly.GetManifestResourceStream("Inlaut.App.Resources.inlaut-32.png");
            if (stream != null)
            {
                using var bmp = new Bitmap(stream);
                _defaultIcon = Icon.FromHandle(bmp.GetHicon());

                // Create a recording icon with a red circle in the corner
                using var recBmp = new Bitmap(bmp);
                using (var g = Graphics.FromImage(recBmp))
                {
                    g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                    using var brush = new SolidBrush(Color.Red);
                    g.FillEllipse(brush, recBmp.Width - 12, recBmp.Height - 12, 11, 11);
                }
                _recordingIcon = Icon.FromHandle(recBmp.GetHicon());
                return;
            }
        }
        catch
        {
            // Fallback
        }

        _defaultIcon = SystemIcons.Application;
        _recordingIcon = SystemIcons.Warning;
    }

    private async Task InitializeModelAsync()
    {
        try
        {
            string modelDir = ModelManager.GetModelDirectory();
            if (!ModelManager.HasValidModel(modelDir))
            {
                var progressForm = new DownloadProgressForm();
                progressForm.Show();

                modelDir = await ModelManager.EnsureModelAvailableAsync((status, percent) =>
                {
                    progressForm.UpdateProgress(status, percent);
                });

                await Task.Delay(400);
                progressForm.Close();
                progressForm.Dispose();
            }

            _engine = new SherpaEngine(modelDir);
            _isModelReady = true;

            UpdateReadyStatus();
            _notifyIcon.ShowBalloonTip(
                3500,
                "inlaut ist bereit",
                $"• {_settings.TriggerKeyName} halten: Diktieren bis zum Loslassen\n• Doppeltippen: Daueraufnahme\n• Taste ändern: Rechtsklick auf Tray -> Einstellungen",
                ToolTipIcon.Info
            );
        }
        catch (Exception ex)
        {
            _notifyIcon.Text = "inlaut - Fehler beim Laden des Modells";
            MessageBox.Show($"Fehler beim Initialisieren des Sprachmodells:\n\n{ex.Message}", "inlaut Fehler", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void UpdateReadyStatus()
    {
        _notifyIcon.Text = $"inlaut - Bereit ({_settings.TriggerKeyName})";
        if (_dictateMenuItem != null)
        {
            _dictateMenuItem.Text = $"🎙️ Diktat starten / stoppen ({_settings.TriggerKeyName})";
        }
    }

    private void ToggleDictation()
    {
        if (_recorder.IsRecording)
        {
            StopDictation();
        }
        else
        {
            StartDictation();
        }
    }

    private void StartDictation()
    {
        if (!_isModelReady || _engine == null)
        {
            _notifyIcon.ShowBalloonTip(2000, "inlaut", "Das Sprachmodell wird noch vorbereitet...", ToolTipIcon.Warning);
            return;
        }

        if (_recorder.IsRecording) return;

        try
        {
            _recorder.Start();
            _notifyIcon.Icon = _recordingIcon;
            _notifyIcon.Text = "inlaut - Aufnahme läuft...";

            // Show floating indicator at bottom center
            _indicator.ShowRecording(() => _recorder.CurrentLevel);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Mikrofon konnte nicht gestartet werden:\n{ex.Message}", "inlaut Fehler", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void StopDictation()
    {
        if (!_recorder.IsRecording) return;

        _notifyIcon.Icon = _defaultIcon;
        _notifyIcon.Text = "inlaut - Transkribiere...";
        _indicator.ShowTranscribing();

        float[] samples = _recorder.Stop();

        if (samples.Length < 1600) // Less than 0.1s
        {
            UpdateReadyStatus();
            _indicator.HideIndicator();
            return;
        }

        Task.Run(() =>
        {
            try
            {
                var (rawText, audioSec, decodeSec, rtf) = _engine.TranscribeSamples(samples, 16000);

                if (!string.IsNullOrWhiteSpace(rawText))
                {
                    string processed = _pipeline.ProcessDictation(rawText);
                    TextInserter.InsertText(processed);
                }
            }
            catch (Exception ex)
            {
                _notifyIcon.ShowBalloonTip(3000, "inlaut Transkriptionsfehler", ex.Message, ToolTipIcon.Error);
            }
            finally
            {
                _indicator.Invoke(() => _indicator.HideIndicator());
                UpdateReadyStatus();
            }
        });
    }

    private void OpenSettings()
    {
        if (_settingsForm == null || _settingsForm.IsDisposed)
        {
            _settingsForm = new SettingsForm(_settings, _keyTrigger, UpdateReadyStatus);
        }

        _settingsForm.Show();
        _settingsForm.BringToFront();
    }

    private void OpenModelFolder()
    {
        string dir = ModelManager.GetModelDirectory();
        if (Directory.Exists(dir))
        {
            Process.Start(new ProcessStartInfo("explorer.exe", dir) { UseShellExecute = true });
        }
        else
        {
            string appData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "inlaut");
            Directory.CreateDirectory(appData);
            Process.Start(new ProcessStartInfo("explorer.exe", appData) { UseShellExecute = true });
        }
    }

    private void ShowAbout()
    {
        MessageBox.Show(
            "inlaut — Lokales Diktieren für Windows\nVersion 0.5.0-prototype\n\n" +
            "• 100% On-Device & Offline Speech-to-Text\n" +
            "• Keine Daten verlassen deinen Rechner\n\n" +
            "Bedienung:\n" +
            $"• Halten: {_settings.TriggerKeyName} gedrückt halten zum Diktieren\n" +
            $"• Freihand: {_settings.TriggerKeyName} doppeltippen\n" +
            "• Tastenkürzel: Strg + Alt + Leertaste\n" +
            "• Taste ändern: Rechtsklick auf Tray -> Einstellungen\n\n" +
            "https://inlaut.de",
            "Über inlaut",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information
        );
    }

    private void Exit()
    {
        _settingsForm?.Dispose();
        _keyTrigger.Dispose();
        _indicator.Dispose();
        _recorder.Dispose();
        _hotkeyReceiver.Dispose();
        _engine?.Dispose();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        ExitThread();
    }
}
