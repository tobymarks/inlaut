using System.Diagnostics;
using System.Text.Json;

namespace Inlaut.App;

// Separate minimal report, never a dump or a copy of the diagnostic directory.
internal sealed class CrashJournal
{
    internal sealed record Session(DateTimeOffset Started, string Version, string Os, string? LastActivity = null);
    internal sealed record Fault(string Type, int Code, string[] Frames);
    internal sealed record Report(DateTimeOffset Started, string Version, string Os, string Reason, Fault? Fault, string? LastActivity);
    private readonly string _directory;
    private readonly object _gate = new();
    private bool _faulted;
    private Session? _activeSession;
    public static CrashJournal Current { get; } = new(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "inlaut", "crash-reports"));
    public CrashJournal(string directory) => _directory = directory;
    private string SessionPath => Path.Combine(_directory, "session.json");
    private string PendingPath => Path.Combine(_directory, "pending.json");
    private string FaultPath => Path.Combine(_directory, "fault.json");
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };
    public bool Begin()
    {
        try
        {
            lock (_gate)
            {
                Directory.CreateDirectory(_directory);
                if (File.Exists(SessionPath))
                {
                    Session? previous = null;
                    try { previous = JsonSerializer.Deserialize<Session>(File.ReadAllText(SessionPath)); } catch (JsonException) { }
                    if (previous != null)
                    {
                        Fault? fault = null;
                        try { if (File.Exists(FaultPath)) fault = JsonSerializer.Deserialize<Fault>(File.ReadAllText(FaultPath)); } catch (JsonException) { }
                        Atomic(PendingPath, new Report(previous.Started, previous.Version, previous.Os, fault == null ? "Unexpected termination (cause unknown)" : "Unhandled exception", fault, previous.LastActivity));
                    }
                }
                File.Delete(FaultPath);
                _activeSession = new Session(DateTimeOffset.UtcNow, LocalDiagnostics.Version, Environment.OSVersion.Version.ToString());
                Atomic(SessionPath, _activeSession);
                _faulted = false;
                return File.Exists(PendingPath);
            }
        }
        catch { return false; } // A diagnostic failure must never prevent startup.
    }
    public void NoteStage(string stage)
    {
        if (stage is not ("startup" or "recording" or "recorded" or "recognized" or "processed" or "input-sent" or "model-ready" or "failed")) return;
        try
        {
            lock (_gate)
            {
                if (_activeSession == null) return;
                _activeSession = _activeSession with { LastActivity = stage };
                Atomic(SessionPath, _activeSession);
            }
        }
        catch { }
    }
    public void Record(Exception error)
    {
        _faulted = true;
        try
        {
            lock (_gate)
            {
                Directory.CreateDirectory(_directory);
                // Reflection-derived symbols only. No exception message, Data,
                // source filename, user path, environment, settings or transcript.
                var frames = (new StackTrace(error, false).GetFrames() ?? []).Take(20)
                    .Select(f => f.GetMethod()).Where(m => m != null)
                    .Select(m => (m!.DeclaringType?.FullName ?? "unknown") + "." + m.Name).ToArray();
                Atomic(FaultPath, new Fault(error.GetType().FullName ?? "Exception", error.HResult, frames));
            }
        }
        catch { }
    }
    public void EndCleanly()
    {
        if (_faulted) return;
        try { lock (_gate) { _activeSession = null; File.Delete(SessionPath); File.Delete(FaultPath); } } catch { }
    }
    public string? ReadReport()
    {
        try
        {
            if (!File.Exists(PendingPath)) return null;
            // Deserialize/reserialize known fields; never attach arbitrary files.
            var report = JsonSerializer.Deserialize<Report>(File.ReadAllText(PendingPath));
            return report == null ? null : JsonSerializer.Serialize(report, Json);
        }
        catch { return null; }
    }
    public void Dismiss() { try { File.Delete(PendingPath); } catch { } }
    private static void Atomic<T>(string path, T value)
    {
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(value, Json));
        File.Move(path + ".tmp", path, true);
    }
}
