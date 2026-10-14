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
    private readonly TextPipeline _pipeline;
    private SherpaEngine? _engine;
    private bool _isModelReady;
    private Icon _defaultIcon = null!;
    private Icon _recordingIcon = null!;

    public InlautTrayApplicationContext()
    {
        _recorder = new AudioRecorder();
        _pipeline = new TextPipeline();
        _hotkeyReceiver = new HotkeyReceiver();

        InitIcons();

        var contextMenu = new ContextMenuStrip();
        var dictateItem = new ToolStripMenuItem("🎙️ Diktat starten / stoppen (Strg+Alt+Leertaste)", null, (s, e) => ToggleDictation());
        var openFolderItem = new ToolStripMenuItem("📁 Modell-Ordner öffnen", null, (s, e) => OpenModelFolder());
        var aboutItem = new ToolStripMenuItem("ℹ️ Über inlaut", null, (s, e) => ShowAbout());
        var exitItem = new ToolStripMenuItem("❌ Beenden", null, (s, e) => Exit());

        contextMenu.Items.Add(dictateItem);
        contextMenu.Items.Add(new ToolStripSeparator());
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

            _notifyIcon.Text = "inlaut - Bereit (Strg+Alt+Leertaste)";
            _notifyIcon.ShowBalloonTip(3000, "inlaut ist bereit", "Drücke Strg+Alt+Leertaste, um die Aufnahme zu starten und zu stoppen.", ToolTipIcon.Info);
        }
        catch (Exception ex)
        {
            _notifyIcon.Text = "inlaut - Fehler beim Laden des Modells";
            MessageBox.Show($"Fehler beim Initialisieren des Sprachmodells:\n\n{ex.Message}", "inlaut Fehler", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void ToggleDictation()
    {
        if (!_isModelReady || _engine == null)
        {
            _notifyIcon.ShowBalloonTip(2000, "inlaut", "Das Sprachmodell wird noch vorbereitet...", ToolTipIcon.Warning);
            return;
        }

        if (!_recorder.IsRecording)
        {
            // Start recording
            try
            {
                _recorder.Start();
                _notifyIcon.Icon = _recordingIcon;
                _notifyIcon.Text = "inlaut - Aufnahme läuft... (Strg+Alt+Leertaste zum Beenden)";
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Mikrofon konnte nicht gestartet werden:\n{ex.Message}", "inlaut Fehler", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
        else
        {
            // Stop recording & transcribe
            _notifyIcon.Icon = _defaultIcon;
            _notifyIcon.Text = "inlaut - Transkribiere...";

            float[] samples = _recorder.Stop();

            if (samples.Length < 1600) // Less than 0.1s
            {
                _notifyIcon.Text = "inlaut - Bereit (Strg+Alt+Leertaste)";
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
                    _notifyIcon.Text = "inlaut - Bereit (Strg+Alt+Leertaste)";
                }
            });
        }
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
            "• Keine Daten verlassen deinen Rechner\n" +
            "• Tastenkürzel: Strg + Alt + Leertaste\n\n" +
            "https://inlaut.de",
            "Über inlaut",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information
        );
    }

    private void Exit()
    {
        _recorder.Dispose();
        _hotkeyReceiver.Dispose();
        _engine?.Dispose();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        ExitThread();
    }
}
