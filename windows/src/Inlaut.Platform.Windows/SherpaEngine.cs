using System.Diagnostics;
using SherpaOnnx;

namespace Inlaut.Platform.Windows;

public class SherpaEngine : IDisposable
{
    private readonly OfflineRecognizer _recognizer;

    public SherpaEngine(string modelDir)
    {
        if (!Directory.Exists(modelDir))
        {
            throw new DirectoryNotFoundException($"Model directory not found: {modelDir}");
        }

        string tokensPath = Path.Combine(modelDir, "tokens.txt");
        if (!File.Exists(tokensPath))
        {
            throw new FileNotFoundException($"Tokens file not found at: {tokensPath}");
        }

        var config = new OfflineRecognizerConfig();
        config.ModelConfig.Tokens = tokensPath;
        config.ModelConfig.NumThreads = Math.Max(2, Environment.ProcessorCount / 2);
        config.ModelConfig.Debug = 0;
        config.ModelConfig.Provider = "cpu";

        // 1. Check for NeMo Transducer model (Encoder, Decoder, Joiner) - Preferred for German STT
        string encoder = Path.Combine(modelDir, "encoder.int8.onnx");
        if (!File.Exists(encoder)) encoder = Path.Combine(modelDir, "encoder.onnx");

        string decoder = Path.Combine(modelDir, "decoder.int8.onnx");
        if (!File.Exists(decoder)) decoder = Path.Combine(modelDir, "decoder.onnx");

        string joiner = Path.Combine(modelDir, "joiner.int8.onnx");
        if (!File.Exists(joiner)) joiner = Path.Combine(modelDir, "joiner.onnx");

        if (File.Exists(encoder) && File.Exists(decoder) && File.Exists(joiner))
        {
            config.ModelConfig.Transducer.Encoder = encoder;
            config.ModelConfig.Transducer.Decoder = decoder;
            config.ModelConfig.Transducer.Joiner = joiner;
            config.ModelConfig.ModelType = "nemo_transducer";
            
            // Use modified_beam_search to prevent repetition loops during silence/pauses
            config.DecodingMethod = "modified_beam_search";
            config.MaxActivePaths = 4;
        }
        else
        {
            // 2. Fallback: Check for NeMo CTC model (single onnx or int8)
            string ctcModel = Path.Combine(modelDir, "model.int8.onnx");
            if (!File.Exists(ctcModel)) ctcModel = Path.Combine(modelDir, "model.onnx");

            if (File.Exists(ctcModel))
            {
                config.ModelConfig.NeMoCtc.Model = ctcModel;
                config.ModelConfig.ModelType = "nemo_ctc";
                config.DecodingMethod = "greedy_search";
            }
            else
            {
                throw new FileNotFoundException($"No valid NeMo Transducer or CTC ONNX model files found in {modelDir}");
            }
        }

        config.FeatConfig.SampleRate = 16000;
        config.FeatConfig.FeatureDim = 80;

        _recognizer = new OfflineRecognizer(config);
    }

    public (string Text, double DurationSec, double DecodeSec, double Rtf) TranscribeFile(string wavPath)
    {
        var reader = new WaveReader(wavPath);
        return TranscribeSamples(reader.Samples, reader.SampleRate);
    }

    public (string Text, double DurationSec, double DecodeSec, double Rtf) TranscribeSamples(float[] samples, int sampleRate = 16000)
    {
        if (samples == null || samples.Length == 0)
        {
            return ("", 0, 0, 0);
        }

        // Trim leading and trailing silence so joiner does not get stuck in silence emission loops
        float[] trimmed = AudioTrimmer.TrimSilence(samples, sampleRate);
        if (trimmed.Length == 0)
        {
            // Pure silence or background noise only
            return ("", 0, 0, 0);
        }

        double audioSec = (double)trimmed.Length / sampleRate;

        using var stream = _recognizer.CreateStream();
        stream.AcceptWaveform(sampleRate, trimmed);

        var sw = Stopwatch.StartNew();
        _recognizer.Decode(stream);
        sw.Stop();

        double decodeSec = sw.Elapsed.TotalSeconds;
        double rtf = audioSec > 0 ? decodeSec / audioSec : 0;
        string text = stream.Result.Text?.Trim() ?? "";

        return (text, audioSec, decodeSec, rtf);
    }

    public void Dispose()
    {
        _recognizer.Dispose();
        GC.SuppressFinalize(this);
    }
}
