using System.Text;
using Inlaut.Core;
using Inlaut.Platform.Windows;

namespace Inlaut.Cli;

internal class Program
{
    static void Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;

        Console.WriteLine("========================================");
        Console.WriteLine("  inlaut — Windows Engine Prototype");
        Console.WriteLine("========================================");

        string modelDir = "";
        string wavFile = "";
        bool inject = false;

        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--model" && i + 1 < args.Length) modelDir = args[++i];
            else if (args[i] == "--file" && i + 1 < args.Length) wavFile = args[++i];
            else if (args[i] == "--inject") inject = true;
        }

        if (string.IsNullOrEmpty(modelDir))
        {
            // Fallback default: look for ./models or local app data
            string defaultPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "models");
            if (Directory.Exists(defaultPath))
            {
                modelDir = defaultPath;
            }
            else
            {
                Console.WriteLine("Usage:");
                Console.WriteLine("  dotnet run --project src/Inlaut.Cli -- --model <path-to-model-dir> --file <path-to-16khz.wav> [--inject]");
                Console.WriteLine();
                Console.WriteLine("Parameters:");
                Console.WriteLine("  --model    Directory containing tokens.txt and model.onnx (or model.int8.onnx)");
                Console.WriteLine("  --file     Path to a 16 kHz mono 16-bit WAV file to transcribe");
                Console.WriteLine("  --inject   Optional: simulate direct Unicode typing into active focus window via SendInput");
                return;
            }
        }

        if (!File.Exists(wavFile))
        {
            Console.WriteLine($"Error: Audio file not found: {wavFile}");
            return;
        }

        Console.WriteLine($"Loading model from: {modelDir} ...");
        var sw = System.Diagnostics.Stopwatch.StartNew();
        using var engine = new SherpaEngine(modelDir, provider: "cpu", threads: Environment.ProcessorCount >= 4 ? 4 : 2);
        sw.Stop();
        Console.WriteLine($"Model loaded in {sw.Elapsed.TotalMilliseconds:F0} ms.");

        Console.WriteLine($"Transcribing: {wavFile} ...");
        var (rawText, audioSec, decodeSec, rtf) = engine.TranscribeFile(wavFile);

        Console.WriteLine();
        Console.WriteLine($"[Audio: {audioSec:F2}s | Decode: {decodeSec * 1000:F0}ms | RTF: {rtf:F3}]");
        Console.WriteLine($"Raw ASR: \"{rawText}\"");

        // Run inlaut TextPipeline
        var pipeline = new TextPipeline
        {
            Languages = [SpokenLanguage.German, SpokenLanguage.English],
            VoiceCommandsEnabled = true,
            SharpSEnabled = true,
            ReplacementsList =
            [
                new Replacement("Dum", "DAM"),
                new Replacement("Aws", "AWS")
            ]
        };

        string processedText = pipeline.ProcessDictation(rawText);
        Console.WriteLine($"Processed: \"{processedText}\"");

        if (inject)
        {
            Console.WriteLine();
            Console.WriteLine("Injecting text in 3 seconds (switch to your target window now)...");
            Thread.Sleep(3000);
            TextInserter.InsertText(processedText);
            Console.WriteLine("Injected successfully via SendInput (KEYEVENTF_UNICODE).");
        }
    }
}
