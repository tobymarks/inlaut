using System.Text.RegularExpressions;

namespace Inlaut.Core;

public enum SpokenLanguage
{
    German,
    English
}

public static class VoiceCommands
{
    private static readonly Regex CommandRegex = new(
        @"([\s,;:.!?]*)\b(neue[rn]?\s+absatz|neue\s+zeile|new\s+paragraph|new\s+line)\b[\s,;:.!?]*",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static string Apply(string text, HashSet<SpokenLanguage> languages)
    {
        if (string.IsNullOrEmpty(text) || languages.Count == 0) return text;

        var matches = CommandRegex.Matches(text);
        if (matches.Count == 0) return text;

        var outText = new System.Text.StringBuilder();
        int cursor = 0;

        foreach (Match match in matches)
        {
            string line = text[cursor..match.Index];
            string before = match.Groups[1].Value;
            outText.Append(FinishLine(line, before, capitalize: cursor > 0));

            string spoken = match.Groups[2].Value.ToLowerInvariant();
            bool isParagraph = spoken.Contains("absatz") || spoken.Contains("paragraph");
            outText.Append(isParagraph ? "\n\n" : "\n");

            cursor = match.Index + match.Length;
        }

        string last = Capitalize(text[cursor..].Trim());
        outText.Append(last);

        var result = outText.ToString();
        while (result.Contains("\n\n\n"))
        {
            result = result.Replace("\n\n\n", "\n\n");
        }
        // Edge breaks can be intentional commands in a subsequent dictation.
        return result.Trim(' ', '\t', '\r');
    }

    private static string FinishLine(string raw, string punctuationBefore, bool capitalize)
    {
        var line = raw.Trim();
        if (string.IsNullOrEmpty(line)) return "";
        if (capitalize) line = Capitalize(line);

        char last = line[^1];
        if (".!?:;,".Contains(last)) return line;
        string explicitPunctuation = punctuationBefore.Trim();
        if (explicitPunctuation.Length > 0) return line + explicitPunctuation;

        // If line is short (salutation/closing like 'Viele Grüße'), keep comma
        if (WordCount(line) <= 4)
        {
            return punctuationBefore.Contains(',') ? line + "," : line;
        }

        return line + (punctuationBefore.Contains('?') ? "?" : ".");
    }

    private static string Capitalize(string s)
    {
        if (string.IsNullOrEmpty(s)) return s;
        if (s.Length == 1) return char.ToUpperInvariant(s[0]).ToString();
        return char.ToUpperInvariant(s[0]) + s[1..];
    }

    private static int WordCount(string s) =>
        s.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
}
