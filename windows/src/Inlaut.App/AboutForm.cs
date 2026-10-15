using System.Diagnostics;

namespace Inlaut.App;

public sealed class AboutForm : FluentForm
{
    public AboutForm()
    {
        Text = UiText.Get("Über inlaut");
        ClientSize = new Size(480, 340);
        MinimumSize = new Size(440, 340);
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        var content = new TableLayoutPanel
        {
            Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1,
            AutoScroll = true
        };
        content.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        content.Controls.Add(new Label { Text = "inlaut", Font = WindowsTheme.Font(24, FontStyle.Bold), AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 0, 0, 12) });
        content.Controls.Add(new Label { Text = UiText.Get("Sprich. Der Text ist da."), AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 0, 0, 8) });
        content.Controls.Add(new Label { Text = UiText.Get("Spracherkennung auf deinem Rechner.\nDeine Aufnahmen werden nicht hochgeladen."), Tag = "secondary", AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 0, 0, 20) });
        content.Controls.Add(new Label { Text = $"Version {LocalDiagnostics.Version.Split('+')[0]}", AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 0, 0, 4) });
        string build = LocalDiagnostics.Version.Split('+').ElementAtOrDefault(1) ?? UiText.Get("lokal");
        content.Controls.Add(new Label { Text = "Build " + build[..Math.Min(8, build.Length)], Tag = "secondary", AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 0, 0, 16) });
        var link = new LinkLabel { Text = "inlaut.de", AutoSize = true, LinkColor = WindowsTheme.Accent, Margin = Padding.Empty };
        link.LinkClicked += (_, _) => Process.Start(new ProcessStartInfo("https://inlaut.de") { UseShellExecute = true });
        content.Controls.Add(link);
        var footer = new Panel { Dock = DockStyle.Bottom, Height = 64, Padding = new Padding(24, 12, 24, 12) };
        var close = new FluentButton { Text = UiText.Get("Schließen"), Dock = DockStyle.Right, Width = 110, Accent = true };
        close.Click += (_, _) => Close();
        footer.Controls.Add(close);
        Controls.Add(content);
        Controls.Add(footer);
        AcceptButton = CancelButton = close;
    }
}

internal static class AppDialog
{
    public static void Error(string heading, string message) => Show(heading, message, TaskDialogIcon.Error);
    public static void Information(string heading, string message) => Show(heading, message, TaskDialogIcon.Information);
    private static void Show(string heading, string message, TaskDialogIcon icon) => TaskDialog.ShowDialog(new TaskDialogPage
    {
        Caption = "inlaut", Heading = heading, Text = UiText.Get(message), Icon = icon,
        Buttons = { TaskDialogButton.OK }, AllowCancel = true
    });
}
