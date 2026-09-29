#define MyAppName "KYBER Launcher LAN ADD"
#define MyAppVersion "1.0.0-beta.1"
#define MyAppPublisher "Mechtaatel"
#define MyAppURL "https://github.com/Mechtaatel/Kyber-LANadd"
#define AppId "KyberLauncherLANADD"
#define AppExeName "kyber_launcher.exe"
#define BundleSourceDir "..\..\artifacts\kyber-lan-add-beta1-windows"

[Setup]
AppId={#AppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases/latest
DefaultDirName={autopf}\KYBER Launcher LAN ADD
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
LicenseFile=..\..\LICENSE
OutputDir=..\..\artifacts
OutputBaseFilename=Kyber-LAN-ADD-Beta-1-Setup
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
