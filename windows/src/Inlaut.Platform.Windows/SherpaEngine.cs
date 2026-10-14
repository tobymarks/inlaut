using System.Diagnostics;
using SherpaOnnx;

namespace Inlaut.Platform.Windows;

public class SherpaEngine : IDisposable
{
    private readonly OfflineRecognizer _recognizer;

    public SherpaEngine(string modelDir, string provider = "cpu", int threads = 4)
    {
        var config = new OfflineRecognizerConfig();
        config.ModelConfig.Provider = provider;
        config.ModelConfig.NumThreads = threads;
        config.ModelConfig.Debug = 0;

        string tokensPath = Path.Combine(modelDir, "tokens.txt");
        if (File.Exists(tokensPath))
        {
            config.ModelConfig.Tokens = tokensPath;
        }

        // Check for NeMo CTC model (single onnx or int8)
        string ctcModel = Path.Combine(modelDir, "model.int8.onnx");
        if (!File.Exists(ctcModel)) ctcModel = Path.Combine(modelDir, "model.onnx");

        if (File.Exists(ctcModel))
        {
            config.ModelConfig.NeMoCtc.Model = ctcModel;
            config.ModelConfig.ModelType = "nemo_ctc";
        }
        else
        {
            // Check for Transducer / TDT model (Encoder, Decoder, Joiner)
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
            }
            else
            {
                throw new FileNotFoundException($"No valid NeMo CTC or Transducer ONNX model files found in {modelDir}");
            }
        }

        _recognizer = new OfflineRecognizer(config);
    }

    public (string Text, double DurationSec, double DecodeSec, double Rtf) TranscribeFile(string wavPath)
    {
        var reader = new WaveReader(wavPath);
        return TranscribeSamples(reader.Samples, reader.SampleRate);
    }

    public (string Text, double DurationSec, double DecodeSec, double Rtf) TranscribeSamples(float[] samples, int sampleRate = 16000)
    {
        double audioSec = (double)samples.Length / sampleRate;

        using var stream = _recognizer.CreateStream();
        stream.AcceptWaveform(sampleRate, samples);

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
    }
}
