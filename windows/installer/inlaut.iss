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

[InstallDelete]
; Leftovers of an earlier runtime: the .NET 8 builds up to 0.7.0-beta.9 also
; installed WPF, and every runtime patch brings its own debugger file and notice
; folders. Only names this installer creates: the install folder can be chosen freely.
Type: files; Name: "{app}\mscordaccore_amd64_amd64_*.dll"
Type: filesandordirs; Name: "{app}\licenses\Microsoft.NETCore.App.Runtime.win-x64"
Type: filesandordirs; Name: "{app}\licenses\Microsoft.WindowsDesktop.App.Runtime.win-x64"
Type: filesandordirs; Name: "{app}\licenses\Microsoft.Win32.Registry"
Type: filesandordirs; Name: "{app}\licenses\System.Security.AccessControl"
Type: filesandordirs; Name: "{app}\licenses\System.Security.Principal.Windows"
; NAudio 2 up to 0.7.0-beta.10 shipped Asio and WinForms assemblies and its own
; license file; NAudio 3's license now lives in licenses\naudio (deleted first, then installed).
Type: files; Name: "{app}\NAudio.Asio.dll"
Type: files; Name: "{app}\NAudio.WinForms.dll"
Type: filesandordirs; Name: "{app}\licenses\NAudio"
Type: files; Name: "{app}\cs\*.resources.dll"
Type: files; Name: "{app}\de\*.resources.dll"
Type: files; Name: "{app}\es\*.resources.dll"
Type: files; Name: "{app}\fr\*.resources.dll"
Type: files; Name: "{app}\it\*.resources.dll"
Type: files; Name: "{app}\ja\*.resources.dll"
Type: files; Name: "{app}\ko\*.resources.dll"
Type: files; Name: "{app}\pl\*.resources.dll"
Type: files; Name: "{app}\pt-BR\*.resources.dll"
Type: files; Name: "{app}\ru\*.resources.dll"
Type: files; Name: "{app}\tr\*.resources.dll"
Type: files; Name: "{app}\zh-Hans\*.resources.dll"
Type: files; Name: "{app}\zh-Hant\*.resources.dll"
Type: files; Name: "{app}\D3DCompiler_47_cor3.dll"
Type: files; Name: "{app}\DirectWriteForwarder.dll"
Type: files; Name: "{app}\PenImc_cor3.dll"
Type: files; Name: "{app}\PresentationCore.dll"
Type: files; Name: "{app}\PresentationFramework-SystemCore.dll"
Type: files; Name: "{app}\PresentationFramework-SystemData.dll"
Type: files; Name: "{app}\PresentationFramework-SystemDrawing.dll"
Type: files; Name: "{app}\PresentationFramework-SystemXml.dll"
Type: files; Name: "{app}\PresentationFramework-SystemXmlLinq.dll"
Type: files; Name: "{app}\PresentationFramework.Aero.dll"
Type: files; Name: "{app}\PresentationFramework.Aero2.dll"
Type: files; Name: "{app}\PresentationFramework.AeroLite.dll"
Type: files; Name: "{app}\PresentationFramework.Classic.dll"
Type: files; Name: "{app}\PresentationFramework.Luna.dll"
Type: files; Name: "{app}\PresentationFramework.Royale.dll"
Type: files; Name: "{app}\PresentationFramework.dll"
Type: files; Name: "{app}\PresentationNative_cor3.dll"
Type: files; Name: "{app}\PresentationUI.dll"
Type: files; Name: "{app}\ReachFramework.dll"
Type: files; Name: "{app}\System.Printing.dll"
Type: files; Name: "{app}\System.Windows.Controls.Ribbon.dll"
Type: files; Name: "{app}\System.Windows.Input.Manipulations.dll"
Type: files; Name: "{app}\System.Windows.Presentation.dll"
Type: files; Name: "{app}\System.Xaml.dll"
Type: files; Name: "{app}\UIAutomationClient.dll"
Type: files; Name: "{app}\UIAutomationClientSideProviders.dll"
Type: files; Name: "{app}\UIAutomationProvider.dll"
Type: files; Name: "{app}\UIAutomationTypes.dll"
Type: files; Name: "{app}\WindowsFormsIntegration.dll"
Type: files; Name: "{app}\vcruntime140_cor3.dll"
Type: files; Name: "{app}\wpfgfx_cor3.dll"

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
