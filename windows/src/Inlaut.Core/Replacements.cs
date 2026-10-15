using System.Text.RegularExpressions;

namespace Inlaut.Core;

public record Replacement(string From, string To);

public static class Replacements
{
    public static string Apply(this IEnumerable<Replacement> replacements, string text)
    {
        if (string.IsNullOrEmpty(text)) return text;

        var sorted = replacements.OrderByDescending(r => r.From.Length);
        var result = text;

        foreach (var rule in sorted)
        {
            if (string.IsNullOrWhiteSpace(rule.From)) continue;

            // Whole-word matching ignoring case
            var pattern = $@"(?<![\p{{L}}\p{{N}}]){Regex.Escape(rule.From)}(?![\p{{L}}\p{{N}}])";
            result = Regex.Replace(result, pattern, _ => rule.To ?? "", RegexOptions.IgnoreCase);
        }

        return result;
    }
}
