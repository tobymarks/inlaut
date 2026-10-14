using System.Net.Http;

namespace Inlaut.App;

public class ModelManager
{
    private static readonly string ModelDirName = "models";
    private static readonly string TokensFileName = "tokens.txt";
    private static readonly string ModelFileName = "model.int8.onnx";

    private const string TokensUrl = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-stt_de_fastconformer_hybrid_large_pc-int8/resolve/main/tokens.txt";
    private const string ModelUrl = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-stt_de_fastconformer_hybrid_large_pc-int8/resolve/main/model.int8.onnx";

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
        bool hasCtc = File.Exists(Path.Combine(directory, "model.int8.onnx")) || File.Exists(Path.Combine(directory, "model.onnx"));
        bool hasTransducer = File.Exists(Path.Combine(directory, "encoder.int8.onnx")) || File.Exists(Path.Combine(directory, "encoder.onnx"));

        return hasTokens && (hasCtc || hasTransducer);
    }

    public static async Task<string> EnsureModelAvailableAsync(Action<string, int>? progressCallback = null)
    {
        string existing = GetModelDirectory();
        if (HasValidModel(existing))
        {
            return existing;
        }

        // Fallback target: %LocalAppData%/inlaut/models/default
        string targetDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "inlaut",
            ModelDirName,
            "fastconformer-ctc-de-int8"
        );

        Directory.CreateDirectory(targetDir);

        string tokensDest = Path.Combine(targetDir, TokensFileName);
        string modelDest = Path.Combine(targetDir, ModelFileName);

        using var client = new HttpClient();
        client.Timeout = TimeSpan.FromMinutes(10);

        if (!File.Exists(tokensDest))
        {
            progressCallback?.Invoke("Lade Sprach-Tokens herunter...", 10);
            var tokensBytes = await client.GetByteArrayAsync(TokensUrl);
            await File.WriteAllBytesAsync(tokensDest, tokensBytes);
        }

        if (!File.Exists(modelDest))
        {
            progressCallback?.Invoke("Lade deutsches Sprachmodell herunter (ca. 125 MB)...", 20);
            using var response = await client.GetAsync(ModelUrl, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();

            var totalBytes = response.Content.Headers.ContentLength ?? 131_652_945L;
            using var contentStream = await response.Content.ReadAsStreamAsync();
            using var fileStream = new FileStream(modelDest + ".tmp", FileMode.Create, FileAccess.Write, FileShare.None);

            var buffer = new byte[81920];
            long totalRead = 0;
            int read;

            while ((read = await contentStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
            {
                await fileStream.WriteAsync(buffer, 0, read);
                totalRead += read;
                int percent = 20 + (int)((totalRead * 75) / totalBytes);
                progressCallback?.Invoke($"Lade Sprachmodell herunter: {totalRead / 1024 / 1024} MB / {totalBytes / 1024 / 1024} MB", Math.Min(95, percent));
            }

            fileStream.Close();
            if (File.Exists(modelDest)) File.Delete(modelDest);
            File.Move(modelDest + ".tmp", modelDest);
        }

        progressCallback?.Invoke("Sprachmodell bereit!", 100);
        return targetDir;
    }
}
