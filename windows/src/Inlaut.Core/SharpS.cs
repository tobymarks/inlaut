using System.Text.RegularExpressions;

namespace Inlaut.Core;

public static class SharpS
{
    private enum Anchor { Anywhere, Start, StartOrEnd, Word }

    private sealed class Rule
    {
        public string Key { get; }
        public int SharpSIndex { get; }
        public Anchor AnchorType { get; }
        public string[] Unless { get; }

        public Rule(string spelled, Anchor anchor = Anchor.Anywhere, string[]? unless = null)
        {
            SharpSIndex = spelled.IndexOf('ß');
            Key = spelled.Replace("ß", "ss");
            AnchorType = anchor;
            Unless = unless ?? Array.Empty<string>();
        }
    }

    private static readonly Rule[] Rules =
    [
        new("groß", unless: ["grossist"]),
        new("größ"),
        new("bloß", unless: ["blossom"]),
        new("heiß"),
        new("süß"),
        new("fleiß"),
        new("gemäß"),
        new("mäßig"),
        new("weiß", Anchor.StartOrEnd, unless: ["weissag"]),
        new("schweiß"),
        new("außen", Anchor.Start, unless: ["aussende", "aussendung", "aussenk"]),
        new("außer", Anchor.Start),
        new("draußen", Anchor.Word),
        new("äuß"),
        new("straße"),
        new("fuß", unless: ["fussel"]),
        new("füße", Anchor.Word),
        new("gruß"),
        new("grüß")
    ];

    public static string Apply(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;

        var words = text.Split(' ');
        for (int i = 0; i < words.Length; i++)
        {
            words[i] = ReplaceWord(words[i]);
        }
        return string.Join(" ", words);
    }

    private static string ReplaceWord(string word)
    {
        var lower = word.ToLowerInvariant();
        foreach (var rule in Rules)
        {
            if (rule.Unless.Any(u => lower.Contains(u))) continue;

            int idx = lower.IndexOf(rule.Key, StringComparison.Ordinal);
            if (idx >= 0)
            {
                bool matchesAnchor = rule.AnchorType switch
                {
                    Anchor.Anywhere => true,
                    Anchor.Start => idx == 0,
                    Anchor.Word => idx == 0 && lower.Length == rule.Key.Length,
                    Anchor.StartOrEnd => idx == 0 || idx + rule.Key.Length == lower.Length,
                    _ => true
                };

                if (matchesAnchor)
                {
                    int ssPos = idx + rule.SharpSIndex;
                    if (ssPos + 1 < word.Length && (word[ssPos] == 's' || word[ssPos] == 'S'))
                    {
                        var chars = word.ToCharArray();
                        chars[ssPos] = 'ß';
                        var remainder = word[(ssPos + 2)..];
                        return new string(chars[..(ssPos + 1)]) + remainder;
                    }
                }
            }
        }
        return word;
    }
}
