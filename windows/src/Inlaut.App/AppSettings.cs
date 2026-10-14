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

    private static readonly string SettingsFilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "inlaut",
        "settings.json"
    );

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsFilePath))
            {
                string json = File.ReadAllText(SettingsFilePath);
                var settings = JsonSerializer.Deserialize<AppSettings>(json);
                if (settings != null) return settings;
            }
        }
        catch
        {
            // Ignore and use defaults
        }

        var defaultSettings = new AppSettings();
        defaultSettings.Save();
        return defaultSettings;
    }

    public void Save()
    {
        try
        {
            string dir = Path.GetDirectoryName(SettingsFilePath)!;
            Directory.CreateDirectory(dir);

            string json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(SettingsFilePath, json);
        }
        catch
        {
            // Best effort
        }
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
            >= 0x70 and <= 0x7B => $"F{vkCode - 0x70 + 1}",
            >= 0x80 and <= 0x87 => $"F{vkCode - 0x80 + 17}",
            >= 0x41 and <= 0x5A => $"Buchstabe '{(char)vkCode}'",
            >= 0x30 and <= 0x39 => $"Ziffer '{(char)vkCode}'",
            _ => $"Taste (Code {vkCode} / 0x{vkCode:X2})"
        };
    }
}
