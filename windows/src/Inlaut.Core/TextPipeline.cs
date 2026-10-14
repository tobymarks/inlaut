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

        return text;
    }
}
