using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace Inlaut.App;

public record MicrophoneOption(string Id, string Name)
{
    public override string ToString() => Name;
}

public class AudioRecorder : IDisposable
{
    private WasapiCapture? _capture;
    private MMDevice? _device;
    private MemoryStream? _buffer;
    private WaveFormat? _format;
    private readonly object _gate = new();
    private bool _retain;
    public bool IsRecording { get; private set; }
    public float CurrentLevel { get; private set; }
    public Exception? Failure { get; private set; }
    public string ActiveDeviceName { get; private set; } = "";
    public event Action? DeviceFailed;

    public static List<MicrophoneOption> Devices()
    {
        using var enumerator = new MMDeviceEnumerator();
        var result = new List<MicrophoneOption> { new("", UiText.Get("Windows-Standardmikrofon")) };
        foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active))
            using (device) result.Add(new(device.ID, device.FriendlyName));
        return result;
    }

    public void Start(string deviceId = "", bool retainAudio = true)
    {
        if (IsRecording) return;
        Dispose();
        Failure = null;
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            _device = string.IsNullOrEmpty(deviceId)
                ? enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console)
                : enumerator.GetDevice(deviceId);
            if (_device.State != DeviceState.Active) throw new InvalidOperationException(UiText.Get("Das gewählte Mikrofon ist nicht verbunden. Bitte in den Einstellungen ein anderes wählen."));
            ActiveDeviceName = _device.FriendlyName;
            _capture = new WasapiCapture(_device);
            _format = _capture.WaveFormat;
            _retain = retainAudio;
            _buffer = retainAudio ? new MemoryStream() : null;
            _capture.DataAvailable += (_, e) =>
            {
                lock (_gate)
                {
                    if (!IsRecording) return;
                    if (_retain) _buffer!.Write(e.Buffer, 0, e.BytesRecorded);
                    using var block = new RawSourceWaveStream(new MemoryStream(e.Buffer, 0, e.BytesRecorded, false), _format);
                    var provider = block.ToSampleProvider();
                    float[] levels = new float[1024];
                    float peak = 0;
                    int read;
                    while ((read = provider.Read(levels, 0, levels.Length)) > 0)
                        for (int i = 0; i < read; i++) peak = Math.Max(peak, Math.Abs(levels[i]));
                    CurrentLevel = Math.Clamp(peak, 0, 1);
                }
            };
            _capture.RecordingStopped += (_, e) =>
            {
                if (e.Exception == null) return;
                Failure = e.Exception;
                DeviceFailed?.Invoke();
            };
            IsRecording = true;
            _capture.StartRecording();
        }
        catch { Dispose(); throw; }
    }

    public float[] Stop()
    {
        if (_capture == null) return [];
        // Stop outside the buffer lock: capture shutdown joins its worker.
        try { _capture.StopRecording(); } catch (Exception error) { Failure ??= error; }
        try { _capture.Dispose(); } catch (Exception error) { Failure ??= error; }
        _capture = null;
        byte[] bytes;
        lock (_gate)
        {
            IsRecording = false;
            CurrentLevel = 0;
            bytes = _buffer?.ToArray() ?? [];
            _buffer?.Dispose(); _buffer = null;
        }
        _device?.Dispose(); _device = null;
        if (Failure != null) throw new InvalidOperationException(UiText.Get("Die Mikrofonaufnahme wurde unterbrochen. Bitte das Gerät prüfen und erneut diktieren."), Failure);
        return bytes.Length == 0 ? [] : ConvertTo16kMono(bytes, _format!);
    }

    internal static float[] ConvertTo16kMono(byte[] bytes, WaveFormat format)
    {
        using var stream = new RawSourceWaveStream(new MemoryStream(bytes, false), format);
        ISampleProvider samples = new MonoProvider(stream.ToSampleProvider());
        if (samples.WaveFormat.SampleRate != 16000) samples = new WdlResamplingSampleProvider(samples, 16000);
        var result = new List<float>();
        float[] block = new float[4096];
        int read;
        while ((read = samples.Read(block, 0, block.Length)) > 0) result.AddRange(block.Take(read));
        return result.ToArray();
    }

    public void Dispose()
    {
        IsRecording = false;
        try { _capture?.StopRecording(); } catch { }
        try { _capture?.Dispose(); } catch { }
        _capture = null;
        lock (_gate) { _buffer?.Dispose(); _buffer = null; }
        _device?.Dispose(); _device = null;
        CurrentLevel = 0;
    }

    private sealed class MonoProvider(ISampleProvider source) : ISampleProvider
    {
        public WaveFormat WaveFormat { get; } = WaveFormat.CreateIeeeFloatWaveFormat(source.WaveFormat.SampleRate, 1);
        public int Read(float[] buffer, int offset, int count)
        {
            int channels = source.WaveFormat.Channels;
            float[] input = new float[count * channels];
            int read = source.Read(input, 0, input.Length);
            int frames = read / channels;
            for (int i = 0; i < frames; i++)
            {
                float value = 0;
                for (int c = 0; c < channels; c++) value += input[i * channels + c];
                buffer[offset + i] = value / channels;
            }
            return frames;
        }
    }
}
