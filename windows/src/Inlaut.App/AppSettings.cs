using System.Text.Json;

namespace Inlaut.App;

public class AppSettings
{
    // Default to Left Control (VK_LCONTROL = 0xA2), which is right next to Fn on MacBooks
    public uint TriggerVkCode { get; set; } = 0xA2;
    public string TriggerKeyName { get; set; } = "Linke Strg-Taste";
    public int HoldDelayMs { get; set; } = 220;
    public int DoubleTapWindowMs { get; set; } = 400;
    public bool UseClipboardInsertion { get; set; } = false;
    public bool VoiceCommands { get; set; } = true;
    public bool SharpS { get; set; } = true;
    public string MicrophoneId { get; set; } = "";
    public bool PlaySounds { get; set; }
    public bool LaunchAtLogin { get; set; }
    public bool AutomaticUpdates { get; set; }
    public bool UpdateConsentAsked { get; set; }
    public bool BetaUpdates { get; set; } = LocalDiagnostics.Version.Split('+')[0].Contains('-');
    public string IndicatorPosition { get; set; } = "bottom";
    public string TriggerMode { get; set; } = "combined";
    public List<Inlaut.Core.Replacement> Replacements { get; set; } = [];
    public List<Inlaut.Core.Snippet> Snippets { get; set; } = [];
    public static string? LoadWarning { get; private set; }

    private static readonly string SettingsFilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "inlaut",
        "settings.json"
    );

    public static AppSettings Load(string? path = null)
    {
        LoadWarning = null;
        try
        {
            if (File.Exists(path ?? SettingsFilePath))
            {
                string json = File.ReadAllText(path ?? SettingsFilePath);
                var settings = JsonSerializer.Deserialize<AppSettings>(json);
                if (settings != null) { settings.Validate(); return settings; }
            }
        }
        catch
        {
            LoadWarning = "Einstellungen konnten nicht geladen werden. Die vorhandene Datei bleibt erhalten; vorläufig gelten Standardwerte.";
        }

        var defaultSettings = new AppSettings();
        return defaultSettings;
    }

    public void Save(string? path = null)
    {
        Validate();
        string target = path ?? SettingsFilePath;
        string temporary = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            string dir = Path.GetDirectoryName(Path.GetFullPath(target))!;
            Directory.CreateDirectory(dir);

            string json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(temporary, json);
            File.Move(temporary, target, true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public AppSettings Clone() => JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(this))!;
    public void CopyFrom(AppSettings other)
    {
        foreach (var property in typeof(AppSettings).GetProperties().Where(p => p.CanWrite && p.SetMethod?.IsPublic == true && p.GetMethod?.IsStatic == false))
            property.SetValue(this, property.GetValue(other));
    }
    public void Validate()
    {
        if (MicrophoneId == null || TriggerKeyName == null || TriggerMode is not ("combined" or "hold" or "toggle") || IndicatorPosition is not ("bottom" or "top") ||
            TriggerVkCode > 255 || HoldDelayMs < 100 || HoldDelayMs > 2000 || DoubleTapWindowMs < 100 || DoubleTapWindowMs > 1500)
            throw new ArgumentException("Ungültige Einstellungen.");
        new Inlaut.Core.TextRules { Replacements = Replacements, Snippets = Snippets }.Validate();
    }
    public void ApplyTo(Inlaut.Core.TextPipeline pipeline)
    {
        pipeline.VoiceCommandsEnabled = VoiceCommands;
        pipeline.SharpSEnabled = SharpS;
        pipeline.ReplacementsList = Replacements.ToList();
        pipeline.Snippets = Snippets.ToList();
    }

    public static string GetFriendlyKeyName(uint vkCode)
    {
        return vkCode switch
        {
            0xA2 => "Strg links",
            0xA3 => "Strg rechts",
            0x11 => "Strg",
            0x14 => "Caps Lock",
            0x12 => "Alt-Taste",
            0xA4 => "Alt links",
            0xA5 => "Alt rechts",
            0x5B => "Windows links",
            0x5C => "Windows rechts",
            0xC0 => "^ (Zirkumflex / Tilde)",
            0xDC => "^ / ° (Dach-Taste)",
            0x20 => "Leertaste",
            0x09 => "Tabulator",
            0x1B => "Escape",
            0x2D => "Einfügen",
            0x24 => "Pos 1",
            0x23 => "Ende",
            0x21 => "Bild auf",
            0x22 => "Bild ab",
            0x90 => "Num Lock",
            0x91 => "Rollen (Scroll Lock)",
            0x13 => "Pause",
            >= 0x70 and <= 0x87 => $"F{vkCode - 0x70 + 1}",
            >= 0x41 and <= 0x5A => $"Buchstabe '{(char)vkCode}'",
            >= 0x30 and <= 0x39 => $"Ziffer '{(char)vkCode}'",
            _ => $"Taste (Code {vkCode} / 0x{vkCode:X2})"
        };
    }
}
