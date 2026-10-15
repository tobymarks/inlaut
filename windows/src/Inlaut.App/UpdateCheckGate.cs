namespace Inlaut.App;

// UI-thread gate, acquired before any modal dialog pumps a nested message loop.
internal sealed class UpdateCheckGate
{
    private bool _running;
    public async Task RunAsync(Func<Task> operation)
    {
        if (_running) return;
        _running = true;
        try { await operation(); }
        finally { _running = false; }
    }
}
