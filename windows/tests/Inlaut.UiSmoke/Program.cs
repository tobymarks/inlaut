using Inlaut.App;

namespace Inlaut.UiSmoke;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 3 && args[0] == "--english-model")
        {
            ModelManager.VerifyModel(args[1], "en");
            using var engine = new Inlaut.Platform.Windows.SherpaEngine(args[1], provider: "cpu", threads: 2);
            var (text, _, _, _) = engine.TranscribeFile(args[2]);
            if (!text.StartsWith("Well, I don't wish to see it any more", StringComparison.OrdinalIgnoreCase) || !text.Contains("old portrait", StringComparison.OrdinalIgnoreCase))
                throw new Exception("English reference transcription differs: " + text);
            Console.WriteLine("PASS: packaged English model recognises the reference recording with the Windows engine");
            return 0;
        }
        if (args.Length == 3 && args[0] == "--crash-child")
        {
            var journal = new CrashJournal(args[1]); journal.Begin();
            journal.NoteStage("recognized"); journal.NoteStage("SECRET_TRANSCRIPT");
            if (args[2] == "clean") { journal.EndCleanly(); return 0; }
            if (args[2] == "fault")
            {
                try { throw new InvalidOperationException("SECRET_TRANSCRIPT C:\\Users\\Private\\note.txt"); }
                catch (Exception error) { journal.Record(error); }
            }
            System.Diagnostics.Process.GetCurrentProcess().Kill();
            return 1;
        }
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        using var host = new Form();
        using var trigger = new KeyTrigger(host);
        using var watchdog = new System.Threading.Timer(_ => Environment.Exit(2), null, 90_000, Timeout.Infinite);
        int result = 0;
        host.Shown += async (_, _) =>
        {
            try
            {
                await SettingsChecks.Run(host, trigger, args.Contains("--hardware"));
                await LanguageChecks.Run(trigger);
                await CrashChecks.Run();
                await UpdateChecks.Run();
                if (args.Contains("--transitions")) await TransitionChecks.Run(host);
                foreach (int pixels in new[] { 20, 25, 30, 35, 40, 50, 60 })
                foreach (string glyph in new[] { "\uE720", "\uE71A", "\uE713", "\uE8A5", "\uE897", "\uE8B7", "\uE9D9", "\uE946", "\uE7E8" })
                {
                    using var icon = FluentMenu.Glyph(glyph, pixels);
                    bool hasInk = false;
                    for (int y = 0; y < pixels; y++)
                    for (int x = 0; x < pixels; x++)
                    {
                        if (icon.GetPixel(x, y).A == 0) continue;
                        hasInk = true;
                        if (x == 0 || y == 0 || x == pixels - 1 || y == pixels - 1)
                            throw new Exception($"Clipped menu icon {glyph} at {pixels}px");
                    }
                    if (!hasInk) throw new Exception("Empty menu icon");
                }
                Console.WriteLine("PASS: all nine menu glyphs have unclipped ink at 100–300% sizes");
                using (var indicator = new RecordingIndicatorForm())
                {
                    indicator.ShowMessage("Keine Sprache erkannt", 100);
                    if (indicator.Phase != IndicatorPhase.Message || !indicator.Visible || indicator.AccessibleDescription != "Keine Sprache erkannt")
                        throw new Exception("Empty-speech status not visible.");
                    await Task.Delay(250);
                    if (indicator.Visible) throw new Exception("Status did not dismiss.");
                    indicator.ShowMessage("Zu kurz aufgenommen", 100);
                    indicator.ShowRecording(() => 0);
                    await Task.Delay(250);
                    if (!indicator.Visible || indicator.Phase != IndicatorPhase.Recording)
                        throw new Exception("Old message timer hid a new recording.");
                    indicator.ShowMessage("Keine Sprache erkannt", 100);
                    indicator.ShowTranscribing();
                    await Task.Delay(250);
                    if (!indicator.Visible || indicator.Phase != IndicatorPhase.Transcribing)
                        throw new Exception("Old message timer hid recognition.");
                    indicator.HideIndicator();
                }
                Console.WriteLine("PASS: compact status dismisses and never hides a subsequent recording/recognition");
                using (var settings = new SettingsForm(new AppSettings(), trigger, () => { }))
                {
                    settings.Show();
                    using (var bitmap = new Bitmap(settings.Width, settings.Height))
                    {
                        settings.DrawToBitmap(bitmap, new Rectangle(Point.Empty, settings.Size));
                        bitmap.Save(Path.Combine(AppContext.BaseDirectory, "settings-native.png"));
                    }
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

                using (var recovery = new DictationReviewForm("Grüße, Straße, 100000!\nZweite Zeile."))
                {
                    recovery.Show();
                    recovery.Size = recovery.MinimumSize;
                    await Task.Delay(100);
                    var editor = Descendants(recovery).OfType<RichTextBox>().Single();
                    if (!editor.ReadOnly || editor.Text != "Grüße, Straße, 100000!\nZweite Zeile." || editor.Height <= 0)
                        throw new Exception($"Recovery text/layout is invalid: readonly={editor.ReadOnly}, height={editor.Height}, text={editor.Text.Length}, size={recovery.Size}");
                    recovery.Close();
                }
                Console.WriteLine("PASS: recovery view preserves text in a read-only field at minimum size");

                using (var menu = new FluentMenu())
                {
                    menu.Items.Add(new ToolStripMenuItem("inlaut · Bereit") { Enabled = false });
                    menu.Items.Add(new ToolStripSeparator());
                    var dictate = FluentMenu.Item("Diktat starten", "\uE720", (_, _) => { });
                    dictate.ShortcutKeyDisplayString = "Strg links";
                    menu.Items.Add(dictate);
                    menu.Items.Add(FluentMenu.Item("Einstellungen…", "\uE713", (_, _) => { }));
                    var help = new ToolStripMenuItem("Hilfe && Diagnose") { Tag = "\uE897" };
                    help.DropDownItems.Add(new ToolStripMenuItem("Eingabe per Zwischenablage") { Checked = true });
                    help.DropDownItems.Add(new ToolStripSeparator());
                    help.DropDownItems.Add(FluentMenu.Item("Modellordner öffnen", "\uE8B7", (_, _) => { }));
                    help.DropDownItems.Add(FluentMenu.Item("Diagnoseordner öffnen", "\uE9D9", (_, _) => { }));
                    help.DropDownItems.Add(new ToolStripMenuItem("Testaufnahmen speichern"));
                    menu.Items.Add(help);
                    menu.Items.Add(new ToolStripSeparator());
                    menu.Items.Add(FluentMenu.Item("Beenden", "\uE7E8", (_, _) => { }));
                    var images = new Dictionary<ToolStripItem, Rectangle>();
                    var texts = new Dictionary<ToolStripItem, Rectangle>();
                    menu.Show(host, new Point(20, 20));
                    menu.Renderer.RenderItemImage += (_, e) => images[e.Item] = e.ImageRectangle;
                    menu.Renderer.RenderItemText += (_, e) => { if (e.Text == e.Item.Text) texts[e.Item] = e.TextRectangle; };
                    menu.Invalidate();
                    await Task.Delay(100);
                    if (images.Count != 4 || texts.Count != 5) throw new Exception("Menu did not render native image/text slots");
                    foreach (var item in images.Keys)
                        if (images[item].IntersectsWith(texts[item])) throw new Exception("Menu image overlaps text");
                    using (var bitmap = new Bitmap(menu.Width, menu.Height))
                    {
                        menu.DrawToBitmap(bitmap, menu.ClientRectangle);
                        bitmap.Save(Path.Combine(AppContext.BaseDirectory, "menu-native.png"));
                    }
                    help.ShowDropDown();
                    await Task.Delay(100);
                    using (var bitmap = new Bitmap(help.DropDown.Width, help.DropDown.Height))
                    {
                        help.DropDown.DrawToBitmap(bitmap, help.DropDown.ClientRectangle);
                        bitmap.Save(Path.Combine(AppContext.BaseDirectory, "submenu-native.png"));
                    }
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
