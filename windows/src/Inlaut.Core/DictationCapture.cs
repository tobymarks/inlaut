using System.Text;
using System.Text.Json;

namespace Inlaut.Core;

/// <summary>Explicit diagnostic capture only. Never called by ordinary metadata logging.</summary>
public sealed class DictationCapture
{
    public string DirectoryPath { get; }
    private readonly int _sampleRate;

    public DictationCapture(string root, float[] recorded, int sampleRate, object metadata)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(sampleRate);
        _sampleRate = sampleRate;
        DirectoryPath = Path.Combine(root, DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff") + "-" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(DirectoryPath);
        WriteJson("metadata.json", metadata);
        WriteWave("recorded.wav", recorded);
        WriteJson("result.json", new { status = "pending" });
    }

    public void Prepared(float[] samples) => WriteWave("recognizer-input.wav", samples);

    public void Complete(string rawText, string processedText, double audioSeconds, double decodeSeconds) =>
        WriteJson("result.json", new { status = "recognized", rawText, processedText, audioSeconds, decodeSeconds });

    public void Failed(string errorType) => WriteJson("result.json", new { status = "failed", errorType });

    private void WriteJson(string file, object data)
    {
        string path = Path.Combine(DirectoryPath, file);
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true }), new UTF8Encoding(false));
        File.Move(path + ".tmp", path, true);
    }

    private void WriteWave(string file, float[] samples)
    {
        string path = Path.Combine(DirectoryPath, file);
        int dataBytes = checked(samples.Length * 2);
        using (var writer = new BinaryWriter(File.Create(path + ".tmp")))
        {
            writer.Write(Encoding.ASCII.GetBytes("RIFF")); writer.Write(checked(36 + dataBytes));
            writer.Write(Encoding.ASCII.GetBytes("WAVEfmt ")); writer.Write(16);
            writer.Write((short)1); writer.Write((short)1); // PCM16 mono, same precision as the microphone
            writer.Write(_sampleRate); writer.Write(checked(_sampleRate * 2));
            writer.Write((short)2); writer.Write((short)16);
            writer.Write(Encoding.ASCII.GetBytes("data")); writer.Write(dataBytes);
            foreach (float sample in samples)
                writer.Write((short)Math.Clamp(MathF.Round(sample * 32768), short.MinValue, short.MaxValue));
        }
        File.Move(path + ".tmp", path, true);
    }
}
