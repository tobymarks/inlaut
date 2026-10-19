using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Inlaut.Core;

public record Snippet(string Phrase, string Text)
{
    // Composed first, as the Mac compares canonically equivalent text as equal.
    public static string Key(string text) => string.Join(" ", Regex.Matches(text.Normalize(NormalizationForm.FormC).ToLowerInvariant().Replace("ß", "ss"), @"[\p{L}\p{N}]+")
        .Select(m => m.Value));
}

// Same lower-camel-case file schema as the macOS TextRulesFile.
public sealed class TextRules
{
    public List<Replacement> Replacements { get; set; } = [];
    public List<Snippet> Snippets { get; set; } = [];
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true };
    public string Export() { Validate(); return JsonSerializer.Serialize(this, Json); }
    public static TextRules Import(string json)
    {
        if (json.Length > 2_000_000) throw new ArgumentException("Die Datei ist zu groß (maximal 2 MB).");
        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind != JsonValueKind.Object ||
            (!doc.RootElement.TryGetProperty("replacements", out _) && !doc.RootElement.TryGetProperty("snippets", out _)))
            throw new ArgumentException("Keine Ersetzungen oder Textbausteine in dieser Datei.");
        var rules = JsonSerializer.Deserialize<TextRules>(json, Json) ?? throw new ArgumentException("Leere Regeldatei.");
        rules.Validate();
        return rules;
    }
    public void Validate()
    {
        if (Replacements == null || Snippets == null || Replacements.Count + Snippets.Count > 1000)
            throw new ArgumentException("Maximal 1000 Regeln sind erlaubt.");
        var words = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rule in Replacements)
            if (rule == null || string.IsNullOrWhiteSpace(rule.From) || rule.To == null || rule.From.Length > 500 || rule.To.Length > 50000 || !words.Add(rule.From.Trim()))
                throw new ArgumentException("Ersetzungen brauchen eindeutige Ausgangswörter (maximal 500 Zeichen).");
        words.Clear();
        foreach (var snippet in Snippets)
            if (snippet == null || string.IsNullOrWhiteSpace(snippet.Phrase) || string.IsNullOrWhiteSpace(snippet.Text) || snippet.Phrase.Length > 500 || snippet.Text.Length > 50000 ||
                Snippet.Key(snippet.Phrase).Length == 0 || !words.Add(Snippet.Key(snippet.Phrase)))
                throw new ArgumentException("Textbausteine brauchen eindeutige Sprechphrasen und einen Text (maximal 50000 Zeichen).");
    }
    public void Merge(TextRules incoming)
    {
        incoming.Validate();
        var replacements = Replacements.ToList();
        var snippets = Snippets.ToList();
        foreach (var item in incoming.Replacements)
        {
            replacements.RemoveAll(r => string.Equals(r.From.Trim(), item.From.Trim(), StringComparison.OrdinalIgnoreCase));
            replacements.Add(item);
        }
        foreach (var item in incoming.Snippets)
        {
            snippets.RemoveAll(s => Snippet.Key(s.Phrase) == Snippet.Key(item.Phrase));
            snippets.Add(item);
        }
        var merged = new TextRules { Replacements = replacements, Snippets = snippets };
        merged.Validate();
        Replacements = merged.Replacements; Snippets = merged.Snippets;
    }
}
