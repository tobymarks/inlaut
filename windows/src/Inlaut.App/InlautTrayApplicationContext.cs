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
    private bool _isTranscribing;
    private bool _isExiting;
    private DirectTextInserter.InputTarget? _dictationTarget;
    private string? _lastDictation;
    private int _captureRemaining;
    private string? _captureRoot;
    private Icon _defaultIcon = null!;
    private Icon _recordingIcon = null!;

    public InlautTrayApplicationContext()
    {
        LocalDiagnostics.Write("startup", new { os = Environment.OSVersion.VersionString });
        _settings = AppSettings.Load();
        _recorder = new AudioRecorder();
        _pipeline = new TextPipeline();
        _settings.ApplyTo(_pipeline);
        _hotkeyReceiver = new HotkeyReceiver();
        _indicator = new RecordingIndicatorForm();
        _keyTrigger = new KeyTrigger(_indicator, _settings.TriggerVkCode);
        _keyTrigger.Mode = _settings.TriggerMode;
        _indicator.PositionPreference = _settings.IndicatorPosition;
        _recorder.DeviceFailed += () =>
        {
            if (!_indicator.IsDisposed) _indicator.BeginInvoke(new Action(() =>
            {
                if (_recorder.IsRecording) StopDictation();
            }));
        };

        InitIcons();

        var contextMenu = new FluentMenu();
        var statusItem = new ToolStripMenuItem("inlaut · Wird vorbereitet") { Enabled = false };
        _dictateMenuItem = FluentMenu.Item("Diktat starten", "\uE720", (_, _) => ToggleDictation());
        var settingsItem = FluentMenu.Item("Einstellungen…", "\uE713", (_, _) => OpenSettings());
        var lastDictationItem = FluentMenu.Item("Letztes Diktat…", "\uE8A5", (_, _) =>
        {
            if (_lastDictation != null) new DictationReviewForm(_lastDictation).Show();
        });
        var helpItem = new ToolStripMenuItem("Hilfe && Diagnose") { Tag = "\uE897" };
        var clipboardItem = new ToolStripMenuItem("Eingabe per Zwischenablage")
        {
            CheckOnClick = true,
            Checked = _settings.UseClipboardInsertion,
            ToolTipText = "Aus: direkte Texteingabe ohne Zwischenablage. Ein: bisheriger Einfügeweg zum Vergleich."
        };
        clipboardItem.Click += (_, _) =>
        {
            bool previous = _settings.UseClipboardInsertion;
            try { _settings.UseClipboardInsertion = clipboardItem.Checked; _settings.Save(); }
            catch (Exception ex) { _settings.UseClipboardInsertion = previous; clipboardItem.Checked = previous; AppDialog.Error("Einstellung nicht gespeichert", ex.Message); }
        };
        helpItem.DropDownItems.Add(clipboardItem);
        helpItem.DropDownItems.Add(new ToolStripSeparator());
        helpItem.DropDownItems.Add(FluentMenu.Item("Modellordner öffnen", "\uE8B7", (_, _) => OpenModelFolder()));
        helpItem.DropDownItems.Add(FluentMenu.Item("Diagnoseordner öffnen", "\uE9D9", (_, _) =>
        {
            Directory.CreateDirectory(LocalDiagnostics.DirectoryPath);
            Process.Start(new ProcessStartInfo("explorer.exe", LocalDiagnostics.DirectoryPath) { UseShellExecute = true });
        }));
        var captureItem = new ToolStripMenuItem("Testaufnahmen speichern")
        {
            ToolTipText = "Speichert bis zu 10 Diktate mit Audio und Text lokal. Keine Übertragung."
        };
        captureItem.Click += (_, _) =>
        {
            if (_captureRemaining > 0) _captureRemaining = 0;
            else
            {
                _captureRemaining = 10;
                _captureRoot = Path.Combine(LocalDiagnostics.DirectoryPath, "captures", DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N")[..8]);
                _notifyIcon?.ShowBalloonTip(5000, "Testaufnahmen aktiviert", "Die nächsten 10 Diktate werden mit Audio und Text lokal im Diagnoseordner gespeichert. Keine automatische Übertragung.", ToolTipIcon.Info);
            }
            captureItem.Checked = _captureRemaining > 0;
        };
        helpItem.DropDownItems.Add(captureItem);
        var reportItem = FluentMenu.Item("Letzten Fehlerbericht ansehen…", "\uE9D9", (_, _) => new CrashReportForm(CrashJournal.Current).Show());
        helpItem.DropDownItems.Add(reportItem);
        helpItem.DropDownItems.Add(new ToolStripSeparator());
        helpItem.DropDownItems.Add(FluentMenu.Item("Über inlaut", "\uE946", (_, _) => ShowAbout()));
        contextMenu.Items.AddRange(new ToolStripItem[]
        {
            statusItem, new ToolStripSeparator(), _dictateMenuItem, lastDictationItem, settingsItem, helpItem,
            new ToolStripSeparator(), FluentMenu.Item("Beenden", "\uE7E8", (_, _) => Exit())
        });
        contextMenu.Opening += (_, _) =>
        {
            reportItem.Enabled = CrashJournal.Current.ReadReport() != null;
            clipboardItem.Checked = _settings.UseClipboardInsertion;
            lastDictationItem.Enabled = _lastDictation != null && !_recorder.IsRecording && !_isTranscribing;
            captureItem.Checked = _captureRemaining > 0;
            captureItem.Enabled = !_recorder.IsRecording && !_isTranscribing;
            clipboardItem.Enabled = !_recorder.IsRecording && !_isTranscribing;
            captureItem.Text = _captureRemaining > 0 ? $"Testaufnahmen speichern ({_captureRemaining} übrig)" : "Testaufnahmen speichern";
            statusItem.Text = "inlaut · " + (_recorder.IsRecording ? "Aufnahme läuft" : _isTranscribing ? "Text wird erkannt" : _isModelReady ? "Bereit" : "Wird vorbereitet");
            _dictateMenuItem.Text = _recorder.IsRecording ? "Diktat beenden" : "Diktat starten";
            _dictateMenuItem.Tag = _recorder.IsRecording ? "\uE71A" : "\uE720";
            _dictateMenuItem.ShortcutKeyDisplayString = AppSettings.GetFriendlyKeyName(_settings.TriggerVkCode);
            _dictateMenuItem.Enabled = _isModelReady && !_isTranscribing && !_keyTrigger.IsSuspended;
            settingsItem.Enabled = !_recorder.IsRecording && !_isTranscribing;
        };

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

        _indicator.BeginInvoke(new Action(() =>
        {
            _ = InitializeModelAsync();
            if (CrashJournal.Current.ReadReport() != null) new CrashReportForm(CrashJournal.Current).Show();
            if (AppSettings.LoadWarning != null) AppDialog.Information("Einstellungen prüfen", AppSettings.LoadWarning);
        }));
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
                using var progressForm = new DownloadProgressForm();
                progressForm.Show();

                modelDir = await ModelManager.EnsureModelAvailableAsync((status, percent) =>
                {
                    progressForm.UpdateProgress(status, percent);
                });

                await Task.Delay(400);
                progressForm.Close();
                progressForm.Dispose();
            }

            var loadTimer = Stopwatch.StartNew();
            var engine = await Task.Run(() => new SherpaEngine(modelDir, threads: Math.Clamp(Environment.ProcessorCount / 2, 2, 4)));
            if (_isExiting) { engine.Dispose(); return; }
            _engine = engine;
            LocalDiagnostics.Write("model-ready", new
            {
                loadSeconds = loadTimer.Elapsed.TotalSeconds,
                configuration = engine.DiagnosticConfiguration,
                files = Directory.GetFiles(modelDir).Where(p => p.EndsWith(".onnx") || p.EndsWith("tokens.txt"))
                    .Select(p => new { name = Path.GetFileName(p), bytes = new FileInfo(p).Length }).ToArray()
            });
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
            if (_isExiting) return;
            _notifyIcon.Text = "inlaut - Fehler beim Laden des Modells";
            AppDialog.Error("Sprachmodell konnte nicht geladen werden", ex.Message);
        }
    }

    private void UpdateReadyStatus()
    {
        _settings.ApplyTo(_pipeline);
        _indicator.PositionPreference = _settings.IndicatorPosition;
        _keyTrigger.Mode = _settings.TriggerMode;
        _notifyIcon.Text = _isModelReady ? $"inlaut - Bereit ({_settings.TriggerKeyName})" : "inlaut - Lade Sprachmodell...";
        if (_dictateMenuItem != null)
        {
            _dictateMenuItem.Text = "Diktat starten";
            _dictateMenuItem.ShortcutKeyDisplayString = AppSettings.GetFriendlyKeyName(_settings.TriggerVkCode);
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
        if (_isTranscribing || _keyTrigger.IsSuspended) return;

        if (!_isModelReady || _engine == null)
        {
            _indicator.ShowMessage("Modell wird vorbereitet…");
            return;
        }

        if (_recorder.IsRecording) return;

        try
        {
            _dictationTarget = DirectTextInserter.CaptureTarget();
            if (_settings.PlaySounds) RecordingSounds.Play(starting: true);
            _recorder.Start(_settings.MicrophoneId);
            LocalDiagnostics.Write("recording", new { });
            _notifyIcon.Icon = _recordingIcon;
            _notifyIcon.Text = _captureRemaining > 0 ? "inlaut - Testaufnahme (Audio + Text werden gespeichert)" : "inlaut - Aufnahme läuft...";

            // Show floating indicator at bottom center
            _indicator.ShowRecording(() => _recorder.CurrentLevel);
        }
        catch (Exception ex)
        {
            AppDialog.Error("Mikrofon konnte nicht gestartet werden", ex.Message);
        }
    }

    private async void StopDictation()
    {
        if (!_recorder.IsRecording || _isTranscribing || _engine == null) return;

        var engine = _engine;
        _isTranscribing = true;
        _notifyIcon.Icon = _defaultIcon;
        _notifyIcon.Text = "inlaut - Transkribiere...";
        _indicator.ShowTranscribing();
        string? statusMessage = null;

        try
        {
            float[] samples = _recorder.Stop();
            if (_settings.PlaySounds) RecordingSounds.Play(starting: false);
            LocalDiagnostics.Write("recorded", LocalDiagnostics.DescribeAudio(samples));
            bool captureRequested = _captureRemaining > 0;
            string? captureRoot = _captureRoot;
            if (captureRequested) _captureRemaining--;
            if (samples.Length < 1600 && !captureRequested)
            {
                statusMessage = "Zu kurz aufgenommen";
                return;
            }
            bool captureFailed = false;

            string processed = await Task.Run(() =>
            {
                DictationCapture? capture = null;
                void Save(Action action)
                {
                    try { action(); }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                    {
                        captureFailed = true;
                        LocalDiagnostics.Write("capture-write-failed", new { type = ex.GetType().Name });
                    }
                }
                if (captureRequested && captureRoot != null)
                    Save(() => capture = new DictationCapture(captureRoot, samples, 16000, new
                    {
                        version = LocalDiagnostics.Version, utc = DateTimeOffset.UtcNow,
                        microphoneDeviceIndex = 0, engine = engine.DiagnosticConfiguration,
                        voiceCommands = _pipeline.VoiceCommandsEnabled, sharpS = _pipeline.SharpSEnabled,
                        languages = _pipeline.Languages.Select(x => x.ToString()).ToArray(),
                        replacements = _pipeline.ReplacementsList
                    }));
                try
                {
                    var (rawText, audioSec, decodeSec, rtf) = engine.TranscribeSamples(samples, 16000,
                        prepared => { if (capture != null) Save(() => capture.Prepared(prepared)); });
                    LocalDiagnostics.Write("recognized", new
                    {
                        audioSec, decodeSec, rtf, text = LocalDiagnostics.DescribeText(rawText)
                    });
                    string processed = _pipeline.ProcessDictation(rawText);
                    if (capture != null) Save(() => capture.Complete(rawText, processed, audioSec, decodeSec));
                    LocalDiagnostics.Write("processed", LocalDiagnostics.DescribeText(processed));
                    return processed;
                }
                catch (Exception ex)
                {
                    if (capture != null) Save(() => capture.Failed(ex.GetType().Name));
                    throw;
                }
            });
            if (captureFailed)
                _notifyIcon.ShowBalloonTip(4000, "Testaufnahme nicht vollständig gespeichert", "Bitte freien Speicherplatz und den Diagnoseordner prüfen. Das Diktieren bleibt verfügbar.", ToolTipIcon.Warning);
            if (string.IsNullOrWhiteSpace(processed))
            {
                statusMessage = "Keine Sprache erkannt";
                return;
            }
            string inputMethod = "clipboard";
            _lastDictation = processed; // Memory only, replaced by the next recognized dictation.
            if (_dictationTarget == null) throw new InvalidOperationException("Kein ursprüngliches Eingabefeld verfügbar.");
            if (_settings.UseClipboardInsertion)
                await ClipboardTextInserter.InsertAsync(processed, _dictationTarget);
            else
                inputMethod = await DirectTextInserter.InsertAsync(processed, expectedTarget: _dictationTarget);
            LocalDiagnostics.Write("input-sent", new { characters = processed.Length,
                method = inputMethod });
        }
        catch (Exception ex)
        {
            LocalDiagnostics.Write("failed", new { type = ex.GetType().Name, code = ex.HResult });
            _notifyIcon.ShowBalloonTip(5000, "Diktat konnte nicht abgeschlossen werden", ex.Message +
                (_lastDictation != null ? " Der zuletzt erkannte Text ist im Menü unter „Letztes Diktat“ verfügbar." : ""), ToolTipIcon.Error);
        }
        finally
        {
            _isTranscribing = false;
            if (statusMessage != null) _indicator.ShowMessage(statusMessage);
            else _indicator.HideIndicator();
            UpdateReadyStatus();
        }
    }

    private void OpenSettings()
    {
        if (_settingsForm == null || _settingsForm.IsDisposed)
        {
            if (_recorder.IsRecording || _isTranscribing) return;
            _settingsForm = new SettingsForm(_settings, _keyTrigger, UpdateReadyStatus);
            _settingsForm.FormClosed += (_, _) => _keyTrigger.IsSuspended = false;
        }

        _keyTrigger.IsSuspended = true;
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
        var about = new AboutForm();
        about.Show();
    }

    private void Exit()
    {
        if (_isTranscribing)
        {
            _notifyIcon.ShowBalloonTip(2000, "inlaut", "Bitte die laufende Transkription abwarten.", ToolTipIcon.Info);
            return;
        }
        _isExiting = true;
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
