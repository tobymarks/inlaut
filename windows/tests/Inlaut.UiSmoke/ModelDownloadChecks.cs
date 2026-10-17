using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using Inlaut.App;

namespace Inlaut.UiSmoke;

internal static class ModelDownloadChecks
{
    internal static async Task Run()
    {
        string root = Path.Combine(Path.GetTempPath(), "inlaut-model-download-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        byte[] expected = [1, 2, 3, 4, 5, 6, 7, 8];
        var file = new ModelManager.ModelFile("model.onnx", expected.Length, Convert.ToHexString(SHA256.HashData(expected)));
        var model = new ModelManager.Model("de", "test-model", "https://models.invalid/", [file]);
        string destination = Path.Combine(root, file.Name);
        byte[] existing = [9, 9, 9];
        try
        {
            // The production downloader receives immediate headers and some
            // bytes, then waits on a body that only stops when it is cancelled.
            using (var body = new StalledBody())
            using (var client = Client(body))
            {
                File.WriteAllBytes(destination, existing);
                var download = ModelManager.DownloadModelAsync(client, model, root, timeout: TimeSpan.FromSeconds(1));
                await body.Waiting.Task.WaitAsync(TimeSpan.FromSeconds(5));
                await Expect<TimeoutException>(download);
                if (!body.Cancelled || !File.ReadAllBytes(destination).SequenceEqual(existing) || File.Exists(destination + ".tmp"))
                    throw new Exception("Timed-out model body was not cancelled/cleaned or replaced an existing file.");
            }

            using (var cancellation = new CancellationTokenSource())
            using (var body = new StalledBody())
            using (var client = Client(body))
            {
                var download = ModelManager.DownloadModelAsync(client, model, root, cancellationToken: cancellation.Token);
                await body.Waiting.Task.WaitAsync(TimeSpan.FromSeconds(5));
                cancellation.Cancel();
                await Expect<OperationCanceledException>(download);
                if (!body.Cancelled || File.Exists(destination + ".tmp") || !File.ReadAllBytes(destination).SequenceEqual(existing))
                    throw new Exception("Caller cancellation was not propagated safely through the model body read.");
            }

            foreach (byte[] invalid in new[] { new byte[expected.Length], new byte[expected.Length + 1] })
            {
                using var client = Client(new MemoryStream(invalid));
                await Expect<InvalidDataException>(ModelManager.DownloadModelAsync(client, model, root));
                if (File.Exists(destination + ".tmp") || !File.ReadAllBytes(destination).SequenceEqual(existing))
                    throw new Exception("Invalid model download replaced the existing file or left a temporary file.");
            }

            var progress = new List<int>();
            using (var client = Client(new MemoryStream(expected)))
                await ModelManager.DownloadModelAsync(client, model, root, (_, percent) => progress.Add(percent));
            if (!File.ReadAllBytes(destination).SequenceEqual(expected) || File.Exists(destination + ".tmp") || progress.LastOrDefault() != 100)
                throw new Exception("Verified model download did not complete and replace the file.");
            Console.WriteLine("PASS: model body deadline, caller cancellation, checksum/size rejection, cleanup and successful recovery");
        }
        finally { Directory.Delete(root, true); }
    }

    private static HttpClient Client(Stream body) => new(new ResponseHandler(body)) { Timeout = Timeout.InfiniteTimeSpan };

    private static async Task Expect<T>(Task operation) where T : Exception
    {
        try { await operation.WaitAsync(TimeSpan.FromSeconds(5)); }
        catch (T) when (operation.IsCompleted) { return; }
        throw new Exception($"Model download did not fail with {typeof(T).Name}.");
    }

    private sealed class ResponseHandler(Stream body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(body) });
    }

    private sealed class StalledBody : Stream
    {
        private bool _sentPrefix;
        internal TaskCompletionSource Waiting { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal bool Cancelled { get; private set; }
        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            if (!_sentPrefix)
            {
                _sentPrefix = true;
                buffer.Span[0] = 1;
                return 1;
            }
            Waiting.TrySetResult();
            try { await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken); }
            catch (OperationCanceledException) { Cancelled = true; throw; }
            return 0;
        }
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
