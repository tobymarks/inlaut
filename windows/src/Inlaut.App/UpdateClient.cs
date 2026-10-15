using System.Net;
using System.Net.Http;
using System.Text;
using Inlaut.Core;

namespace Inlaut.App;

internal sealed class UpdateClient : IDisposable
{
    private readonly HttpClient _http;
    public UpdateClient(HttpMessageHandler? handler = null)
    {
        _http = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false }) { Timeout = TimeSpan.FromMinutes(10) };
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("inlaut-Windows-Updater/1");
    }
    private async Task<HttpResponseMessage> Get(Uri url, CancellationToken token)
    {
        for (int redirects = 0; redirects < 5; redirects++)
        {
            if (url.Scheme != "https" || !url.IsDefaultPort || url.UserInfo != "" || url.Host is not ("inlaut.de" or "github.com" or "release-assets.githubusercontent.com" or "objects.githubusercontent.com")) throw new IOException("Unzulässige Download-Weiterleitung.");
            var response = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, token);
            if ((int)response.StatusCode is >= 300 and < 400 && response.Headers.Location != null)
            { var location = response.Headers.Location; response.Dispose(); url = location.IsAbsoluteUri ? location : new Uri(url, location); continue; }
            return response;
        }
        throw new IOException("Zu viele Download-Weiterleitungen.");
    }
    public async Task<UpdateManifest?> Check(bool beta, CancellationToken token)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token); timeout.CancelAfter(TimeSpan.FromSeconds(30));
        using var response = await Get(new Uri($"https://inlaut.de/updates/windows-{(beta ? "beta" : "stable")}.json"), timeout.Token);
        if (response.StatusCode == HttpStatusCode.NotFound) return null;
        response.EnsureSuccessStatusCode();
        using var stream = await response.Content.ReadAsStreamAsync(timeout.Token); using var output = new MemoryStream();
        await CopyBounded(stream, output, 16384, null, timeout.Token);
        return UpdateManifest.Parse(Encoding.UTF8.GetString(output.ToArray()));
    }
    public async Task Download(UpdateManifest manifest, string destination, IProgress<int>? progress, CancellationToken token)
    {
        manifest.Validate();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
        timeout.CancelAfter(TimeSpan.FromMinutes(10)); token = timeout.Token;
        bool created = false;
        try
        {
            using var response = await Get(new Uri(manifest.Url), token); response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength is long size && size != manifest.Size) throw new IOException("Download-Größe stimmt nicht.");
            using var stream = await response.Content.ReadAsStreamAsync(token);
            await using var file = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true);
            created = true;
            long received = await CopyBounded(stream, file, manifest.Size, progress, token);
            if (received != manifest.Size) throw new IOException("Update-Download unvollständig.");
        }
        catch { if (created && File.Exists(destination)) File.Delete(destination); throw; }
    }
    private static async Task<long> CopyBounded(Stream input, Stream output, long limit, IProgress<int>? progress, CancellationToken token)
    {
        byte[] buffer = new byte[81920]; long total = 0; int count;
        while ((count = await input.ReadAsync(buffer, token)) != 0)
        {
            total += count; if (total > limit) throw new IOException("Download überschreitet die erlaubte Größe.");
            await output.WriteAsync(buffer.AsMemory(0, count), token); progress?.Report((int)(total * 100 / limit));
        }
        return total;
    }
    public void Dispose() => _http.Dispose();
}
