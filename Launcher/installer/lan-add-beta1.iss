#define MyAppName "KYBER Launcher LAN ADD"
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
AppVerName={#MyAppName} {#MyAppVersion}
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

[Dirs]
Name: "{commonappdata}\Kyber"; Permissions: users-modify
Name: "{commonappdata}\Kyber\Module"; Permissions: users-modify
Name: "{commonappdata}\Kyber\LAN-Modules"; Permissions: users-modify

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "{#BundleSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#AppExeName}"; AppUserModelID: "kyber.LANADD"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCR; Subkey: ".kbcollection"; ValueType: string; ValueName: ""; ValueData: "KyberLauncherLANADD.kmodfile"; Flags: uninsdeletevalue
Root: HKCR; Subkey: "KyberLauncherLANADD.kmodfile"; ValueType: string; ValueName: ""; ValueData: "Kyber Collection File"; Flags: uninsdeletekey
Root: HKCR; Subkey: "KyberLauncherLANADD.kmodfile\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExeName},0"; Flags: uninsdeletekey
Root: HKCR; Subkey: "KyberLauncherLANADD.kmodfile\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\{#AppExeName}"; Flags: nowait runasoriginaluser; Check: IsLanAddUpdate

[Code]
function IsLanAddUpdate: Boolean;
begin
  Result := ExpandConstant('{param:LANADDUPDATE|0}') = '1';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ModuleDll: String;
  OriginalDll: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    ModuleDll := ExpandConstant('{commonappdata}\Kyber\Module\Kyber.dll');
    OriginalDll := ModuleDll + '.lan-add-original';
    if FileExists(OriginalDll) then
    begin
      if CopyFile(OriginalDll, ModuleDll, True) then
        DeleteFile(OriginalDll)
      else
        MsgBox('Could not restore the original Kyber.dll. The backup remains at:' + #13#10 + OriginalDll,
          mbError, MB_OK);
    end;
  end;
end;
