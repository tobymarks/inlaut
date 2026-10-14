using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using Inlaut.App;
using Inlaut.Core;
using Inlaut.Platform.Windows;

namespace Inlaut.UiSmoke;

internal static class UpdateChecks
{
    public static async Task Run()
    {
        var versions = new[] { "0.7.0-beta.2", "0.7.0-beta.9", "0.7.0-beta.10", "0.7.0-rc.1", "0.7.0", "0.7.1", "0.8.0-beta.1", "1.0.0" };
        for (int i = 1; i < versions.Length; i++) Assert(ReleaseVersion.Parse(versions[i]).CompareTo(ReleaseVersion.Parse(versions[i - 1])) > 0, "Version order");
        byte[] payload = [1, 2, 3, 4, 5];
        var manifest = new UpdateManifest(1, "0.7.0-beta.10", "https://github.com/tobymarks/inlaut/releases/download/windows-v0.7.0-beta.10/inlaut-0.7.0-beta.10-windows-x64-setup.exe", Convert.ToHexString(SHA256.HashData(payload)), payload.Length);
        Assert(manifest.IsNewer("0.7.0-beta.6", true) && !manifest.IsNewer("0.7.0-beta.6", false) && !manifest.IsNewer("0.7.0", true), "Channel/downgrade guard");
        var stable = manifest with { Version = "0.7.0", Url = manifest.Url.Replace("0.7.0-beta.10", "0.7.0") };
        Assert(stable.IsNewer("0.7.0-beta.6", true) && stable.IsNewer("0.7.0-beta.6", false), "Beta-to-stable promotion");
        foreach (var bad in new[] { manifest with { Schema = 2 }, manifest with { Sha256 = "bad" }, manifest with { Size = 0 }, manifest with { Size = UpdateManifest.MaxBytes + 1 }, manifest with { Url = manifest.Url.Replace("https:", "http:") }, manifest with { Url = manifest.Url.Replace("tobymarks/inlaut", "someone/else") }, manifest with { Version = "0.7.0-beta.01" }, manifest with { Url = manifest.Url + "?x=1" } })
            Reject(() => bad.Validate(), "Invalid manifest accepted");
        string folder = Path.Combine(Path.GetTempPath(), "inlaut-update-tests-" + Guid.NewGuid()); Directory.CreateDirectory(folder);
        try
        {
            var handler = new FakeHandler(request => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(manifest)) });
            using (var client = new UpdateClient(handler)) Assert(await client.Check(true, default) == manifest, "Feed parse");
            Assert(handler.Requests.Single().Contains("windows-beta.json") && handler.Headers.All(h => !h.Contains("Cookie") && !h.Contains("Authorization")), "Request privacy");
            using (var client = new UpdateClient(new FakeHandler(_ => new(HttpStatusCode.NotFound)))) Assert(await client.Check(false, default) == null, "Unpublished feed");
            using (var client = new UpdateClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 17000)) }))) await RejectAsync(() => client.Check(true, default), "Oversize feed");
            using (var client = new UpdateClient(new FakeHandler(_ => throw new HttpRequestException("offline")))) await RejectAsync(() => client.Check(true, default), "Offline error");
            string file = Path.Combine(folder, "update.exe");
            using (var client = new UpdateClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new ByteArrayContent(payload) }))) await client.Download(manifest, file, null, default);
            Assert(File.ReadAllBytes(file).SequenceEqual(payload), "Download bytes");
            using (var client = new UpdateClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new ByteArrayContent(payload) }))) await RejectAsync(() => client.Download(manifest, file, null, default), "Existing staging file overwritten");
            Assert(File.ReadAllBytes(file).SequenceEqual(payload), "Existing file deleted on failed CreateNew");
            Reject(() => UpdateSecurity.VerifyPackage(file, manifest with { Sha256 = new string('0', 64) }, Application.ExecutablePath), "Hash mismatch accepted");
            Reject(() => UpdateSecurity.VerifyPackage(file, manifest, Application.ExecutablePath), "Unsigned payload accepted");
            Reject(() => UpdateSecurity.TrustedCertificate(typeof(AppSettings).Assembly.Location), "Unsigned installed app accepted");
            File.Delete(file);
            using (var client = new UpdateClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new ByteArrayContent([1, 2]) }))) await RejectAsync(() => client.Download(manifest, file, null, default), "Truncated download");
            Assert(!File.Exists(file), "Partial download retained");
            using (var client = new UpdateClient(new FakeHandler(_ => { var body = new ByteArrayContent([1, 2, 3, 4, 5, 6]); body.Headers.ContentLength = manifest.Size; return new(HttpStatusCode.OK) { Content = body }; }))) await RejectAsync(() => client.Download(manifest, file, null, default), "Oversize body");
            Assert(!File.Exists(file), "Oversize download retained");
            using (var client = new UpdateClient(new FakeHandler(_ => new(HttpStatusCode.Redirect) { Headers = { Location = new Uri("https://example.com/wrong.exe") } }))) await RejectAsync(() => client.Download(manifest, file, null, default), "Untrusted redirect");
            using (var cancelled = new CancellationTokenSource())
            {
                cancelled.Cancel();
                using var client = new UpdateClient(new FakeHandler(_ => new(HttpStatusCode.OK) { Content = new ByteArrayContent(payload) }));
                await RejectAsync(() => client.Download(manifest, file, null, cancelled.Token), "Cancellation");
            }
            Assert(!File.Exists(file), "Cancelled download retained");
            using var form = new UpdateForm(true, () => false, () => throw new Exception("Should not exit"), manifest);
            form.Show(); await Task.Delay(80);
            using var bitmap = new Bitmap(form.Width, form.Height); form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, form.Size)); bitmap.Save(Path.Combine(AppContext.BaseDirectory, "updates.png"));
            var button = Descendants(form).OfType<Button>().Single(b => b.Text.StartsWith("Herunterladen")); button.PerformClick();
            Assert(Descendants(form).OfType<Label>().Any(l => l.Text.Contains("Diktat beenden")), "Busy install gate");
            form.Close();
            using var unsigned = new UpdateForm(true, () => true, () => throw new Exception("Unsigned update attempted exit"), manifest);
            unsigned.Show(); await Task.Delay(80);
            Descendants(unsigned).OfType<Button>().Single(b => b.Text.StartsWith("Herunterladen")).PerformClick();
            for (int i = 0; i < 100 && !Descendants(unsigned).OfType<Label>().Any(l => l.Text.Contains("noch keine bestätigte")); i++) await Task.Delay(50);
            Assert(Descendants(unsigned).OfType<Label>().Any(l => l.Text.Contains("noch keine bestätigte")), "Unsigned installation UI did not reject update: " + string.Join(" | ", Descendants(unsigned).OfType<Label>().Select(l => l.Text)));
            unsigned.Close();
            Console.WriteLine("PASS: update version/channel/beta-to-stable rules, malformed feed, offline/404, bounded download, cancellation, redirect restriction, checksum/signature rejection and busy UI gate; no live update traffic");
        }
        finally { Directory.Delete(folder, true); }
    }
    private static IEnumerable<Control> Descendants(Control parent) => parent.Controls.Cast<Control>().SelectMany(c => new[] { c }.Concat(Descendants(c)));
    private static void Assert(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static void Reject(Action action, string message) { try { action(); } catch { return; } throw new Exception(message); }
    private static async Task RejectAsync(Func<Task> action, string message) { try { await action(); } catch { return; } throw new Exception(message); }
    private sealed class FakeHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public List<string> Requests = [], Headers = [];
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        { token.ThrowIfCancellationRequested(); Requests.Add(request.RequestUri!.ToString()); Headers.Add(request.Headers.ToString()); return Task.FromResult(respond(request)); }
    }
}
