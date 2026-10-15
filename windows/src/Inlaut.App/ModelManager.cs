using System.Net.Http;

namespace Inlaut.App;

public class ModelManager
{
    private static readonly string ModelDirName = "models";

    private const string TransducerBaseUrl = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-transducer-stt_de_fastconformer_hybrid_large_pc-int8/resolve/main/";

    private static readonly (string File, string Desc, long EstSize)[] ModelFiles = new[]
    {
        ("tokens.txt", "Sprach-Tokens", 11_000L),
        ("encoder.int8.onnx", "Akustik-Encoder (131 MB)", 131_114_014L),
        ("decoder.int8.onnx", "Prädiktor-Decoder (4 MB)", 3_955_863L),
        ("joiner.int8.onnx", "Joiner-Netzwerk (1.4 MB)", 1_408_183L)
    };

    public static string GetModelDirectory()
    {
        // 1. Check next to executable (portable mode)
        string appDir = AppDomain.CurrentDomain.BaseDirectory;
        string localModels = Path.Combine(appDir, ModelDirName);
        if (Directory.Exists(localModels) && HasValidModel(localModels))
        {
            return localModels;
        }

        // Check subdirectories in appDir/models
        if (Directory.Exists(localModels))
        {
            foreach (var sub in Directory.GetDirectories(localModels))
            {
                if (HasValidModel(sub)) return sub;
            }
        }

        // 2. Check %LocalAppData%/inlaut/models
        string appData = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "inlaut",
            ModelDirName
        );

        if (Directory.Exists(appData) && HasValidModel(appData))
        {
            return appData;
        }

        if (Directory.Exists(appData))
        {
            foreach (var sub in Directory.GetDirectories(appData))
            {
                if (HasValidModel(sub)) return sub;
            }
        }

        return localModels; // Default target
    }

    public static bool HasValidModel(string directory)
    {
        if (!Directory.Exists(directory)) return false;

        bool hasTokens = File.Exists(Path.Combine(directory, "tokens.txt"));
        
        bool hasTransducer = (File.Exists(Path.Combine(directory, "encoder.int8.onnx")) || File.Exists(Path.Combine(directory, "encoder.onnx")))
                          && (File.Exists(Path.Combine(directory, "decoder.int8.onnx")) || File.Exists(Path.Combine(directory, "decoder.onnx")))
                          && (File.Exists(Path.Combine(directory, "joiner.int8.onnx")) || File.Exists(Path.Combine(directory, "joiner.onnx")));

        bool hasCtc = File.Exists(Path.Combine(directory, "model.int8.onnx")) || File.Exists(Path.Combine(directory, "model.onnx"));

        return hasTokens && (hasTransducer || hasCtc);
    }

    public static async Task<string> EnsureModelAvailableAsync(Action<string, int>? progressCallback = null)
    {
        string existing = GetModelDirectory();
        if (HasValidModel(existing))
        {
            return existing;
        }

        // Fallback target: %LocalAppData%/inlaut/models/fastconformer-de-transducer
        string targetDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "inlaut",
            ModelDirName,
            "fastconformer-de-transducer"
        );

        Directory.CreateDirectory(targetDir);

        using var client = new HttpClient();
        client.Timeout = TimeSpan.FromMinutes(10);

        long grandTotal = 0;
        foreach (var item in ModelFiles) grandTotal += item.EstSize;

        long downloadedBytes = 0;

        foreach (var (file, desc, estSize) in ModelFiles)
        {
            string dest = Path.Combine(targetDir, file);
            if (File.Exists(dest) && new FileInfo(dest).Length > 0)
            {
                downloadedBytes += estSize;
                continue;
            }

            int percent = (int)(downloadedBytes * 100 / grandTotal);
            progressCallback?.Invoke($"Lade {desc} herunter...", percent);

            string url = TransducerBaseUrl + file;
            using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();

            using var contentStream = await response.Content.ReadAsStreamAsync();
            using var fileStream = new FileStream(dest + ".tmp", FileMode.Create, FileAccess.Write, FileShare.None);

            var buffer = new byte[81920];
            int read;
            long itemRead = 0;
            while ((read = await contentStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
            {
                await fileStream.WriteAsync(buffer, 0, read);
                itemRead += read;
                int currentPercent = (int)((downloadedBytes + itemRead) * 100 / grandTotal);
                progressCallback?.Invoke($"Lade {desc} herunter...", Math.Min(99, currentPercent));
            }

            fileStream.Close();
            File.Move(dest + ".tmp", dest, true);
            downloadedBytes += estSize;
        }

        progressCallback?.Invoke("Sprachmodell bereit!", 100);
        return targetDir;
    }
}
