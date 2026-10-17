#ifndef PayloadDir
  #error PayloadDir is required
#endif
#ifndef ArtifactDir
  #error ArtifactDir is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif

[Setup]
AppId={{9B11F2B4-5849-45C6-AB66-A8A9EF7D73DA}
AppName=inlaut Beta
AppVersion={#AppVersion}
VersionInfoProductName=inlaut
VersionInfoProductTextVersion={#AppVersion}
AppPublisher=inlaut
AppPublisherURL=https://github.com/tobymarks/inlaut
DefaultDirName={localappdata}\Programs\inlaut Beta
DefaultGroupName=inlaut Beta
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#ArtifactDir}
OutputBaseFilename=inlaut-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\Inlaut.exe
AppMutex=Local\Inlaut-Windows-App-SingleInstance
CloseApplications=no
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\inlaut Beta"; Filename: "{app}\Inlaut.exe"
Name: "{autodesktop}\inlaut Beta"; Filename: "{app}\Inlaut.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Inlaut.exe"; Description: "{cm:LaunchProgram,inlaut Beta}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "inlaut"; Flags: dontcreatekey uninsdeletevalue

[CustomMessages]
english.CloseLegacyInlaut=Please exit inlaut in this Windows session, then try again.
german.CloseLegacyInlaut=Bitte inlaut in dieser Windows-Sitzung beenden und erneut versuchen.
english.LegacyCheckFailed=Setup could not check whether an older inlaut is running. Please restart Windows and try again.
german.LegacyCheckFailed=Setup konnte nicht prüfen, ob eine ältere inlaut-Version läuft. Bitte Windows neu starten und erneut versuchen.

[Code]
function GetCurrentProcessId(): Cardinal;
  external 'GetCurrentProcessId@kernel32.dll stdcall';
function ProcessIdToSessionId(ProcessId: Cardinal; var SessionId: Cardinal): Boolean;
  external 'ProcessIdToSessionId@kernel32.dll stdcall';

function CheckLegacyInstance(): String;
var
  SessionId: Cardinal;
  Locator, Services, Processes: Variant;
begin
  Result := '';
  { beta.8 knows only the global mutex. Its existence in another session is
    harmless; only a process in our session should block this installation. }
  if not CheckForMutexes('Global\Inlaut-Windows-App-SingleInstance') then Exit;
  try
    if not ProcessIdToSessionId(GetCurrentProcessId(), SessionId) then
      RaiseException('Cannot determine installer session');
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Services := Locator.ConnectServer('', 'root\CIMV2');
    Processes := Services.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE Name = ''Inlaut.exe'' AND SessionId = ' + IntToStr(SessionId));
    if Processes.Count > 0 then Result := CustomMessage('CloseLegacyInlaut');
  except
    Log('Legacy instance check failed: ' + GetExceptionMessage);
    Result := CustomMessage('LegacyCheckFailed');
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := CheckLegacyInstance();
end;

function InitializeUninstall(): Boolean;
var
  Error: String;
begin
  Error := CheckLegacyInstance();
  Result := Error = '';
  if not Result then SuppressibleMsgBox(Error, mbError, MB_OK, IDOK);
end;
