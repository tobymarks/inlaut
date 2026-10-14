using System.Text.RegularExpressions;

namespace Inlaut.Core;

public class TextPipeline
{
    public HashSet<SpokenLanguage> Languages { get; set; } = [SpokenLanguage.German, SpokenLanguage.English];
    public bool VoiceCommandsEnabled { get; set; } = true;
    public bool SharpSEnabled { get; set; } = true;
    public List<Replacement> ReplacementsList { get; set; } = [];

    public string ProcessDictation(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "";

        string text = raw;

        // 1. Sanitize transducer/decoder silence artifacts (e.g. repeated "???", "....", "eeee")
        text = SanitizeArtifacts(text);

        if (VoiceCommandsEnabled)
        {
            text = VoiceCommands.Apply(text, Languages);
        }

        if (SharpSEnabled && Languages.Contains(SpokenLanguage.German))
        {
            text = SharpS.Apply(text);
        }

        if (ReplacementsList.Count > 0)
        {
            text = ReplacementsList.Apply(text);
        }

        return text.Trim();
    }

    public static string SanitizeArtifacts(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return "";

        // Collapse repeated punctuation: "?????" -> "?", "....." -> "."
        text = Regex.Replace(text, @"([\?\!\.\,\;\:\-])\1+", "$1");

        // Collapse 3 or more repeated letters/characters: "eeeeeee" -> "ee"
        text = Regex.Replace(text, @"(.)\1{2,}", "$1$1");

        // Clean up spaces before punctuation: "Jetzt ," -> "Jetzt,"
        text = Regex.Replace(text, @"\s+([\?\!\.\,\;\:])", "$1");

        return text;
    }
}
