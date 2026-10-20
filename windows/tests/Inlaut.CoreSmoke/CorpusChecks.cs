#nullable enable
using System.Globalization;
using System.Text.Json;
using Inlaut.Core;

/// Runs TestData/text-pipeline.json, which Tests/TextPipelineCorpusTests.swift
/// runs on the Mac as well, so every difference the cases find between the
/// Windows and Mac text handling is one the file names. Both runners check the
/// file the same way, so a misspelt key cannot quietly turn a case into a weaker one.
static class CorpusChecks
{
    private static readonly HashSet<string> Shared = ["id", "step", "input", "expected", "mac", "windows", "differences"];
    private static readonly Dictionary<string, HashSet<string>> StepKeys = new()
    {
        ["sharpS"] = [],
        ["voiceCommands"] = ["languages"],
        ["dictation"] = ["languages", "voiceCommands", "sharpS", "replacements", "snippets"],
    };

    public static void Run()
    {
        string path = Path.Combine(AppContext.BaseDirectory, "text-pipeline.json");
        using var corpus = JsonDocument.Parse(File.ReadAllText(path));
        var root = corpus.RootElement;
        if (!root.EnumerateObject().Select(p => p.Name).ToHashSet().SetEquals(["about", "differences", "cases"]))
            throw new Exception("The shared text corpus needs exactly about, differences and cases.");
        var differences = root.GetProperty("differences").EnumerateObject().Select(p => p.Name).ToHashSet();
        var cases = root.GetProperty("cases").EnumerateArray().ToArray();
        if (cases.Length == 0) throw new Exception("The shared text corpus is empty.");

        // The text steps must not depend on the Windows culture, Turkish included.
        var culture = CultureInfo.CurrentCulture;
        try
        {
            foreach (var name in new[] { "", "de-DE", "tr-TR" })
            {
                CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = new CultureInfo(name);
                Check(cases, differences);
            }
        }
        finally { CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = culture; }
        Console.WriteLine($"PASS: {cases.Length} shared text cases agree with TestData/text-pipeline.json (invariant, German and Turkish culture)");
    }

    private static void Check(JsonElement[] cases, HashSet<string> differences)
    {
        var ids = new HashSet<string>();
        var used = new HashSet<string>();
        var failures = new List<string>();

        foreach (var item in cases)
        {
            string id = Text(item, "id") ?? throw new Exception("A corpus case has no id.");
            if (!ids.Add(id)) throw new Exception($"{id}: id is not unique");
            string step = Text(item, "step") ?? "dictation";
            if (!StepKeys.TryGetValue(step, out var keys)) throw new Exception($"{id}: unknown step {step}");
            var extra = item.EnumerateObject().Select(p => p.Name).Where(k => !Shared.Contains(k) && !keys.Contains(k)).ToArray();
            if (extra.Length > 0) throw new Exception($"{id}: {string.Join(", ", extra)} do not belong to step {step}");
            if (step != "sharpS" && !item.TryGetProperty("languages", out _)) throw new Exception($"{id}: needs languages");

            string expected;
            if (Text(item, "expected") is { } both)
            {
                if (item.TryGetProperty("mac", out _) || item.TryGetProperty("windows", out _) || item.TryGetProperty("differences", out _))
                    throw new Exception($"{id}: expected holds on both platforms, so it needs no mac, windows or differences");
                expected = both;
            }
            else
            {
                string? mac = Text(item, "mac"), windows = Text(item, "windows");
                string[] named = item.TryGetProperty("differences", out var list) ? list.EnumerateArray().Select(d => d.GetString()!).ToArray() : [];
                if (mac == null || windows == null || named.Length == 0)
                    throw new Exception($"{id}: needs expected, or mac, windows and differences");
                if (mac == windows) throw new Exception($"{id}: mac and windows agree, so this is expected");
                foreach (var key in named)
                    if (!differences.Contains(key)) throw new Exception($"{id}: unknown difference {key}");
                used.UnionWith(named);
                expected = windows;
            }

            string actual = Process(id, step, item);
            if (actual != expected)
                failures.Add($"{id}: expected {JsonSerializer.Serialize(expected)}, got {JsonSerializer.Serialize(actual)}");
        }

        if (!used.SetEquals(differences))
            throw new Exception("Every named difference needs a case: " + string.Join(", ", differences.Except(used)));
        if (failures.Count > 0)
            throw new Exception($"Shared text corpus failed ({CultureInfo.CurrentCulture.Name}):\n" + string.Join("\n", failures));
    }

    private static string Process(string id, string step, JsonElement item)
    {
        string input = Text(item, "input") ?? throw new Exception($"{id}: needs input");
        var languages = item.TryGetProperty("languages", out var list)
            ? list.EnumerateArray().Select(l => l.GetString() switch
            {
                "german" => SpokenLanguage.German,
                "english" => SpokenLanguage.English,
                var other => throw new Exception($"{id}: unknown language {other}")
            }).ToHashSet()
            : [];

        switch (step)
        {
            case "sharpS":
                return SharpS.Apply(input);
            case "voiceCommands":
                return VoiceCommands.Apply(input, languages);
            default:
                var pipeline = new TextPipeline
                {
                    Languages = languages,
                    VoiceCommandsEnabled = Flag(id, item, "voiceCommands"),
                    SharpSEnabled = Flag(id, item, "sharpS"),
                    ReplacementsList = Rules(id, item, "replacements", "from", "to").Select(r => new Replacement(r[0], r[1])).ToList(),
                    Snippets = Rules(id, item, "snippets", "phrase", "text").Select(s => new Snippet(s[0], s[1])).ToList(),
                };
                return pipeline.ProcessDictation(input);
        }
    }

    private static string? Text(JsonElement item, string name) =>
        item.TryGetProperty(name, out var value) ? value.GetString() : null;

    private static bool Flag(string id, JsonElement item, string name)
    {
        if (!item.TryGetProperty(name, out var value)) return true;
        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => throw new Exception($"{id}: {name} is true or false")
        };
    }

    private static IEnumerable<string[]> Rules(string id, JsonElement item, string name, string first, string second)
    {
        if (!item.TryGetProperty(name, out var list)) return [];
        return list.EnumerateArray().Select(rule =>
        {
            if (!rule.EnumerateObject().Select(p => p.Name).ToHashSet().SetEquals([first, second]))
                throw new Exception($"{id}: a rule has exactly {first} and {second}");
            return new[] { Text(rule, first)!, Text(rule, second)! };
        }).ToList();
    }
}
