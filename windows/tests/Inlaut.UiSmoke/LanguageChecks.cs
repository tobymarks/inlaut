using Inlaut.App;
using Inlaut.Core;
using System.Globalization;

namespace Inlaut.UiSmoke;
internal static class LanguageChecks
{
    internal static async Task Run(KeyTrigger trigger)
    {
        string root = Path.Combine(Path.GetTempPath(), "inlaut-language-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        var culture = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("en-US");
            string path = Path.Combine(root, "settings.json");
            if (AppSettings.Load(path).SpeechLanguage != "en") throw new Exception("English first-run default missing");
            File.WriteAllText(path, "{}");
            if (AppSettings.Load(path).SpeechLanguage != "de") throw new Exception("Legacy German settings changed language");
            var settings = new AppSettings { SpeechLanguage = "en", InterfaceLanguage = "en" };
            settings.Save(path);
            if (AppSettings.Load(path).InterfaceLanguage != "en" || AppSettings.Load(path).SpeechLanguage != "en") throw new Exception("Language persistence failed");
            var pipeline = new TextPipeline(); settings.ApplyTo(pipeline);
            if (pipeline.ProcessDictation("First line new line second line new paragraph last paragraph") != "First line\nSecond line\n\nLast paragraph") throw new Exception("English commands failed");
            if (pipeline.ProcessDictation("gross") != "gross") throw new Exception("German spelling changed English speech");
            settings.ApplyTo(pipeline, "de");
            if (pipeline.ProcessDictation("neue Zeile") != "\n" || pipeline.ProcessDictation("new line") != "new line") throw new Exception("Pending language changed running pipeline");
            foreach (var file in ModelManager.ForLanguage("de").Files)
                using (var stream = File.Create(Path.Combine(root, file.Name))) stream.SetLength(file.Size);
            string english = ModelManager.ResolveDirectory("en", root, Path.Combine(root, "user"));
            if (english == root || ModelManager.HasValidModel(root, "en")) throw new Exception("English selected legacy German model");
            try { ModelManager.VerifyModel(root, "de"); throw new Exception("Corrupt model accepted"); }
            catch (InvalidDataException) { }
            UiText.Language = "en";
            using var form = new SettingsForm(settings, trigger, () => { });
            form.Show(); await Task.Delay(80);
            var tabs = Descendants(form).OfType<TabControl>().Single();
            if (tabs.TabPages[0].Text != "Dictation" || !Descendants(form).Any(c => c.Text == "Dictation language")) throw new Exception("English settings missing");
            foreach (TabPage page in tabs.TabPages)
            {
                tabs.SelectedTab = page; await Task.Delay(30);
                using var bitmap = new Bitmap(form.Width, form.Height);
                form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, form.Size));
                bitmap.Save(Path.Combine(AppContext.BaseDirectory, "settings-en-" + tabs.SelectedIndex + ".png"));
            }
            form.Close();
            Console.WriteLine("PASS: English UI, settings migration, language persistence, commands, model isolation and corruption rejection");
        }
        finally { UiText.Language = "de"; CultureInfo.CurrentUICulture = culture; Directory.Delete(root, true); }
    }
    private static IEnumerable<Control> Descendants(Control root) => root.Controls.Cast<Control>().SelectMany(c => new[] { c }.Concat(Descendants(c)));
}
