namespace Inlaut.Platform.Windows;

public class WaveReader
{
    public int SampleRate { get; }
    public float[] Samples { get; }

    public WaveReader(string filename)
    {
        using var stream = File.OpenRead(filename);
        using var reader = new BinaryReader(stream);

        // Read RIFF chunk header
        string riff = new string(reader.ReadChars(4));
        if (riff != "RIFF") throw new InvalidDataException("Not a valid RIFF file");
        
        int chunkSize = reader.ReadInt32();
        string wave = new string(reader.ReadChars(4));
        if (wave != "WAVE") throw new InvalidDataException("Not a valid WAVE file");

        // Search for "fmt " chunk
        while (new string(reader.ReadChars(4)) != "fmt ")
        {
            int subChunkSize = reader.ReadInt32();
            reader.BaseStream.Seek(subChunkSize, SeekOrigin.Current);
        }

        int fmtChunkSize = reader.ReadInt32();
        short audioFormat = reader.ReadInt16();     // 1 for PCM, 3 for IEEE float
        short numChannels = reader.ReadInt16();     // Expect 1 (mono)
        SampleRate = reader.ReadInt32();
        int byteRate = reader.ReadInt32();
        short blockAlign = reader.ReadInt16();
        short bitsPerSample = reader.ReadInt16();

        // Skip any extra format bytes
        if (fmtChunkSize > 16)
        {
            reader.BaseStream.Seek(fmtChunkSize - 16, SeekOrigin.Current);
        }

        // Search for "data" chunk
        while (new string(reader.ReadChars(4)) != "data")
        {
            int subChunkSize = reader.ReadInt32();
            reader.BaseStream.Seek(subChunkSize, SeekOrigin.Current);
        }

        int dataSize = reader.ReadInt32();
        int bytesPerSample = bitsPerSample / 8;
        int numSamples = dataSize / bytesPerSample;
        Samples = new float[numSamples];

        if (bitsPerSample == 16)
        {
            for (int i = 0; i < numSamples; i++)
            {
                Samples[i] = reader.ReadInt16() / 32768.0f;
            }
        }
        else if (bitsPerSample == 32 && audioFormat == 3)
        {
            for (int i = 0; i < numSamples; i++)
            {
                Samples[i] = reader.ReadSingle();
            }
        }
        else
        {
            throw new NotSupportedException($"Unsupported WAV format: bitsPerSample={bitsPerSample}, format={audioFormat}");
        }
    }
}
