using System.Drawing;
using System.Windows.Forms;

namespace Inlaut.App;

public class DownloadProgressForm : Form
{
    private readonly Label _titleLabel;
    private readonly Label _statusLabel;
    private readonly ProgressBar _progressBar;

    public DownloadProgressForm()
    {
        Text = "inlaut";
        Width = 480;
        Height = 220;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;
        MinimizeBox = false;
        BackColor = Color.FromArgb(248, 249, 250);

        _titleLabel = new Label
        {
            Text = "inlaut wird vorbereitet",
            Font = new Font("Segoe UI", 14, FontStyle.Bold),
            ForeColor = Color.FromArgb(20, 20, 20),
            Location = new Point(30, 25),
            AutoSize = true
        };

        var subtitleLabel = new Label
        {
            Text = "Das lokale deutsche Sprachmodell wird für die Offline-Nutzung geladen.",
            Font = new Font("Segoe UI", 9.5f, FontStyle.Regular),
            ForeColor = Color.FromArgb(100, 100, 100),
            Location = new Point(30, 60),
            Width = 410,
            Height = 35
        };

        _progressBar = new ProgressBar
        {
            Location = new Point(30, 105),
            Width = 405,
            Height = 18,
            Minimum = 0,
            Maximum = 100,
            Value = 5
        };

        _statusLabel = new Label
        {
            Text = "Initialisiere...",
            Font = new Font("Segoe UI", 9, FontStyle.Regular),
            ForeColor = Color.FromArgb(80, 80, 80),
            Location = new Point(30, 132),
            Width = 405,
            AutoSize = false
        };

        Controls.Add(_titleLabel);
        Controls.Add(subtitleLabel);
        Controls.Add(_progressBar);
        Controls.Add(_statusLabel);
    }

    public void UpdateProgress(string status, int percent)
    {
        if (InvokeRequired)
        {
            BeginInvoke(() => UpdateProgress(status, percent));
            return;
        }

        _statusLabel.Text = status;
        _progressBar.Value = Math.Clamp(percent, 0, 100);
    }
}
