namespace Inlaut.App;

internal static class RecordingSounds
{
    public static void Play(bool starting)
    {
        try
        {
            using var data = new MemoryStream();
            using (var writer = new BinaryWriter(data, System.Text.Encoding.ASCII, true))
            {
                const int count = 960; // 60 ms; finish before opening the microphone.
                writer.Write(System.Text.Encoding.ASCII.GetBytes("RIFF")); writer.Write(36 + count * 2);
                writer.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt ")); writer.Write(16);
                writer.Write((short)1); writer.Write((short)1); writer.Write(16000); writer.Write(32000);
                writer.Write((short)2); writer.Write((short)16);
                writer.Write(System.Text.Encoding.ASCII.GetBytes("data")); writer.Write(count * 2);
                for (int i = 0; i < count; i++)
                {
                    double envelope = Math.Sin(Math.PI * i / count);
                    writer.Write((short)(6000 * envelope * Math.Sin(2 * Math.PI * (starting ? 880 : 660) * i / 16000)));
                }
            }
            data.Position = 0;
            using var player = new System.Media.SoundPlayer(data); player.PlaySync();
        }
        catch { } // A missing output device must not block dictation.
    }
}
