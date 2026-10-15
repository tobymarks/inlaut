namespace Inlaut.App;

/// <summary>Transient recovery view; no disk writes or automatic clipboard access.</summary>
internal sealed class DictationReviewForm : FluentForm
{
    public DictationReviewForm(string text)
    {
        Text = UiText.Get("inlaut — Letztes Diktat");
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoScaleDimensions = new SizeF(96, 96);
        ClientSize = new Size(620, 380);
        MinimumSize = new Size(380, 260);
        StartPosition = FormStartPosition.CenterScreen;
        Font = WindowsTheme.Font();
        var editor = new RichTextBox { Dock = DockStyle.Fill, ReadOnly = true, Text = text,
            BackColor = WindowsTheme.Surface, ForeColor = WindowsTheme.Text, BorderStyle = BorderStyle.None };
        var note = new Label { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(12),
            Text = UiText.Get("Prüfe vor erneutem Einfügen, ob bereits ein Teil im Ziel steht. Diese Ansicht speichert keinen Text auf der Festplatte.") };
        note.MaximumSize = new Size(ClientSize.Width, 0);
        ClientSizeChanged += (_, _) => note.MaximumSize = new Size(ClientSize.Width, 0);
        var actions = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 54, Padding = new Padding(8), FlowDirection = FlowDirection.RightToLeft };
        var close = new Button { Text = UiText.Get("Schließen"), AutoSize = true };
        close.Click += (_, _) => Close();
        var copy = new Button { Text = UiText.Get("Text kopieren"), AutoSize = true };
        copy.Click += (_, _) =>
        {
            try { Clipboard.SetText(text); }
            catch (Exception ex) { AppDialog.Error(UiText.Get("Kopieren nicht möglich"), UiText.Get(ex.Message)); }
        };
        actions.Controls.Add(close); actions.Controls.Add(copy);
        Controls.Add(editor); Controls.Add(note); Controls.Add(actions);
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        MinimumSize = new Size(380 * DeviceDpi / 96, 300 * DeviceDpi / 96);
    }

    protected override void OnDpiChanged(DpiChangedEventArgs e)
    {
        base.OnDpiChanged(e);
        MinimumSize = new Size(380 * e.DeviceDpiNew / 96, 300 * e.DeviceDpiNew / 96);
    }
}
