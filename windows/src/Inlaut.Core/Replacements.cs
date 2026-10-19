using System.Text.RegularExpressions;

namespace Inlaut.Core;

public record Replacement(string From, string To);

public static class Replacements
{
    // The Mac matches with ICU's case folding, where ß, ẞ and ss are the same.
    // Without that, "Strasse → Str." stops working once the ß step has
    // written "Straße", and a rules file behaves differently on each platform.
    private static readonly Regex SharpSOrDoubleS = new("ss|ß|ẞ", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public static string Apply(this IEnumerable<Replacement> replacements, string text)
    {
        if (string.IsNullOrEmpty(text)) return text;

        var sorted = replacements.OrderByDescending(r => r.From.Length);
        var result = text;

        foreach (var rule in sorted)
        {
            if (string.IsNullOrWhiteSpace(rule.From)) continue;

            // Whole-word matching ignoring case, the same in every Windows culture
            // (a Turkish one would otherwise not match "GITLAB" with "Gitlab").
            var word = SharpSOrDoubleS.Replace(Regex.Escape(rule.From), "(?:ss|ß|ẞ)");
            var pattern = $@"(?<![\p{{L}}\p{{N}}]){word}(?![\p{{L}}\p{{N}}])";
            result = Regex.Replace(result, pattern, _ => rule.To ?? "", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }

        return result;
    }
}
