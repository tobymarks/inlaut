namespace Inlaut.App;

public class DownloadProgressForm : FluentForm
{
    private readonly Label _statusLabel;
    private readonly ProgressBar _progressBar;

    public DownloadProgressForm()
    {
        Text = UiText.Get("inlaut vorbereiten");
        ClientSize = new Size(500, 240);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = MinimizeBox = false;
        // Closing the view must not leave a download reporting to a disposed form.
        ControlBox = false;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.Controls.Add(new Label { Text = UiText.Get("Einmal laden. Offline diktieren."), Font = WindowsTheme.Font(18, FontStyle.Bold), AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 0, 0, 12) });
        layout.Controls.Add(new Label { Text = UiText.Get("Das deutsche Sprachmodell wird heruntergeladen und bleibt auf deinem Rechner."), Tag = "secondary", AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 0, 0, 20) });
        _progressBar = new ProgressBar { Dock = DockStyle.Top, Height = 6, Minimum = 0, Maximum = 100, Margin = new Padding(0, 0, 0, 12), AccessibleName = "Downloadfortschritt" };
        layout.Controls.Add(_progressBar);
        _statusLabel = new Label { Text = UiText.Get("Download wird vorbereitet…"), Tag = "secondary", AutoSize = true, Dock = DockStyle.Top, Margin = Padding.Empty };
        layout.Controls.Add(_statusLabel);
        Controls.Add(layout);
    }

    public void UpdateProgress(string status, int percent)
    {
        if (IsDisposed || Disposing) return;
        if (InvokeRequired) { BeginInvoke(() => UpdateProgress(status, percent)); return; }
        _statusLabel.Text = $"{status}  {Math.Clamp(percent, 0, 100)} %";
        _progressBar.Value = Math.Clamp(percent, 0, 100);
    }
}
