using System.Text.Json;

namespace Inlaut.App;

internal static class UiText
{
    // Fixed for the process lifetime: changing the preference requires a restart.
    internal static string Language { get; set; } = "de";
    private static readonly IReadOnlyDictionary<string, string> English = Load();
    private static Dictionary<string, string> Load()
    {
        using var stream = typeof(UiText).Assembly.GetManifestResourceStream("Inlaut.App.English.json")!;
        return JsonSerializer.Deserialize<Dictionary<string, string>>(stream)!;
    }
    internal static string Get(string german) => Language == "en" && English.TryGetValue(german, out var value) ? value : german;
    internal static string Format(string german, params object[] values) => string.Format(Get(german), values);
}
