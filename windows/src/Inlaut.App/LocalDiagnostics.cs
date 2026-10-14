using System.Reflection;
using System.Text.Json;

namespace Inlaut.App;

// Metadata only: never write audio, dictated text or exception messages here.
internal static class LocalDiagnostics
{
    private static readonly object Gate = new();
    public static string Version => typeof(Program).Assembly
        .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "unknown";
    public static string DirectoryPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "inlaut", "diagnostics");

    public static void Write(string stage, object metrics)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(DirectoryPath);
                string path = Path.Combine(DirectoryPath, "latest.jsonl");
                if (File.Exists(path) && new FileInfo(path).Length > 1_000_000)
                    File.Move(path, Path.Combine(DirectoryPath, "previous.jsonl"), true);
                File.AppendAllText(path, JsonSerializer.Serialize(new
                {
                    time = DateTimeOffset.UtcNow, version = Version, stage, metrics
                }) + Environment.NewLine);
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    public static object DescribeText(string text)
    {
        int longestPunctuationRun = 0, run = 0;
        foreach (char c in text)
        {
            if (char.IsPunctuation(c) || char.IsSymbol(c))
                longestPunctuationRun = Math.Max(longestPunctuationRun, ++run);
            else if (!char.IsWhiteSpace(c))
                run = 0;
        }
        return new { characters = text.Length, letters = text.Count(char.IsLetter), longestPunctuationRun };
    }

    public static object DescribeAudio(float[] samples)
    {
        double sum = 0;
        float peak = 0;
        int clipped = 0;
        foreach (float sample in samples)
        {
            sum += (double)sample * sample;
            peak = Math.Max(peak, Math.Abs(sample));
            if (Math.Abs(sample) >= 0.999f) clipped++;
        }
        return new
        {
            seconds = samples.Length / 16000.0, peak,
            rms = samples.Length == 0 ? 0 : Math.Sqrt(sum / samples.Length), clipped
        };
    }
}
