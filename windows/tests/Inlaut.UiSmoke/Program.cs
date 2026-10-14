using Inlaut.App;

namespace Inlaut.UiSmoke;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        using var host = new Form();
        using var trigger = new KeyTrigger(host);
        using var watchdog = new System.Threading.Timer(_ => Environment.Exit(2), null, 30_000, Timeout.Infinite);
        int result = 0;
        host.Shown += async (_, _) =>
        {
            try
            {
                using (var settings = new SettingsForm(new AppSettings(), trigger, () => { }))
                {
                    settings.Show();
                    var keyLabel = Descendants(settings).OfType<Label>()
                        .Single(label => label.Text.StartsWith("Aktuelle Taste:"));
                    for (int i = 0; i < 150; i++)
                    {
                        settings.ClientSize = new Size(460 + i % 7 * 80, 460 + i % 5 * 90);
                        // Exercise the same relayout as changing the key, without
                        // touching the user's settings file or microphone.
                        keyLabel.Text = i % 2 == 0 ? "Aktuelle Taste: F8" : "Aktuelle Taste: Rechte Alt / Option";
                        await Task.Delay(1);
                        if (settings.Controls.Cast<Control>().Any(c => c.Width < 0))
                            throw new Exception("Invalid layout bounds");
                    }
                    settings.Close();
                }
                Console.WriteLine("PASS: 150 settings resizes and key-label changes");

                using (var menu = new FluentMenu())
                {
                    menu.Items.Add(FluentMenu.Item("Diktat starten", "\uE720", (_, _) => { }));
                    menu.Items.Add(FluentMenu.Item("Einstellungen…", "\uE713", (_, _) => { }));
                    var images = new Dictionary<ToolStripItem, Rectangle>();
                    var texts = new Dictionary<ToolStripItem, Rectangle>();
                    menu.Show(host, new Point(20, 20));
                    menu.Renderer.RenderItemImage += (_, e) => images[e.Item] = e.ImageRectangle;
                    menu.Renderer.RenderItemText += (_, e) => { if (e.Text == e.Item.Text) texts[e.Item] = e.TextRectangle; };
                    menu.Invalidate();
                    await Task.Delay(100);
                    if (images.Count != 2 || texts.Count != 2) throw new Exception("Menu did not render native image/text slots");
                    foreach (var item in images.Keys)
                        if (images[item].IntersectsWith(texts[item])) throw new Exception("Menu image overlaps text");
                    menu.Close();
                }
                Console.WriteLine("PASS: menu image and text occupy separate native layout slots");

                // Opt-in only: this test operates the clipboard and keyboard.
                // Run on an isolated interactive Windows test desktop.
                if (args.Contains("--paste"))
                {
                    using var editor = new RichTextBox { Dock = DockStyle.Fill };
                    host.Controls.Add(editor);
                    host.Activate();
                    editor.Focus();
                    trigger.Start();
                    int triggers = 0;
                    trigger.OnStart = () => triggers++;
                    Clipboard.SetText("clipboard sentinel");
                    const string expected = "Erstes Wort, danach ein vollständiger Satz: Grüße, Straße, 100000!\nZweite Zeile?";
                    await ClipboardTextInserter.InsertAsync(expected);
                    if (editor.Text.ReplaceLineEndings("\n") != expected) throw new Exception("Paste text differs");
                    if (Clipboard.GetText() != "clipboard sentinel") throw new Exception("Clipboard not restored");
                    if (triggers != 0) throw new Exception("Injected shortcut triggered dictation");

                    editor.Clear();
                    var paste = ClipboardTextInserter.InsertAsync(expected);
                    await Task.Delay(200);
                    Clipboard.SetText("new copy during paste");
                    await paste;
                    if (Clipboard.GetText() != "new copy during paste") throw new Exception("New clipboard copy overwritten");
                    Console.WriteLine("PASS: paste, clipboard restore, concurrent copy, injected-key filtering");
                }
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); result = 1; }
            finally { host.Close(); }
        };
        Application.Run(host);
        return result;
    }

    private static IEnumerable<Control> Descendants(Control root) =>
        root.Controls.Cast<Control>().SelectMany(c => new[] { c }.Concat(Descendants(c)));
}
