using NAudio.Wave;

namespace Inlaut.App;

public class AudioRecorder : IDisposable
{
    private WaveInEvent? _waveIn;
    private MemoryStream? _audioBuffer;
    private readonly object _lock = new();
    public bool IsRecording { get; private set; }

    public void Start()
    {
        lock (_lock)
        {
            if (IsRecording) return;

            _audioBuffer = new MemoryStream();
            _waveIn = new WaveInEvent
            {
                WaveFormat = new WaveFormat(16000, 16, 1) // 16 kHz Mono 16-bit
            };

            _waveIn.DataAvailable += (s, e) =>
            {
                lock (_lock)
                {
                    _audioBuffer?.Write(e.Buffer, 0, e.BytesRecorded);
                }
            };

            _waveIn.StartRecording();
            IsRecording = true;
        }
    }

    public float[] Stop()
    {
        lock (_lock)
        {
            if (!IsRecording || _waveIn == null || _audioBuffer == null)
            {
                return Array.Empty<float>();
            }

            _waveIn.StopRecording();
            _waveIn.Dispose();
            _waveIn = null;
            IsRecording = false;

            byte[] bytes = _audioBuffer.ToArray();
            _audioBuffer.Dispose();
            _audioBuffer = null;

            int sampleCount = bytes.Length / 2;
            float[] samples = new float[sampleCount];

            for (int i = 0; i < sampleCount; i++)
            {
                short sample = (short)(bytes[i * 2] | (bytes[i * 2 + 1] << 8));
                samples[i] = sample / 32768.0f;
            }

            return samples;
        }
    }

    public void Dispose()
    {
        lock (_lock)
        {
            if (IsRecording)
            {
                _waveIn?.StopRecording();
            }
            _waveIn?.Dispose();
            _audioBuffer?.Dispose();
            IsRecording = false;
        }
    }
}
