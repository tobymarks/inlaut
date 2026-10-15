namespace Inlaut.Platform.Windows;

public static class AudioTrimmer
{
    /// <summary>
    /// Trims leading and trailing silence/background noise from PCM float samples.
    /// Returns an empty array if the entire buffer is below the voice activity threshold.
    /// </summary>
    public static float[] TrimSilence(float[] samples, int sampleRate = 16000, float threshold = 0.006f, int padMs = 180)
    {
        if (samples == null || samples.Length == 0) return Array.Empty<float>();

        int windowSize = sampleRate / 50; // 20ms window (320 samples at 16kHz)
        if (windowSize <= 0) windowSize = 320;

        int padSamples = (sampleRate * padMs) / 1000;

        int firstActive = -1;
        int lastActive = -1;

        for (int i = 0; i <= samples.Length - windowSize; i += windowSize)
        {
            float sum = 0f;
            for (int j = 0; j < windowSize; j++)
            {
                sum += Math.Abs(samples[i + j]);
            }
            float avg = sum / windowSize;

            if (avg >= threshold)
            {
                if (firstActive == -1) firstActive = i;
                lastActive = i + windowSize;
            }
        }

        // If no speech above threshold was detected, return empty so we do not decode silence
        if (firstActive == -1) return Array.Empty<float>();

        int start = Math.Max(0, firstActive - padSamples);
        int end = Math.Min(samples.Length, lastActive + padSamples);
        int length = end - start;

        if (length <= 0) return Array.Empty<float>();

        float[] trimmed = new float[length];
        Array.Copy(samples, start, trimmed, 0, length);
        return trimmed;
    }
}
