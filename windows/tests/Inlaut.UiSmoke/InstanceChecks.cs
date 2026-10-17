using Inlaut.App;

namespace Inlaut.UiSmoke;

internal static class InstanceChecks
{
    internal static void Run()
    {
        if (LegacyInstanceGuard.IsOtherInstance(10, 1, 10, 1))
            throw new Exception("An app must not detect itself as another instance.");
        if (!LegacyInstanceGuard.IsOtherInstance(20, 1, 10, 1))
            throw new Exception("A legacy instance in the same session must block startup.");
        if (LegacyInstanceGuard.IsOtherInstance(20, 2, 10, 1))
            throw new Exception("An instance in a different session must not block startup.");

        const string currentPath = @"C:\Apps\Current\Inlaut.exe";
        const string otherPath = @"C:\Apps\Portable\Inlaut.exe";
        if (LegacyInstanceGuard.RequiresLegacyCheck(currentPath.ToLowerInvariant(), null, currentPath))
            throw new Exception("The local-mutex loser from the same executable blocked its winner.");
        if (!LegacyInstanceGuard.RequiresLegacyCheck(otherPath, "0.7.0-beta.8+af96c75", currentPath))
            throw new Exception("An older portable binary did not block the new executable.");
        foreach (string version in new[] { "0.7.0-beta.9", "0.7.0-beta.9+abcdef", "0.7.0-beta.10", "0.7.0", "0.8.0" })
            if (LegacyInstanceGuard.RequiresLegacyCheck(otherPath, version, currentPath))
                throw new Exception("A session-local binary was mistaken for a legacy binary: " + version);
        foreach (string? version in new string?[] { null, "unknown", "0.6.0", "0.7.0-beta.8", "999999999999999999999.0.0" })
            if (!LegacyInstanceGuard.RequiresLegacyCheck(otherPath, version, currentPath))
                throw new Exception("An old or unknown foreign binary bypassed the legacy check: " + version);

        // Exercise the actual Windows named object without touching the live app's
        // mutex. The beta.8 constructor uses createdNew, not mutex ownership.
        string name = "Global\\Inlaut-Compatibility-Test-" + Guid.NewGuid().ToString("N");
        using (var compatibility = LegacyInstanceGuard.HoldCompatibilityMutex(name))
        {
            if (compatibility == null) throw new Exception("Compatibility mutex was not created.");
            using var oldBinary = new Mutex(true, name, out bool oldCanStart);
            if (oldCanStart) throw new Exception("An old binary could start after the new binary.");
            using var anotherSession = LegacyInstanceGuard.HoldCompatibilityMutex(name);
            if (anotherSession == null) throw new Exception("Existing legacy mutex blocked another new instance.");
        }
        using (var oldBinary = new Mutex(true, name, out bool oldCanStart))
        {
            if (!oldCanStart) throw new Exception("Compatibility mutex was not released.");
            using var compatibility = LegacyInstanceGuard.HoldCompatibilityMutex(name);
            if (compatibility == null) throw new Exception("Existing legacy mutex cannot be retained.");
            oldBinary.ReleaseMutex();
        }
        Console.WriteLine("PASS: legacy session/version filtering, local winner/loser distinction and beta.8 mutex compatibility in both start orders");
    }
}
