namespace Inlaut.Core;

public sealed record UpdateRequest(int ParentPid, long ParentStarted, string Application, string CurrentVersion, UpdateManifest Manifest, string InterfaceLanguage = "de");
