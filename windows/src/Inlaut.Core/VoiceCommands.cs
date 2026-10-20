using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Inlaut.Core;

public enum SpokenLanguage
{
    German,
    English
}

/// Spoken layout commands: "neue Zeile" / "new line" → line break,
/// "neuer Absatz" / "new paragraph" → blank line. The recogniser writes
/// them as words with commas around ("Hallo Frau Becker, neuer Absatz,
/// vielen Dank …"), so the punctuation next to each command is tidied as well.
/// Mirrors Sources/VoiceCommands.swift; TestData/text-pipeline.json runs
/// shared cases from both test runners.
public static class VoiceCommands
{
    private static readonly Dictionary<SpokenLanguage, string> Patterns = new()
    {
        [SpokenLanguage.German] = @"neue[rn]?\s+absatz|neue\s+zeile",
        [SpokenLanguage.English] = @"new\s+paragraph|new\s+line",
    };

    // Lines this short are salutations or sign-offs ("Hallo Frau Becker,",
    // "Viele Grüße,", "Tobias Marks"), which keep their comma or get no period.
    private const int ShortLine = 4;

    public static string Apply(string text, HashSet<SpokenLanguage> languages)
    {
        var alternatives = Patterns.Where(p => languages.Contains(p.Key)).Select(p => p.Value).Order(StringComparer.Ordinal).ToArray();
        if (alternatives.Length == 0 || string.IsNullOrEmpty(text)) return text;
        // Only the dictated languages: a command of another language must not
        // take the punctuation in front of a real one.
        var matches = Regex.Matches(text, @"([\s,;:.!?]*)\b(" + string.Join("|", alternatives) + @")\b[\s,;:.!?]*",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (matches.Count == 0) return text;

        var result = new StringBuilder();
        int cursor = 0;
        foreach (Match match in matches)
        {
            result.Append(Finish(text[cursor..match.Index], match.Groups[1].Value, capitalize: cursor > 0));
            string spoken = match.Groups[2].Value.ToLowerInvariant();
            result.Append(spoken.Contains("absatz") || spoken.Contains("paragraph") ? "\n\n" : "\n");
            cursor = match.Index + match.Length;
        }
        string last = Capitalize(TrimSpaces(text[cursor..]));
        // A signature ("Tobias.") gets no full stop; an ellipsis stays whole.
        if (WordCount(last) <= ShortLine && last.EndsWith('.') && !last.EndsWith("..", StringComparison.Ordinal)) last = last[..^1];
        result.Append(last);

        var output = result.ToString();
        // Two commands in a row must not stack up more than one blank line.
        while (output.Contains("\n\n\n")) output = output.Replace("\n\n\n", "\n\n");
        // Line breaks at either end stay: a command at the start or end of a
        // dictation applies next to the cursor (#20).
        return output.Trim(' ', '\t', '\r');
    }

    private static string Finish(string raw, string punctuationBefore, bool capitalize)
    {
        var line = TrimSpaces(raw);
        if (line.Length == 0) return "";
        if (capitalize) line = Capitalize(line);
        if (".!?:;,".Contains(line[^1])) return line;
        int spoken = punctuationBefore.IndexOfAny(['.', '!', '?', ':']);
        if (spoken >= 0)
        {
            // Parakeet Ultra ends "Best regards" / "Hallo Frau Becker" with a
            // full stop; as a salutation or sign-off it takes a comma.
            if (punctuationBefore[spoken] == '.' && WordCount(line) <= ShortLine) return line + ",";
            return line + punctuationBefore[spoken];
        }
        // The recogniser put a comma: keep it after a salutation, otherwise
        // the line was a sentence.
        if (punctuationBefore.Contains(','))
            return line + (WordCount(line) <= ShortLine ? "," : ".");
        return line;
    }

    // Spaces and tabs, as Swift's CharacterSet.whitespaces; line breaks stay.
    private static string TrimSpaces(string text)
    {
        int start = 0, end = text.Length;
        while (start < end && IsSpace(text[start])) start++;
        while (end > start && IsSpace(text[end - 1])) end--;
        return text[start..end];
    }

    private static bool IsSpace(char c) => c == '\t' || char.GetUnicodeCategory(c) == UnicodeCategory.SpaceSeparator;

    private static string Capitalize(string line)
    {
        if (line.Length == 0) return line;
        int first = StringInfo.GetNextTextElementLength(line);
        return line[..first].ToUpperInvariant() + line[first..];
    }

    private static int WordCount(string line) =>
        line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
}
