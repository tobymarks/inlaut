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
VersionInfoProductVersion={#AppVersion}
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
AppMutex=Global\Inlaut-Windows-App-SingleInstance
CloseApplications=no
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "Desktop-Verknüpfung erstellen"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\inlaut Beta"; Filename: "{app}\Inlaut.exe"
Name: "{autodesktop}\inlaut Beta"; Filename: "{app}\Inlaut.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Inlaut.exe"; Description: "inlaut Beta starten"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "inlaut"; Flags: dontcreatekey uninsdeletevalue
