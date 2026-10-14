namespace Inlaut.Core;

public class TextPipeline
{
    public HashSet<SpokenLanguage> Languages { get; set; } = [SpokenLanguage.German, SpokenLanguage.English];
    public bool VoiceCommandsEnabled { get; set; } = true;
    public bool SharpSEnabled { get; set; } = true;
    public List<Replacement> ReplacementsList { get; set; } = [];
    public List<Snippet> Snippets { get; set; } = [];

    public string ProcessDictation(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "";
        string key = Snippet.Key(raw);
        var snippet = key.Length == 0 ? null : Snippets.FirstOrDefault(s => Snippet.Key(s.Phrase) == key);
        if (snippet != null) return snippet.Text; // Exact literal payload, including whitespace.

        string text = raw;

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

}
