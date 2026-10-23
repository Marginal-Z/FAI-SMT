; SMT-FAI Windows installer (Inno Setup 6.3+). Built by CI:
;   ISCC /DAppVersion=1.4.0 /DAppArch=x64 /DSourceDir=<Release folder> smt-fai.iss
; The fixed AppId makes every new version upgrade the existing install in
; place (same folder, shortcuts and uninstall entry). It installs per user,
; so no administrator rights are needed and the in-app updater can run it.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppArch
  #define AppArch "x64"
#endif

[Setup]
AppId={{8F3C2A51-6B0E-4C77-9A2D-5E1F0B7C4D93}
AppName=SMT-FAI
AppVersion={#AppVersion}
AppVerName=SMT-FAI {#AppVersion}
AppPublisher=SMT-FAI
AppPublisherURL=https://github.com/Marginal-Z/FAI-SMT
AppUpdatesURL=https://github.com/Marginal-Z/FAI-SMT/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\SMT-FAI
UsePreviousAppDir=yes
DisableDirPage=auto
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
#if AppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
OutputDir=..\..\dist
OutputBaseFilename=SMT-FAI-{#AppVersion}-windows-{#AppArch}-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\smt_fai.exe
UninstallDisplayName=SMT-FAI
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=force
RestartApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Old Flutter assets are replaced as a whole so nothing stale is left behind.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\SMT-FAI"; Filename: "{app}\smt_fai.exe"
Name: "{autodesktop}\SMT-FAI"; Filename: "{app}\smt_fai.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\smt_fai.exe"; Description: "{cm:LaunchProgram,SMT-FAI}"; Flags: nowait postinstall skipifsilent
; Silent upgrades started by the in-app updater restart the app themselves.
Filename: "{app}\smt_fai.exe"; Flags: nowait; Check: WizardSilent
