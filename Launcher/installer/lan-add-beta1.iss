#define MyAppName "KYBER Launcher LANadd"
#ifndef MyAppVersion
  #define VersionFile FileOpen("..\assets\lan_add_version.txt")
  #define MyAppVersion Trim(FileRead(VersionFile))
  #expr FileClose(VersionFile)
#endif
#define MyAppPublisher "Mechtaatel"
#define MyAppURL "https://github.com/Mechtaatel/Kyber-LANadd"
#define AppId "KyberLauncherLANADD"
#define AppExeName "kyber_launcher.exe"
#ifndef BundleSourceDir
  #define BundleSourceDir "..\..\artifacts\kyber-lan-add-beta1-windows"
#endif
#ifndef SetupOutputName
  #define SetupOutputName "Kyber-LAN-ADD-Beta-1-Setup"
#endif
#if !FileExists(BundleSourceDir + "\data\flutter_assets\assets\lan_add_version.txt")
  #error "LAN ADD version asset is missing from the bundle. Rebuild and package the launcher."
#endif
#define BundleVersionFile FileOpen(BundleSourceDir + "\data\flutter_assets\assets\lan_add_version.txt")
#define BundleVersion Trim(FileRead(BundleVersionFile))
#expr FileClose(BundleVersionFile)
#if BundleVersion != MyAppVersion
  #error "Installer and bundled LAN ADD versions do not match."
#endif

[Setup]
AppId={#AppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#StringChange(MyAppVersion, ".0-beta", "-beta")}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\KYBER Launcher LAN ADD
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
LicenseFile=..\..\LICENSE
OutputDir=..\..\artifacts
OutputBaseFilename={#SetupOutputName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
RestartApplications=no

[Dirs]
Name: "{commonappdata}\Kyber"; Permissions: users-modify
Name: "{commonappdata}\Kyber\Module"; Permissions: users-modify
Name: "{commonappdata}\Kyber\LAN-Modules"; Permissions: users-modify

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[InstallDelete]
Type: files; Name: "{app}\lan-module\*.dll"
Type: files; Name: "{app}\lan-module\ca_root.pem"
Type: files; Name: "{app}\lan-module\VanillaBundleAggregation.kb"
Type: files; Name: "{app}\lan-module\ONLINE-COMPATIBILITY.json"
Type: files; Name: "{app}\lan-module\VERSION"
Type: files; Name: "{app}\lan-module\LAN-MODULE"
Type: dirifempty; Name: "{app}\lan-module"

[Files]
Source: "{#BundleSourceDir}\*"; Excludes: "lan-module\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

Source: "{#BundleSourceDir}\lan-module\*"; DestDir: "{commonappdata}\Kyber\LAN-Modules"; Flags: ignoreversion
Source: "cleanup-module-cache.ps1"; DestDir: "{app}"; Flags: deleteafterinstall

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#AppExeName}"; AppUserModelID: "kyber.LANADD"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCR; Subkey: ".kbcollection"; ValueType: string; ValueName: ""; ValueData: "KyberLauncherLANADD.kmodfile"; Flags: uninsdeletevalue
Root: HKCR; Subkey: "KyberLauncherLANADD.kmodfile"; ValueType: string; ValueName: ""; ValueData: "Kyber Collection File"; Flags: uninsdeletekey
Root: HKCR; Subkey: "KyberLauncherLANADD.kmodfile\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExeName},0"; Flags: uninsdeletekey
Root: HKCR; Subkey: "KyberLauncherLANADD.kmodfile\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""; Flags: uninsdeletekey

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\cleanup-module-cache.ps1"""; Flags: runhidden waituntilterminated runasoriginaluser
Filename: "{app}\{#AppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\{#AppExeName}"; Flags: nowait runasoriginaluser; Check: IsLanAddUpdate

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Command: String;
  ExitCode: Integer;
begin
  Result := '';
  { Maxima runs as a service and can keep its executable and runtime DLL locked. }
  Command := '$ErrorActionPreference = ''Stop''; try { ' +
    '$service = Get-Service -Name ''MaximaBackgroundService'' -ErrorAction SilentlyContinue; ' +
    'if ($null -ne $service) { ' +
    'if ($service.Status -ne ''Stopped'') { ' +
    'Stop-Service -InputObject $service -NoWait; ' +
    '$service.WaitForStatus(''Stopped'', [TimeSpan]::FromSeconds(30)); ' +
    '} }; exit 0 } catch { exit 1 }';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -Command "' + Command + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
    Result := 'Could not start the Maxima service shutdown. Restart Windows and run setup again.'
  else if ExitCode <> 0 then
    Result := 'Could not stop MaximaBackgroundService. Close Battlefront II and KYBER, then stop the service or restart Windows before retrying.';
end;

function IsLanAddUpdate: Boolean;
begin
  Result := ExpandConstant('{param:LANADDUPDATE|0}') = '1';
end;

