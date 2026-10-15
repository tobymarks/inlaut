using Inlaut.Core;

namespace Inlaut.App;

internal sealed class RulesEditor : UserControl
{
    private readonly ListBox _list = new() { Dock = DockStyle.Fill, IntegralHeight = false };
    private readonly bool _snippets;
    private readonly AppSettings _draft;
    private readonly Action _changed;
    public RulesEditor(AppSettings draft, bool snippets, Action changed)
    {
        _draft = draft; _snippets = snippets; _changed = changed;
        Dock = DockStyle.Top; Height = 180; Margin = new Padding(0, 0, 0, 16);
        _list.AccessibleName = snippets ? UiText.Get("Textbausteine") : UiText.Get("Ersetzungen");
        var actions = new FlowLayoutPanel { AutoSizeMode = AutoSizeMode.GrowAndShrink, Dock = DockStyle.Bottom, AutoSize = true };
        foreach (var (label, action) in new (string, Action)[] { (UiText.Get("Hinzufügen…"), () => Edit(-1)), (UiText.Get("Bearbeiten…"), () => Edit(_list.SelectedIndex)), (UiText.Get("Entfernen"), Remove) })
        {
            var button = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = label, AutoSize = true };
            button.Click += (_, _) => action(); actions.Controls.Add(button);
        }
        _list.DoubleClick += (_, _) => { if (_list.SelectedIndex >= 0) Edit(_list.SelectedIndex); };
        Controls.Add(_list); Controls.Add(actions); RefreshItems();
    }
    public void RefreshItems()
    {
        _list.Items.Clear();
        if (_snippets) foreach (var item in _draft.Snippets) _list.Items.Add(item.Phrase + " → " + item.Text.ReplaceLineEndings(" · "));
        else foreach (var item in _draft.Replacements) _list.Items.Add(item.From + " → " + item.To);
    }
    private void Remove()
    {
        int index = _list.SelectedIndex;
        if (index < 0) return;
        if (_snippets) _draft.Snippets.RemoveAt(index); else _draft.Replacements.RemoveAt(index);
        RefreshItems(); _changed(); // Reversible by cancelling the parent settings dialog.
    }
    private void Edit(int index)
    {
        using var dialog = new Form();
        dialog.SuspendLayout();
        dialog.Text = _snippets ? UiText.Get("Textbaustein") : UiText.Get("Ersetzung"); dialog.StartPosition = FormStartPosition.CenterParent;
        dialog.AutoScaleDimensions = new SizeF(96, 96); dialog.AutoScaleMode = AutoScaleMode.Dpi;
        dialog.ClientSize = new Size(480, 360); dialog.MinimumSize = new Size(400, 330);
        dialog.Font = WindowsTheme.Font(); dialog.MinimizeBox = false; dialog.MaximizeBox = false;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(16), ColumnCount = 1, RowCount = 5 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize)); layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize)); layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var from = new TextBox { Dock = DockStyle.Top, AccessibleName = _snippets ? UiText.Get("Sprechphrase") : UiText.Get("Erkanntes Wort") };
        var to = new TextBox { Dock = DockStyle.Fill, Multiline = true, AcceptsReturn = true, ScrollBars = ScrollBars.Vertical, AccessibleName = UiText.Get("Einzufügender Text") };
        if (index >= 0) { from.Text = _snippets ? _draft.Snippets[index].Phrase : _draft.Replacements[index].From; to.Text = _snippets ? _draft.Snippets[index].Text : _draft.Replacements[index].To; }
        layout.Controls.Add(new Label { Text = from.AccessibleName, AutoSize = true }); layout.Controls.Add(from);
        layout.Controls.Add(new Label { Text = _snippets ? UiText.Get("Text (wird unverändert eingefügt)") : UiText.Get("Ersetzen durch (leer = entfernen)"), AutoSize = true }); layout.Controls.Add(to);
        var actions = new FlowLayoutPanel { AutoSizeMode = AutoSizeMode.GrowAndShrink, AutoSize = true, Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft };
        var ok = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = UiText.Get("Übernehmen"), AutoSize = true };
        var cancel = new Button { AutoSizeMode = AutoSizeMode.GrowAndShrink, Text = UiText.Get("Abbrechen"), AutoSize = true, DialogResult = DialogResult.Cancel };
        actions.Controls.Add(ok); actions.Controls.Add(cancel); layout.Controls.Add(actions); dialog.Controls.Add(layout); dialog.CancelButton = cancel;
        ok.Click += (_, _) =>
        {
            var rules = new TextRules { Replacements = _draft.Replacements.ToList(), Snippets = _draft.Snippets.ToList() };
            if (_snippets) { if (index >= 0) rules.Snippets.RemoveAt(index); rules.Snippets.Add(new(from.Text.Trim(), to.Text)); }
            else { if (index >= 0) rules.Replacements.RemoveAt(index); rules.Replacements.Add(new(from.Text.Trim(), to.Text)); }
            try { rules.Validate(); }
            catch (ArgumentException ex) { MessageBox.Show(dialog, UiText.Get(ex.Message), UiText.Get("Bitte prüfen"), MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
            _draft.Replacements = rules.Replacements; _draft.Snippets = rules.Snippets;
            _changed(); RefreshItems(); dialog.DialogResult = DialogResult.OK;
        };
        dialog.ResumeLayout(true);
        dialog.ShowDialog(FindForm());
    }
}


