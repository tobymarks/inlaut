using Inlaut.App;
using Inlaut.Core;
using NAudio.Wave;
using System.Text.Json;

namespace Inlaut.UiSmoke;

internal static class SettingsChecks
{
    public static async Task Run(Form host, KeyTrigger trigger, bool hardware)
    {
        string folder = Path.Combine(Path.GetTempPath(), "inlaut-settings-test-" + Guid.NewGuid());
        Directory.CreateDirectory(folder);
        try
        {
            string path = Path.Combine(folder, "settings.json");
            var original = new AppSettings();
            int changed = 0; bool startup = false;
            using (var settings = new SettingsForm(original, trigger, () => changed++, s => s.Save(path), v => startup = v))
            {
                settings.Show();
                var tabs = Descendants(settings).OfType<TabControl>().Single();
                foreach (TabPage page in tabs.TabPages)
                {
                    tabs.SelectedTab = page; await Task.Delay(40);
                    using var bitmap = new Bitmap(settings.Width, settings.Height);
                    settings.DrawToBitmap(bitmap, new Rectangle(Point.Empty, settings.Size));
                    bitmap.Save(Path.Combine(AppContext.BaseDirectory, "settings-" + tabs.SelectedIndex + ".png"));
                }
                // Exercise the real controls, save transaction and reload path.
                foreach (var box in Descendants(settings).OfType<CheckBox>()) box.Checked = !box.Checked;
                var draft = settings.Draft;
                draft.IndicatorPosition = "top"; draft.TriggerMode = "toggle"; draft.TriggerVkCode = 0x77; draft.TriggerKeyName = "F8";
                settings.MergeRules("""{"replacements":[{"from":"Testwort","to":"$1 Euro"}],"snippets":[{"phrase":"Meine Signatur","text":"  Grüße\n\nTeam  "}]}""");
                if (original.UseClipboardInsertion || original.Replacements.Count != 0) throw new Exception("Unsaved draft affected live settings.");
                if (!settings.SaveChanges() || changed != 1 || !startup) throw new Exception("Settings save did not apply.");
                var loaded = AppSettings.Load(path);
                if (!loaded.UseClipboardInsertion || loaded.VoiceCommands || loaded.SharpS || !loaded.PlaySounds || !loaded.LaunchAtLogin || loaded.IndicatorPosition != "top" || loaded.TriggerMode != "toggle" || loaded.TriggerVkCode != 0x77)
                    throw new Exception("Settings did not survive reload.");
                var pipeline = new TextPipeline(); loaded.ApplyTo(pipeline);
                if (pipeline.ProcessDictation("Testwort") != "$1 Euro" || pipeline.ProcessDictation("MEINE SIGNATUR.") != "  Grüße\n\nTeam  " || pipeline.ProcessDictation("neue Zeile") != "neue Zeile")
                    throw new Exception("Persisted rules/options not effective.");
                if (pipeline.ProcessDictation("Hier ist meine Signatur für dich") == "  Grüße\n\nTeam  ") throw new Exception("Snippet matched part of a sentence.");
                var exported = new TextRules { Replacements = loaded.Replacements, Snippets = loaded.Snippets }.Export();
                var imported = TextRules.Import(exported);
                if (imported.Snippets.Single().Text != "  Grüße\n\nTeam  ") throw new Exception("Snippet whitespace changed on round trip.");
                settings.MergeRules("""{"replacements":[{"from":"testwort","to":"Neu"}]}""");
                if (settings.Draft.Replacements.Count != 1 || settings.Draft.Snippets.Count != 1) throw new Exception("Import merge differs.");
                foreach (var invalid in new[] { "{}", "{\"snippets\":null}", "{\"snippets\":[{\"phrase\":\"x\",\"text\":\"a\"},{\"phrase\":\"X.\",\"text\":\"b\"}]}" })
                {
                    bool rejected = false; try { settings.MergeRules(invalid); } catch { rejected = true; }
                    if (!rejected || settings.Draft.Snippets.Count != 1) throw new Exception("Invalid import modified draft.");
                }
                if (!settings.SaveChanges()) throw new Exception("Second save failed");
                // Open and complete the actual multiline snippet editor, rather
                // than only manipulating the draft model behind the controls.
                var snippetEditor = Descendants(settings).OfType<RulesEditor>().Single(e => Descendants(e).OfType<ListBox>().Single().AccessibleName == "Textbausteine");
                tabs.SelectedIndex = 2;
                tabs.SelectedTab!.ScrollControlIntoView(snippetEditor);
                Exception? dialogError = null;
                using (var completeDialog = new System.Windows.Forms.Timer { Interval = 100 })
                {
                    completeDialog.Tick += (_, _) =>
                    {
                        var dialog = Application.OpenForms.Cast<Form>().FirstOrDefault(f => f.Text == "Textbaustein");
                        if (dialog == null) return;
                        completeDialog.Stop();
                        try
                        {
                            Descendants(dialog).OfType<TextBox>().Single(b => b.AccessibleName == "Sprechphrase").Text = "Testabschluss";
                            Descendants(dialog).OfType<TextBox>().Single(b => b.AccessibleName == "Einzufügender Text").Text = "Erste Zeile\r\n\r\nZweite Zeile";
                            using var bitmap = new Bitmap(dialog.Width, dialog.Height);
                            dialog.DrawToBitmap(bitmap, new Rectangle(Point.Empty, dialog.Size)); bitmap.Save(Path.Combine(AppContext.BaseDirectory, "snippet-editor.png"));
                            Descendants(dialog).OfType<Button>().Single(b => b.Text == "Übernehmen").PerformClick();
                        }
                        catch (Exception error) { dialogError = error; dialog.Close(); }
                    };
                    completeDialog.Start();
                    Descendants(snippetEditor).OfType<Button>().Single(b => b.Text == "Hinzufügen…").PerformClick();
                }
                if (dialogError != null) throw dialogError;
                if (!settings.Draft.Snippets.Any(s => s.Phrase == "Testabschluss" && s.Text.ReplaceLineEndings("\n") == "Erste Zeile\n\nZweite Zeile"))
                    throw new Exception("Real snippet dialog did not save multiline text.");
                if (!settings.SaveChanges()) throw new Exception("Snippet dialog persistence failed.");
                settings.Close();
            }
            Console.WriteLine("PASS: real settings controls, save/reload, pipeline options, literal replacement, snippets and Mac-schema import/export");

            var live = new AppSettings(); bool startupState = false;
            using (var failing = new SettingsForm(live, trigger, () => throw new Exception("Must not apply"), _ => throw new IOException("test write failure"), v => startupState = v))
            {
                failing.Draft.LaunchAtLogin = true;
                failing.Draft.UseClipboardInsertion = true;
                if (failing.SaveChanges() || live.UseClipboardInsertion || startupState || !failing.Status.StartsWith("Nicht gespeichert"))
                    throw new Exception("Failed save was reported/applied as success.");
            }
            string corrupt = Path.Combine(folder, "broken.json"); File.WriteAllText(corrupt, "broken"); AppSettings.Load(corrupt);
            if (AppSettings.LoadWarning == null || File.ReadAllText(corrupt) != "broken") throw new Exception("Corrupt settings overwritten or hidden.");
            AppSettings.Load(path);
            if (SettingsForm.SupportedKey(0x41) || SettingsForm.SupportedKey(0x5B) || !SettingsForm.SupportedKey(0x77)) throw new Exception("Unsafe trigger accepted");
            Console.WriteLine("PASS: write failure rollback, corrupt-file preservation and unsafe-key rejection");

            using (var pcm = new MemoryStream())
            {
                using (var writer = new BinaryWriter(pcm, System.Text.Encoding.UTF8, true))
                    for (int i = 0; i < 48000; i++) { float value = .2f * (float)Math.Sin(2 * Math.PI * 440 * i / 48000); writer.Write(value); writer.Write(value); }
                var converted = AudioRecorder.ConvertTo16kMono(pcm.ToArray(), WaveFormat.CreateIeeeFloatWaveFormat(48000, 2));
                if (Math.Abs(converted.Length - 16000) > 10 || converted.Max(Math.Abs) < .15 || converted.Max(Math.Abs) > .25)
                    throw new Exception("Microphone conversion changed duration or level.");
            }
            Console.WriteLine("PASS: 48 kHz stereo microphone-format conversion to 16 kHz mono");

            var down = typeof(KeyTrigger).GetMethod("HandleKeyDown", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!;
            var up = typeof(KeyTrigger).GetMethod("HandleKeyUp", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!;
            int starts = 0, stops = 0; trigger.OnStart = () => starts++; trigger.OnStop = () => stops++;
            trigger.IsSuspended = false; trigger.Mode = "toggle";
            down.Invoke(trigger, null); down.Invoke(trigger, null); up.Invoke(trigger, null); await Task.Delay(30);
            if (starts != 1 || stops != 0) throw new Exception("Toggle repeats caused duplicate recording.");
            down.Invoke(trigger, null); up.Invoke(trigger, null); await Task.Delay(30);
            if (stops != 1) throw new Exception("Toggle failed to stop.");
            trigger.IsSuspended = true; trigger.IsSuspended = false; trigger.Mode = "hold";
            down.Invoke(trigger, null); await Task.Delay(300); up.Invoke(trigger, null); await Task.Delay(30);
            if (starts != 2 || stops != 2) throw new Exception("Hold mode failed.");
            Console.WriteLine("PASS: hold/toggle trigger state machine including key-repeat suppression (no physical keys injected)");
            trigger.IsSuspended = true; trigger.IsSuspended = false; trigger.Mode = "combined";
            down.Invoke(trigger, null); up.Invoke(trigger, null); down.Invoke(trigger, null); up.Invoke(trigger, null); await Task.Delay(30);
            down.Invoke(trigger, null); up.Invoke(trigger, null); await Task.Delay(30);
            if (starts != 3 || stops != 3) throw new Exception("Combined double-tap mode failed.");
            using (var indicator = new RecordingIndicatorForm())
            {
                indicator.PositionPreference = "top"; indicator.ShowMessage("Test"); int top = indicator.Top;
                indicator.PositionPreference = "bottom"; indicator.ShowMessage("Test");
                if (indicator.Top <= top) throw new Exception("Indicator position preference ignored.");
                indicator.HideIndicator();
            }
            Console.WriteLine("PASS: combined double-tap mode and actual top/bottom indicator positioning");

            string requestPath = Path.Combine(AppContext.BaseDirectory, "settings-audio-request.json");
            if (File.Exists(requestPath))
            {
                using var request = JsonDocument.Parse(File.ReadAllText(requestPath));
                using var engine = new Inlaut.Platform.Windows.SherpaEngine(request.RootElement.GetProperty("Model").GetString()!, threads: 2);
                string audio = request.RootElement.GetProperty("Audio").GetString()!;
                using var wav = new WaveFileReader(audio);
                byte[] bytes = new byte[wav.Length]; wav.ReadExactly(bytes);
                var samples = AudioRecorder.ConvertTo16kMono(bytes, wav.WaveFormat);
                var raw = engine.TranscribeSamples(samples, 16000).Text;
                var pipeline = new TextPipeline();
                var option = new AppSettings { VoiceCommands = true, Replacements = [new("Lieferung", "Bestellung")] }; option.ApplyTo(pipeline);
                var processed = pipeline.ProcessDictation(raw);
                if (!processed.Contains('\n') || !processed.Contains("Bestellung")) throw new Exception("Audio-to-settings processing differs.");
                using var editor = new RichTextBox { Dock = DockStyle.Fill }; host.Controls.Add(editor); host.Activate(); editor.Focus();
                await Inlaut.Platform.Windows.DirectTextInserter.InsertAsync(processed);
                if (editor.Text.ReplaceLineEndings("\n") != processed.ReplaceLineEndings("\n")) throw new Exception("Audio to editor differs.");
                File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "settings-audio-results.json"), JsonSerializer.Serialize(new { raw, processed, exact = true }));
                Console.WriteLine("PASS: audio -> microphone conversion -> recognition -> settings/rules -> native editor");
            }
            if (hardware)
            {
                RecordingSounds.Play(starting: true); RecordingSounds.Play(starting: false);
                using (var runKey = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    object? previous = runKey.GetValue("inlaut");
                    var kind = previous == null ? Microsoft.Win32.RegistryValueKind.String : runKey.GetValueKind("inlaut");
                    try
                    {
                        StartupRegistration.SetEnabled(true);
                        if (!StartupRegistration.IsEnabled()) throw new Exception("Autostart registration missing");
                        StartupRegistration.SetEnabled(false);
                        if (StartupRegistration.IsEnabled()) throw new Exception("Autostart registration not removed");
                    }
                    finally { if (previous == null) runKey.DeleteValue("inlaut", false); else runKey.SetValue("inlaut", previous, kind); }
                }
                Console.WriteLine("PASS: real per-user autostart registration/readback/removal; previous registration restored (login itself not exercised)");
                using var recorder = new AudioRecorder(); recorder.Start(retainAudio: false); await Task.Delay(1500);
                if (recorder.Failure != null || string.IsNullOrEmpty(recorder.ActiveDeviceName)) throw new Exception("Physical microphone preview failed.");
                if (recorder.Stop().Length != 0) throw new Exception("Preview retained audio");
                recorder.Start(); await Task.Delay(1500); var samples = recorder.Stop();
                if (samples.Length < 8000) throw new Exception("Physical microphone produced no audio frames.");
                var device = AudioRecorder.Devices().First(d => d.Id.Length > 0);
                recorder.Start(device.Id, retainAudio: false); await Task.Delay(500); recorder.Stop();
                bool missing = false; try { recorder.Start("inlaut-test-missing-device"); } catch { missing = true; }
                if (!missing) throw new Exception("Missing device not rejected");
                recorder.Start(retainAudio: false); await Task.Delay(300); recorder.Stop();
                Console.WriteLine("PASS: physical default/selected microphone, no-retention preview, missing-device rejection and recovery");
            }
        }
        finally { Directory.Delete(folder, true); }
    }
    private static IEnumerable<Control> Descendants(Control root) => root.Controls.Cast<Control>().SelectMany(c => new[] { c }.Concat(Descendants(c)));
}
