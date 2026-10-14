using System.Text.Json;
using System.Text.RegularExpressions;

namespace Inlaut.Core;

public sealed record ReleaseVersion(int Major, int Minor, int Patch, string[] Pre) : IComparable<ReleaseVersion>
{
    public static ReleaseVersion Parse(string value)
    {
        var m = Regex.Match(value ?? "", @"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$", RegexOptions.CultureInvariant);
        if (!m.Success || value!.Length > 80) throw new FormatException("Ungültige Versionsnummer.");
        var pre = m.Groups[4].Success ? m.Groups[4].Value.Split('.') : [];
        if (pre.Any(s => s.All(char.IsAsciiDigit) && s.Length > 1 && s[0] == '0')) throw new FormatException("Ungültige Vorabversion.");
        return new(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value), int.Parse(m.Groups[3].Value), pre);
    }
    public int CompareTo(ReleaseVersion? other)
    {
        if (other == null) return 1;
        foreach (var pair in new[] { (Major, other.Major), (Minor, other.Minor), (Patch, other.Patch) })
            if (pair.Item1 != pair.Item2) return pair.Item1.CompareTo(pair.Item2);
        if (Pre.Length == 0 || other.Pre.Length == 0) return (Pre.Length == 0 ? 1 : 0).CompareTo(other.Pre.Length == 0 ? 1 : 0);
        for (int i = 0; i < Math.Min(Pre.Length, other.Pre.Length); i++)
        {
            var a = Pre[i]; var b = other.Pre[i]; bool an = a.All(char.IsAsciiDigit), bn = b.All(char.IsAsciiDigit);
            int c = an && bn ? (a.Length != b.Length ? a.Length.CompareTo(b.Length) : string.CompareOrdinal(a, b)) : an != bn ? (an ? -1 : 1) : string.CompareOrdinal(a, b);
            if (c != 0) return c;
        }
        return Pre.Length.CompareTo(other.Pre.Length);
    }
}

public sealed record UpdateManifest(int Schema, string Version, string Url, string Sha256, long Size)
{
    public const long MaxBytes = 600L * 1024 * 1024;
    public static UpdateManifest Parse(string json)
    {
        if (json.Length > 16384) throw new FormatException("Update-Information zu groß.");
        var result = JsonSerializer.Deserialize<UpdateManifest>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? throw new FormatException("Leere Update-Information.");
        result.Validate(); return result;
    }
    public void Validate()
    {
        _ = ReleaseVersion.Parse(Version);
        if (Schema != 1 || Size <= 0 || Size > MaxBytes || !Regex.IsMatch(Sha256 ?? "", "^[a-fA-F0-9]{64}$")) throw new FormatException("Ungültige Update-Information.");
        if (!Uri.TryCreate(Url, UriKind.Absolute, out var uri) || uri.Scheme != "https" || uri.Host != "github.com" || !uri.IsDefaultPort || uri.UserInfo != "" || uri.Query != "" || uri.Fragment != "" ||
            !uri.AbsolutePath.StartsWith("/tobymarks/inlaut/releases/download/", StringComparison.Ordinal) ||
            Path.GetFileName(uri.AbsolutePath) != $"inlaut-{Version}-windows-x64-setup.exe") throw new FormatException("Unzulässige Update-Adresse.");
    }
    public bool IsNewer(string current, bool beta) => ReleaseVersion.Parse(Version).CompareTo(ReleaseVersion.Parse(current)) > 0 && (beta || ReleaseVersion.Parse(Version).Pre.Length == 0);
}
