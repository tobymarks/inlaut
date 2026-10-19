using Inlaut.Core;

var pipeline = new TextPipeline { VoiceCommandsEnabled = false, SharpSEnabled = false };
foreach (var text in new[] { "100000 Euro", "Warte...", "Jaaa!", "Grüße, Straße, Öl?", "Zeile eins\n\nZeile zwei" })
{
    if (pipeline.ProcessDictation(text) != text)
        throw new Exception("Text was corrupted by preprocessing");
}
Console.WriteLine("PASS: numbers, ellipses, repeated letters, Unicode and line breaks preserved");

var commands = new TextPipeline();
if (commands.ProcessDictation("Erste Zeile neue Zeile zweite Zeile neuer Absatz letzter Absatz") != "Erste Zeile\nZweite Zeile\n\nLetzter Absatz")
    throw new Exception("German line/paragraph commands differ.");
Console.WriteLine("PASS: German new-line and new-paragraph commands produce expected breaks");
foreach (var pair in new[] { ("neue Zeile", "\n"), ("neuer Absatz", "\n\n"), ("neue Zeile Zweite Zeile.", "\nZweite Zeile."), ("Hallo. neuer Absatz Danke.", "Hallo.\n\nDanke."), ("Ende neue Zeile", "Ende\n") })
    if (commands.ProcessDictation(pair.Item1) != pair.Item2) throw new Exception("Edge command or explicit punctuation lost");
Console.WriteLine("PASS: standalone and edge line/paragraph commands and explicit punctuation preserved");

foreach (int dpi in new[] { 96, 120, 144, 168, 192, 240, 288 })
{
    foreach (int textWidth in new[] { 90, 180, 360 })
    {
        var measured = new System.Drawing.Size((int)Math.Ceiling(textWidth * dpi / 96.0), (int)Math.Ceiling(22 * dpi / 96.0));
        var layout = Inlaut.App.IndicatorLayout.Create(dpi, measured);
        if (layout.Icon.Right >= layout.Text.Left || layout.Text.Right >= layout.Bars.Left ||
            layout.Bars.Right >= layout.Size.Width || layout.Text.Bottom >= layout.Size.Height || layout.Text.Size != measured)
            throw new Exception($"HUD overlap at {dpi} DPI");
    }
}
Console.WriteLine("PASS: nonoverlapping HUD geometry at 100–300% scaling and enlarged text");

string captureRoot = Path.Combine(Path.GetTempPath(), "inlaut-capture-test-" + Guid.NewGuid());
try
{
    // Every possible microphone PCM16 value must survive saving exactly.
    float[] samples = Enumerable.Range(short.MinValue, 65536).Select(n => n / 32768f).ToArray();
    var capture = new DictationCapture(captureRoot, samples, 16000, new { test = true });
    capture.Prepared(samples[100..200]);
    capture.Complete("Grüße 100000", "Grüße 100000", .00625, .01);
    using var reader = new BinaryReader(File.OpenRead(Path.Combine(capture.DirectoryPath, "recorded.wav")));
    if (new string(reader.ReadChars(4)) != "RIFF" || reader.ReadInt32() != 36 + samples.Length * 2)
        throw new Exception("Invalid WAV header");
    reader.BaseStream.Position = 20;
    if (reader.ReadInt16() != 1 || reader.ReadInt16() != 1 || reader.ReadInt32() != 16000)
        throw new Exception("Incorrect PCM format");
    reader.BaseStream.Position = 44;
    for (int i = short.MinValue; i <= short.MaxValue; i++)
        if (reader.ReadInt16() != i) throw new Exception("Microphone sample changed during capture");
    if (new FileInfo(Path.Combine(capture.DirectoryPath, "recognizer-input.wav")).Length != 244)
        throw new Exception("Wrong prepared audio length");
    using var result = System.Text.Json.JsonDocument.Parse(File.ReadAllText(Path.Combine(capture.DirectoryPath, "result.json")));
    if (result.RootElement.GetProperty("rawText").GetString() != "Grüße 100000") throw new Exception("Transcript mismatch");
    var second = new DictationCapture(captureRoot, [], 16000, new { test = true });
    second.Prepared([]);
    second.Complete("", "", 0, 0);
    if (capture.DirectoryPath == second.DirectoryPath) throw new Exception("Capture overwritten");
    Console.WriteLine("PASS: lossless PCM16 capture, prepared audio, Unicode transcript and empty result");
}
finally { Directory.Delete(captureRoot, true); }

var english = new TextPipeline { Languages = [SpokenLanguage.English] };
if (english.ProcessDictation("First line new line second line new paragraph last paragraph") != "First line\nSecond line\n\nLast paragraph" || english.ProcessDictation("gross") != "gross" || english.ProcessDictation("neue Zeile") != "neue Zeile")
    throw new Exception("English pipeline commands or language isolation failed");
Console.WriteLine("PASS: English commands and isolation from German spelling/commands");

foreach (var (input, expected) in new[]
{
    ("draussen.", "draußen."),
    ("(Füsse), »draussen«!", "(Füße), »draußen«!"),
    ("draussen\tfüsse\r\naussen", "draußen\tfüße\r\naußen"),
    ("  draussen  füsse\n", "  draußen  füße\n"),
    ("aussenden Fussel Grossist blossom weissagen", "aussenden Fussel Grossist blossom weissagen"),
    ("🦶 Füsse — draussen…", "🦶 Füße — draußen…")
})
{
    string actual = SharpS.Apply(input);
    if (actual != expected) throw new Exception($"German spelling changed word boundaries: {input} => {actual}");
}
if (commands.ProcessDictation("draussen neue Zeile füsse.") != "draußen\nFüße.")
    throw new Exception("Spelling after spoken line-break processing differs.");
Console.WriteLine("PASS: German spelling at punctuation/Unicode/whitespace boundaries and after spoken line breaks; exceptions preserved");

CorpusChecks.Run();
