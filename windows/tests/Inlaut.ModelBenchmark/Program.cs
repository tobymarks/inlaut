using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;
using Inlaut.Platform.Windows;

try
{
    if (args.Length is < 3 or > 4) throw new ArgumentException("Usage: ModelBenchmark <model-directory> <corpus-directory> <result.json> [nemo|nemo-tdt|whisper]");
    // Each model runs in a fresh process. The corpus contains expected.json and
    // test-1.wav ... test-N.wav. Never commit recordings or private transcripts.
    var references = JsonSerializer.Deserialize<string[]>(File.ReadAllText(Path.Combine(args[1], "expected.json")))!;
    var clock = Stopwatch.StartNew();
    using var engine = new SherpaEngine(args[0], threads: 4, modelFamily: args.Length == 4 ? args[3] : "nemo");
    long loadMs = clock.ElapsedMilliseconds;
    var results = new List<object>();
    int totalErrors = 0, totalWords = 0;
    for (int i = 0; i < references.Length; i++)
    {
        var (text, audioSec, decodeSec, rtf) = engine.TranscribeFile(Path.Combine(args[1], $"test-{i + 1}.wav"));
        string[] expected = Words(references[i]), actual = Words(text);
        int errors = Distance(expected, actual);
        totalErrors += errors; totalWords += expected.Length;
        results.Add(new { reference = references[i], text, errors, words = expected.Length, audioSec, decodeSec, rtf });
    }
    using var process = Process.GetCurrentProcess();
    process.Refresh();
    var report = new { model = Path.GetFileName(Path.GetFullPath(args[0]).TrimEnd(Path.DirectorySeparatorChar)), loadMs,
        modelBytes = Directory.GetFiles(args[0], "*", SearchOption.AllDirectories).Sum(f => new FileInfo(f).Length),
        peakWorkingSetBytes = process.PeakWorkingSet64, privateBytes = process.PrivateMemorySize64,
        wordErrors = totalErrors, referenceWords = totalWords, wer = totalWords == 0 ? 0 : (double)totalErrors / totalWords,
        normalization = "Unicode lowercase, punctuation removed; no number normalization", configuration = engine.DiagnosticConfiguration, results };
    File.WriteAllText(args[2], JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
    Console.WriteLine($"Completed: {totalErrors}/{totalWords} word errors; peak working set {process.PeakWorkingSet64 / 1048576} MiB");
}
catch (Exception error)
{
    Console.Error.WriteLine(error);
    Environment.ExitCode = 1;
}
static string[] Words(string text) => Regex.Matches(text.Normalize().ToLowerInvariant(), @"[\p{L}\p{M}\p{N}]+").Select(m => m.Value).ToArray();
static int Distance(string[] a, string[] b)
{
    int[] previous = Enumerable.Range(0, b.Length + 1).ToArray();
    for (int i = 1; i <= a.Length; i++)
    {
        int[] current = new int[b.Length + 1]; current[0] = i;
        for (int j = 1; j <= b.Length; j++)
            current[j] = Math.Min(Math.Min(previous[j] + 1, current[j - 1] + 1), previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
        previous = current;
    }
    return previous[b.Length];
}
