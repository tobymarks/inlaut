using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;

namespace Inlaut.App;

public static class ModelManager
{
    public sealed record ModelFile(string Name, long Size, string Sha256);
    public sealed record Model(string Language, string Directory, string? BaseUrl, ModelFile[] Files);
    private static readonly Model[] Models = LoadCatalog();
    private static Model[] LoadCatalog()
    {
        using var stream = typeof(ModelManager).Assembly.GetManifestResourceStream("Inlaut.App.models.json")!;
        return JsonSerializer.Deserialize<Model[]>(stream, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
    }
    public static Model ForLanguage(string language) => Models.Single(m => m.Language == language);

    public static string GetModelDirectory(string language = "de") => ResolveDirectory(language,
        Path.Combine(AppContext.BaseDirectory, "models"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "inlaut", "models"));

    internal static string ResolveDirectory(string language, string bundledRoot, string userRoot)
    {
        var model = ForLanguage(language);
        // Never select an arbitrary directory: a different language has the same filenames.
        var candidates = new List<string> { Path.Combine(bundledRoot, model.Directory), Path.Combine(userRoot, model.Directory) };
        if (language == "de") candidates.AddRange([bundledRoot, Path.Combine(userRoot, "fastconformer-de-transducer"), userRoot]);
        return candidates.FirstOrDefault(p => HasValidModel(p, language)) ?? candidates[0];
    }

    public static bool HasValidModel(string directory, string language = "de") => ForLanguage(language).Files.All(f =>
        File.Exists(Path.Combine(directory, f.Name)) && new FileInfo(Path.Combine(directory, f.Name)).Length == f.Size);

    public static void VerifyModel(string directory, string language)
    {
        foreach (var file in ForLanguage(language).Files)
        {
            using var stream = File.OpenRead(Path.Combine(directory, file.Name));
            if (stream.Length != file.Size || !Convert.ToHexString(SHA256.HashData(stream)).Equals(file.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException(UiText.Get("Sprachmodell beschädigt. Bitte inlaut erneut installieren."));
        }
    }

    public static async Task<string> EnsureModelAvailableAsync(Action<string, int>? progressCallback = null, string language = "de")
    {
        var model = ForLanguage(language);
        string existing = GetModelDirectory(language);
        if (HasValidModel(existing, language)) return existing;
        // Both languages ship in the installer. English has no unverified download fallback.
        if (model.BaseUrl == null) throw new FileNotFoundException(UiText.Get("Englisches Sprachmodell fehlt. Bitte den aktuellen zweisprachigen Installer verwenden."));
        string target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "inlaut", "models", model.Directory);
        Directory.CreateDirectory(target);
        using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        long total = model.Files.Sum(f => f.Size), done = 0;
        foreach (var file in model.Files)
        {
            string destination = Path.Combine(target, file.Name), temporary = destination + ".tmp";
            try
            {
                using var response = await client.GetAsync(model.BaseUrl + file.Name, HttpCompletionOption.ResponseHeadersRead);
                response.EnsureSuccessStatusCode();
                await using (var input = await response.Content.ReadAsStreamAsync())
                await using (var output = File.Create(temporary))
                {
                    var buffer = new byte[81920]; long received = 0; int count;
                    while ((count = await input.ReadAsync(buffer)) > 0)
                    {
                        received += count;
                        if (received > file.Size) throw new InvalidDataException("Unexpected model size");
                        await output.WriteAsync(buffer.AsMemory(0, count));
                        progressCallback?.Invoke(UiText.Get("Sprachmodell wird geladen…"), (int)((done + received) * 100 / total));
                    }
                }
                using (var stream = File.OpenRead(temporary))
                    if (stream.Length != file.Size || !Convert.ToHexString(SHA256.HashData(stream)).Equals(file.Sha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Model checksum mismatch");
                File.Move(temporary, destination, true); done += file.Size;
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        return target;
    }
}
