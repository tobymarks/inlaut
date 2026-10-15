using System.Diagnostics;

namespace Inlaut.App;

internal sealed class CrashReportForm : FluentForm
{
    public CrashReportForm(CrashJournal journal)
    {
        SuspendLayout(); AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi;
        Text = UiText.Get("inlaut wurde unerwartet beendet"); ClientSize = new Size(620, 510); MinimumSize = new Size(480, 380);
        Font = WindowsTheme.Font(); StartPosition = FormStartPosition.CenterScreen;
        var report = journal.ReadReport() ?? UiText.Get("Kein lesbarer Bericht vorhanden.");
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(16), ColumnCount = 1, RowCount = 4 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize)); layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize)); layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var info = new Label { Dock = DockStyle.Fill, AutoSize = true, Text = UiText.Get("Beim letzten Mal wurde inlaut nicht regulär beendet. Das kann ein Absturz, ein erzwungenes Beenden oder ein Stromausfall gewesen sein. Es wurde nichts gesendet.\n\nDieser lokale Bericht enthält nur Version, Windows-Version, Zeitpunkt, letzte Verarbeitungsphase und gegebenenfalls technische Fehlerstellen. Keine Aufnahmen, Diktate oder eigenen Wörter."), Margin = new Padding(0, 0, 0, 12) };
        var preview = new TextBox { Multiline = true, ReadOnly = true, Dock = DockStyle.Fill, ScrollBars = ScrollBars.Both, WordWrap = false, Text = report, AccessibleName = UiText.Get("Technischer Bericht zur Prüfung") };
        var status = new Label { Dock = DockStyle.Fill, AutoSize = true, Text = UiText.Get("GitHub-Meldungen sind öffentlich. Erst im Browser wird die Meldung endgültig abgeschickt."), Margin = new Padding(0, 12, 0, 12) };
        var actions = new FlowLayoutPanel { AutoSizeMode = AutoSizeMode.GrowAndShrink, Dock = DockStyle.Fill, AutoSize = true };
        var save = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = UiText.Get("Bericht speichern…"), AutoSize = true };
        save.Click += (_, _) =>
        {
            using var dialog = new SaveFileDialog { Filter = UiText.Get("Technischer Bericht (*.json)|*.json"), FileName = "inlaut-fehlerbericht.json" };
            if (dialog.ShowDialog(this) != DialogResult.OK) return;
            try { File.WriteAllText(dialog.FileName, report); status.Text = UiText.Get("Bericht lokal gespeichert. Es wurde nichts gesendet."); }
            catch (Exception ex) { status.Text = UiText.Get("Speichern fehlgeschlagen: ") + ex.GetType().Name; }
        };
        var send = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = UiText.Get("GitHub-Meldung vorbereiten…"), AutoSize = true };
        send.Click += (_, _) =>
        {
            if (MessageBox.Show(this, UiText.Get("Der angezeigte Bericht wird an GitHub übergeben und dort in eine neue Meldung eingetragen. Er wird erst nach deinem Absenden im Browser öffentlich. Fortfahren?"), UiText.Get("Bericht an GitHub übergeben"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            try
            {
                // Opening this URL itself transmits the report to GitHub; the
                // confirmation above explicitly covers that transfer.
                string url = BuildIssueUrl(report);
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                status.Text = url.Contains("attach") ? UiText.Get("GitHub geöffnet. Den Bericht bitte als Datei speichern und dort anhängen, dann absenden.") : UiText.Get("GitHub geöffnet. Bitte prüfen und die Meldung im Browser absenden.");
            }
            catch { status.Text = UiText.Get("Browser konnte nicht geöffnet werden. Bericht als Datei speichern und manuell melden."); }
        };
        var later = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = UiText.Get("Später"), AutoSize = true }; later.Click += (_, _) => Close();
        var dismiss = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = "Verwerfen", AutoSize = true }; dismiss.Click += (_, _) => { journal.Dismiss(); Close(); };
        actions.Controls.AddRange([save, send, later, dismiss]);
        layout.Controls.Add(info); layout.Controls.Add(preview); layout.Controls.Add(status); layout.Controls.Add(actions); Controls.Add(layout); ResumeLayout(true);
    }

    internal static string BuildIssueUrl(string report)
    {
        const string prefix = "https://github.com/tobymarks/inlaut/issues/new?title=Windows%20beta%3A%20unexpected%20termination&body=";
        string body = "inlaut ended unexpectedly.\n\nWhat I was doing: (please describe without private dictation text)\n\n```json\n" + report + "\n```";
        string url = prefix + Uri.EscapeDataString(body);
        // Stay below shell/browser URL limits. Large reports are explicitly
        // attached by the user, never silently truncated or uploaded elsewhere.
        return url.Length <= 1800 ? url : prefix + Uri.EscapeDataString("inlaut ended unexpectedly. Please attach the exported inlaut-fehlerbericht.json and describe what happened without private dictation text.");
    }
}


