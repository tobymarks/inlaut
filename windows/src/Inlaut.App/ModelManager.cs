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

    public static async Task<string> EnsureModelAvailableAsync(Action<string, int>? progressCallback = null, string language = "de",
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var model = ForLanguage(language);
        string existing = GetModelDirectory(language);
        if (HasValidModel(existing, language)) return existing;
        // Both languages ship in the installer. English has no unverified download fallback.
        if (model.BaseUrl == null) throw new FileNotFoundException(UiText.Get("Englisches Sprachmodell fehlt. Bitte den aktuellen zweisprachigen Installer verwenden."));
        string target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "inlaut", "models", model.Directory);
        using var client = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        await DownloadModelAsync(client, model, target, progressCallback, cancellationToken);
        return target;
    }

    internal static async Task DownloadModelAsync(HttpClient client, Model model, string target,
        Action<string, int>? progressCallback = null, CancellationToken cancellationToken = default, TimeSpan? timeout = null)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(timeout ?? TimeSpan.FromMinutes(10));
        var token = deadline.Token;
        Directory.CreateDirectory(target);
        long total = model.Files.Sum(f => f.Size), done = 0;
        try
        {
            foreach (var file in model.Files)
            {
                token.ThrowIfCancellationRequested();
                string destination = Path.Combine(target, file.Name), temporary = destination + ".tmp";
                try
                {
                    using var response = await client.GetAsync(model.BaseUrl + file.Name, HttpCompletionOption.ResponseHeadersRead, token);
                    response.EnsureSuccessStatusCode();
                    await using (var input = await response.Content.ReadAsStreamAsync(token))
                    await using (var output = File.Create(temporary))
                    {
                        var buffer = new byte[81920]; long received = 0; int count;
                        while ((count = await input.ReadAsync(buffer.AsMemory(), token)) > 0)
                        {
                            received += count;
                            if (received > file.Size) throw new InvalidDataException("Unexpected model size");
                            await output.WriteAsync(buffer.AsMemory(0, count), token);
                            progressCallback?.Invoke(UiText.Get("Sprachmodell wird geladen…"), (int)((done + received) * 100 / total));
                        }
                    }
                    using (var stream = File.OpenRead(temporary))
                        if (stream.Length != file.Size || !Convert.ToHexString(await SHA256.HashDataAsync(stream, token)).Equals(file.Sha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Model checksum mismatch");
                    token.ThrowIfCancellationRequested();
                    File.Move(temporary, destination, true); done += file.Size;
                }
                finally { if (File.Exists(temporary)) File.Delete(temporary); }
            }
        }
        catch (OperationCanceledException error) when (!cancellationToken.IsCancellationRequested && deadline.IsCancellationRequested)
        {
            throw new TimeoutException(UiText.Get("Der Download des Sprachmodells hat zu lange gedauert. Bitte die Verbindung prüfen und inlaut erneut starten."), error);
        }
    }
}
