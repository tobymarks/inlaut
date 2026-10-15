using System.Diagnostics;
using Inlaut.Core;

namespace Inlaut.App;

public class SettingsForm : FluentForm
{
    private readonly AppSettings _settings;
    private readonly AppSettings _draft;
    private readonly KeyTrigger _keyTrigger;
    private readonly Action _onSettingsChanged;
    private readonly Action<AppSettings> _save;
    private readonly Action<bool> _startup;
    private readonly AudioRecorder _preview = new();
    private readonly System.Windows.Forms.Timer _meterTimer = new() { Interval = 100 };
    private readonly Label _status = new() { AutoSize = true, Dock = DockStyle.Top, AccessibleRole = AccessibleRole.StatusBar };
    private Label _keyLabel = null!;
    private Button _capture = null!;
    private Button _micTest = null!;
    private ProgressBar _meter = null!;
    private ComboBox _microphones = null!;
    private RulesEditor _replacements = null!, _snippets = null!;
    private bool _dirty, _capturing;
    private DateTime _previewStarted;
    internal AppSettings Draft => _draft;
    internal string Status => _status.Text;

    public SettingsForm(AppSettings settings, KeyTrigger keyTrigger, Action onSettingsChanged,
        Action<AppSettings>? save = null, Action<bool>? startup = null, Action? checkUpdates = null)
    {
        SuspendLayout();
        _settings = settings; _draft = settings.Clone(); _keyTrigger = keyTrigger; _onSettingsChanged = onSettingsChanged;
        _save = save ?? (s => s.Save()); _startup = startup ?? StartupRegistration.SetEnabled;
        if (startup == null)
        {
            try { _draft.LaunchAtLogin = StartupRegistration.IsEnabled(); } catch { }
        }
        Text = "inlaut — Einstellungen"; AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(620, 620); MinimumSize = new Size(480, 480); StartPosition = FormStartPosition.CenterScreen;
        Font = WindowsTheme.Font(); MinimizeBox = false;
        var tabs = new TabControl { Dock = DockStyle.Fill, Multiline = true, AccessibleName = "Einstellungsbereiche" };
        var footer = new FlowLayoutPanel { AutoSizeMode = AutoSizeMode.GrowAndShrink, Dock = DockStyle.Bottom, AutoSize = true, Padding = new Padding(12), FlowDirection = FlowDirection.RightToLeft };
        var saveButton = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Name = "saveSettings", Text = "Speichern", AutoSize = true };
        saveButton.Click += (_, _) => SaveChanges();
        var close = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = "Schließen", AutoSize = true }; close.Click += (_, _) => Close();
        footer.Controls.Add(close); footer.Controls.Add(saveButton);
        var notice = new Label { Text = "Diktieren pausiert · Änderungen gelten nach „Speichern“.", AutoSize = true, Dock = DockStyle.Fill, Padding = new Padding(12) };
        _status.Padding = new Padding(12, 6, 12, 6);
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4 };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize)); root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize)); root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.Controls.Add(notice, 0, 0); root.Controls.Add(tabs, 0, 1); root.Controls.Add(_status, 0, 2); root.Controls.Add(footer, 0, 3);
        Controls.Add(root);

        var dictation = Page(tabs, "Diktieren");
        Heading(dictation, "Diktiertaste");
        _keyLabel = Note(dictation, "Aktuelle Taste: " + AppSettings.GetFriendlyKeyName(_draft.TriggerVkCode));
        var keys = new FlowLayoutPanel { AutoSizeMode = AutoSizeMode.GrowAndShrink, Dock = DockStyle.Top, AutoSize = true };
        _capture = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = "Taste ändern…", AutoSize = true }; _capture.Click += (_, _) => BeginCapture(); keys.Controls.Add(_capture);
        var recommended = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = "F8 verwenden", AutoSize = true }; recommended.Click += (_, _) => CaptureKey(0x77); keys.Controls.Add(recommended); dictation.Controls.Add(keys);
        Note(dictation, "F8 vermeidet Konflikte mit Strg-Kürzeln. Einzelne Buchstaben, Windows-, Tab- und Eingabetasten sind nicht als Diktiertaste verfügbar.");
        Choice(dictation, "Bedienung", ["Halten + Doppeltippen", "Nur halten", "Einmal tippen: Start / Stopp"], ["combined", "hold", "toggle"], _draft.TriggerMode, v => _draft.TriggerMode = v);
        Note(dictation, "Halten: loslassen beendet. Doppeltippen: ein weiterer Tastendruck beendet die Daueraufnahme. Strg+Alt+Leertaste bleibt als zusätzliches Kürzel verfügbar.");
        Heading(dictation, "Mikrofon");
        _microphones = new ComboBox { Name = "microphone", Dock = DockStyle.Top, DropDownStyle = ComboBoxStyle.DropDownList, AccessibleName = "Aufnahmegerät" };
        ReloadDevices();
        _microphones.SelectedIndexChanged += (_, _) => { StopPreview(); if (_microphones.SelectedItem is MicrophoneOption d) { _draft.MicrophoneId = d.Id; Changed(); } };
        dictation.Controls.Add(_microphones);
        var micActions = new FlowLayoutPanel { AutoSizeMode = AutoSizeMode.GrowAndShrink, Dock = DockStyle.Top, AutoSize = true };
        var refresh = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = "Geräte aktualisieren", AutoSize = true }; refresh.Click += (_, _) => { StopPreview(); ReloadDevices(); };
        _micTest = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Name = "testMicrophone", Text = "Mikrofon testen", AutoSize = true }; _micTest.Click += (_, _) => TogglePreview();
        micActions.Controls.Add(_micTest); micActions.Controls.Add(refresh); dictation.Controls.Add(micActions);
        _meter = new ProgressBar { Dock = DockStyle.Top, Height = 18, Maximum = 100, AccessibleName = "Mikrofonpegel" }; dictation.Controls.Add(_meter);
        Note(dictation, "Der Test zeigt nur den Pegel, speichert keinen Ton und endet spätestens nach 30 Sekunden. Das Standardgerät wird bei jedem Aufnahmestart neu ermittelt.");
        _meterTimer.Tick += (_, _) =>
        {
            if (_preview.Failure != null) { string message = "Mikrofon unterbrochen. Gerät prüfen und erneut testen."; StopPreview(); SetStatus(message, true); }
            else if ((DateTime.UtcNow - _previewStarted).TotalSeconds >= 30) StopPreview();
            else _meter.Value = Math.Clamp((int)(_preview.CurrentLevel * 100), 0, 100);
        };

        var text = Page(tabs, "Texteingabe");
        Heading(text, "Einfügen in andere Programme");
        Check(text, "Über Zwischenablage einfügen", _draft.UseClipboardInsertion, v => _draft.UseClipboardInsertion = v);
        Note(text, "Aus: direkte Eingabe, bei manchen Programmen zeichenweise. Ein: Text als Block einfügen; die Zwischenablage wird vorübergehend genutzt. Mehrzeilige Office-Diktate benötigen diesen Modus. In Excel vorher F2 drücken, damit alles in einer Zelle bleibt.");
        Heading(text, "Text aufbereiten");
        Check(text, "Zeilen und Absätze per Sprache", _draft.VoiceCommands, v => _draft.VoiceCommands = v);
        Note(text, "„neue Zeile“ und „neuer Absatz“ erzeugen Umbrüche. Ausgeschaltet bleiben die gesprochenen Wörter erhalten.");
        Check(text, "Eindeutige Wörter mit ß schreiben", _draft.SharpS, v => _draft.SharpS = v);
        Note(text, "Zum Beispiel Straße, groß und Grüße. Eigene Ersetzungen werden anschließend angewendet.");
        Note(text, "Hinweis: Automatische Leerzeichen und Großschreibung zwischen zwei getrennten Diktaten sind noch nicht zuverlässig gelöst.");

        var words = Page(tabs, "Eigene Wörter");
        Heading(words, "Ersetzungen"); Note(words, "Ganze Wörter oder Wortgruppen ersetzen, unabhängig von Groß-/Kleinschreibung.");
        _replacements = new RulesEditor(_draft, false, Changed); words.Controls.Add(_replacements);
        Heading(words, "Textbausteine"); Note(words, "Die Sprechphrase muss das ganze Diktat sein, etwa „meine Signatur“. Der gespeicherte Text wird unverändert eingefügt.");
        _snippets = new RulesEditor(_draft, true, Changed); words.Controls.Add(_snippets);
        var files = new FlowLayoutPanel { AutoSizeMode = AutoSizeMode.GrowAndShrink, AutoSize = true, Dock = DockStyle.Top };
        var import = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = "Importieren…", AutoSize = true }; import.Click += (_, _) => ImportRules();
        var export = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = "Exportieren…", AutoSize = true }; export.Click += (_, _) => ExportRules(); files.Controls.Add(import); files.Controls.Add(export); words.Controls.Add(files);
        Note(words, "JSON-Dateien sind mit inlaut für Mac austauschbar. Import ergänzt die Liste und ersetzt gleiche Einträge; wirksam erst nach Speichern. Export enthält die hier sichtbaren Einträge, auch ungespeicherte Änderungen.");

        var behavior = Page(tabs, "Verhalten");
        Heading(behavior, "Aufnahmeanzeige");
        Choice(behavior, "Position auf dem Bildschirm am Mauszeiger", ["Unten", "Oben"], ["bottom", "top"], _draft.IndicatorPosition, v => _draft.IndicatorPosition = v);
        Check(behavior, "Töne bei Start und Ende", _draft.PlaySounds, v => _draft.PlaySounds = v);
        Check(behavior, "inlaut bei Windows-Anmeldung starten", _draft.LaunchAtLogin, v => _draft.LaunchAtLogin = v);
        Note(behavior, "Autostart öffnet inlaut im Infobereich. Es beginnt keine Aufnahme. Für einen dauerhaften Autostart die installierte Version verwenden.");

        var help = Page(tabs, "Info & Hilfe");
        Heading(help, "Updates");
        Check(help, "Täglich automatisch nach Updates suchen", _draft.AutomaticUpdates, v => { _draft.AutomaticUpdates = v; _draft.UpdateConsentAsked = true; });
        Check(help, "Auch Beta-Versionen anbieten", _draft.BetaUpdates, v => _draft.BetaUpdates = v);
        Note(help, "Update-Suche: Verbindung zu inlaut.de; Download nach Bestätigung von GitHub. Keine Diktate oder Gerätekennung. Stabile Versionen werden auch im Beta-Kanal angeboten. Installation nach deinem Klick mit anschließendem Neustart.");
        var updates = new Button { AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = "Jetzt nach Updates suchen…" };
        updates.Click += (_, _) => { if (checkUpdates != null) checkUpdates(); }; updates.Enabled = checkUpdates != null; help.Controls.Add(updates);
        Heading(help, "Spracherkennung");
        string modelDir = ModelManager.GetModelDirectory();
        bool available = ModelManager.HasValidModel(modelDir);
        long size = Directory.Exists(modelDir) ? Directory.GetFiles(modelDir).Sum(f => new FileInfo(f).Length) : 0;
        Note(help, $"Deutsch · FastConformer INT8 · lokal auf diesem Rechner\nModell: {(available ? "Dateien vorhanden" : "noch nicht vollständig vorhanden")} · {size / 1048576d:F0} MB auf dem Datenträger\nWeitere Sprachen und Modelle sind in dieser Windows-Beta nicht auswählbar.");
        var folder = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = "Modellordner öffnen", AutoSize = true }; folder.Click += (_, _) => OpenFolder(modelDir); help.Controls.Add(folder);
        Heading(help, "Datenschutz und Hilfe");
        Note(help, "Normale Diktate werden nicht als Audio oder Textdatei gespeichert und nicht hochgeladen. Eigene Wörter und Textbausteine werden lokal gespeichert. „Letztes Diktat“ im Tray-Menü hält den letzten Text im Arbeitsspeicher bereit, etwa nach einer abgebrochenen Eingabe.");
        Note(help, "Die gesonderte Funktion „Testaufnahmen speichern“ unter Hilfe & Diagnose speichert dagegen Audio und Text lokal für bis zu 10 Diktate. Diagnoseprotokolle enthalten sonst nur technische Metadaten.");
        var diagnostics = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = "Diagnoseordner öffnen", AutoSize = true }; diagnostics.Click += (_, _) => OpenFolder(LocalDiagnostics.DirectoryPath); help.Controls.Add(diagnostics);
        var feedback = new LinkLabel { Text = "Fehler melden auf GitHub", AutoSize = true }; feedback.LinkClicked += (_, _) => Process.Start(new ProcessStartInfo("https://github.com/tobymarks/inlaut/issues") { UseShellExecute = true }); help.Controls.Add(feedback);
        Note(help, "Version " + LocalDiagnostics.Version.Split('+')[0] + " · Updates werden nur mit gültiger Windows-Signatur und dem vertrauten inlaut-Zertifikat installiert.");
        if (AppSettings.LoadWarning != null) SetStatus(AppSettings.LoadWarning, true);
        FormClosing += (_, e) =>
        {
            EndCapture(); StopPreview();
            if (_dirty && MessageBox.Show(this, "Ungespeicherte Änderungen verwerfen?", "Einstellungen", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) e.Cancel = true;
        };
        FormClosed += (_, _) => { EndCapture(); _preview.Dispose(); _meterTimer.Dispose(); };
        ResumeLayout(true);
    }

    private static TableLayoutPanel Page(TabControl tabs, string title)
    {
        var page = new TabPage(title) { AutoScroll = true, Padding = new Padding(16), UseVisualStyleBackColor = true };
        var table = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 1, GrowStyle = TableLayoutPanelGrowStyle.AddRows };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); page.Controls.Add(table); tabs.TabPages.Add(page); return table;
    }
    private static Label Note(TableLayoutPanel page, string text)
    {
        var label = new Label { Text = text, AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 4, 0, 12) }; page.Controls.Add(label); return label;
    }
    private static void Heading(TableLayoutPanel page, string text) { var label = Note(page, text); label.Font = WindowsTheme.Font(12, FontStyle.Bold); }
    private void Check(TableLayoutPanel page, string label, bool value, Action<bool> set)
    {
        var box = new CheckBox { Text = label, AccessibleName = label, AutoSize = true, Dock = DockStyle.Top, Checked = value, Margin = new Padding(0, 6, 0, 6) };
        box.CheckedChanged += (_, _) => { set(box.Checked); Changed(); }; page.Controls.Add(box);
    }
    private void Choice(TableLayoutPanel page, string label, string[] labels, string[] values, string value, Action<string> set)
    {
        Note(page, label);
        var box = new ComboBox { AccessibleName = label, Dock = DockStyle.Top, DropDownStyle = ComboBoxStyle.DropDownList }; box.Items.AddRange(labels);
        box.SelectedIndex = Math.Max(0, Array.IndexOf(values, value)); box.SelectedIndexChanged += (_, _) => { set(values[box.SelectedIndex]); Changed(); }; page.Controls.Add(box);
    }
    private void Changed() { _dirty = true; SetStatus("Ungespeicherte Änderungen"); }
    private void SetStatus(string text, bool error = false) { _status.Text = text; _status.ForeColor = error ? Color.Firebrick : WindowsTheme.Text; }
    private void BeginCapture()
    {
        if (_capturing) { EndCapture(); return; }
        _capturing = true; _capture.Text = "Taste drücken · Esc bricht ab"; _keyTrigger.SetCaptureMode(v => { if (!IsDisposed) BeginInvoke(() => CaptureKey(v)); });
    }
    private void EndCapture() { _capturing = false; _keyTrigger.EndCaptureMode(); if (_capture != null) _capture.Text = "Taste ändern…"; }
    internal static bool SupportedKey(uint key) => key is >= 0x70 and <= 0x87 or 0xA2 or 0xA3 or 0xA4 or 0xA5 or 0x14;
    private void CaptureKey(uint key)
    {
        EndCapture(); if (key == 0x1B) return;
        if (!SupportedKey(key)) { SetStatus("Bitte eine F-Taste, Strg, Alt oder Caps Lock wählen. F8 ist eine gute erste Wahl.", true); return; }
        _draft.TriggerVkCode = key; _draft.TriggerKeyName = AppSettings.GetFriendlyKeyName(key);
        _keyLabel.Text = "Aktuelle Taste: " + _draft.TriggerKeyName; Changed();
        if (key is 0xA2 or 0xA3 or 0xA4 or 0xA5 or 0x14) SetStatus("Ungespeichert. Diese Taste wird auch von Windows oder anderen Programmen verwendet; bei Konflikten F8 wählen.");
    }
    private void ReloadDevices()
    {
        try
        {
            var devices = AudioRecorder.Devices();
            if (!devices.Any(d => d.Id == _draft.MicrophoneId)) devices.Add(new(_draft.MicrophoneId, "Gewähltes Mikrofon nicht verbunden"));
            _microphones.Items.Clear(); _microphones.Items.AddRange(devices.Cast<object>().ToArray());
            _microphones.SelectedItem = devices.First(d => d.Id == _draft.MicrophoneId);
        }
        catch { SetStatus("Mikrofone konnten nicht abgefragt werden. Verbindung und Windows-Mikrofonzugriff prüfen.", true); }
    }
    internal void TogglePreview()
    {
        if (_preview.IsRecording) { StopPreview(); return; }
        try
        {
            _preview.Start(_draft.MicrophoneId, retainAudio: false); _previewStarted = DateTime.UtcNow;
            _micTest.Text = "Test beenden"; _meterTimer.Start(); SetStatus("Mikrofontest läuft: " + _preview.ActiveDeviceName + " · kein Audio wird gespeichert");
        }
        catch { StopPreview(); SetStatus("Mikrofon nicht verfügbar. Gerät und Windows-Mikrofonzugriff prüfen.", true); }
    }
    private void StopPreview()
    {
        _meterTimer.Stop(); _preview.Dispose();
        if (_micTest != null) _micTest.Text = "Mikrofon testen";
        if (_meter != null) _meter.Value = 0;
        if (_status.Text.StartsWith("Mikrofontest läuft")) SetStatus(_dirty ? "Ungespeicherte Änderungen" : "Mikrofontest beendet");
    }
    internal bool SaveChanges()
    {
        EndCapture(); StopPreview();
        bool startupChanged = _draft.LaunchAtLogin != _settings.LaunchAtLogin;
        try
        {
            _draft.Validate();
            if (startupChanged) _startup(_draft.LaunchAtLogin);
            try { _save(_draft); }
            catch { if (startupChanged) _startup(_settings.LaunchAtLogin); throw; }
            _settings.CopyFrom(_draft.Clone()); _keyTrigger.UpdateTriggerKey(_settings.TriggerVkCode); _keyTrigger.Mode = _settings.TriggerMode;
            _onSettingsChanged(); _dirty = false; SetStatus("Gespeichert. Die Änderungen gelten für das nächste Diktat."); return true;
        }
        catch (Exception ex) { SetStatus("Nicht gespeichert: " + ex.Message, true); return false; }
    }
    internal void MergeRules(string json)
    {
        var rules = new TextRules { Replacements = _draft.Replacements.ToList(), Snippets = _draft.Snippets.ToList() };
        rules.Merge(TextRules.Import(json)); _draft.Replacements = rules.Replacements; _draft.Snippets = rules.Snippets;
        _replacements.RefreshItems(); _snippets.RefreshItems(); Changed();
    }
    private void ImportRules()
    {
        using var dialog = new OpenFileDialog { Filter = "inlaut-Regeln (*.json)|*.json", Title = "Ersetzungen und Textbausteine importieren" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try { if (new FileInfo(dialog.FileName).Length > 2_000_000) throw new IOException("Maximal 2 MB erlaubt."); MergeRules(File.ReadAllText(dialog.FileName)); }
        catch (Exception ex) { SetStatus("Import fehlgeschlagen: " + ex.Message, true); }
    }
    private void ExportRules()
    {
        using var dialog = new SaveFileDialog { Filter = "inlaut-Regeln (*.json)|*.json", FileName = "inlaut-textregeln.json", Title = "Ersetzungen und Textbausteine exportieren" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try { File.WriteAllText(dialog.FileName, new TextRules { Replacements = _draft.Replacements, Snippets = _draft.Snippets }.Export()); SetStatus("Regeln exportiert. Die Datei enthält deine eigenen Texte."); }
        catch (Exception ex) { SetStatus("Export fehlgeschlagen: " + ex.Message, true); }
    }
    private void OpenFolder(string folder)
    {
        try { Directory.CreateDirectory(folder); Process.Start(new ProcessStartInfo("explorer.exe", folder) { UseShellExecute = true }); }
        catch (Exception ex) { SetStatus("Ordner konnte nicht geöffnet werden: " + ex.Message, true); }
    }
}
