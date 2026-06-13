#define MyAppName "FullPOS"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef MyAppBuild
  #define MyAppBuild "1"
#endif
#define MyAppPublisher "FullTech SRL"
#define MyAppExeName "fullpos.exe"
#define MyAppSourceDir "..\build\windows\x64\runner\Release"
#define MySetupIcon "assets\fullpos.ico"

[Setup]
AppId={{A7F1C9D4-2E91-4C3B-8F6A-1E9D7C5B2A11}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\FullPOS
DefaultGroupName=FullPOS
DisableProgramGroupPage=yes
UsePreviousAppDir=yes

OutputDir=output
OutputBaseFilename=FullPOS-Setup

Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#MySetupIcon}
LicenseFile=license_fullpos.txt

PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

CloseApplications=yes
CloseApplicationsFilter={#MyAppExeName}
RestartApplications=yes

Uninstallable=yes
CreateUninstallRegKey=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}

VersionInfoVersion={#MyAppVersion}.{#MyAppBuild}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Instalador oficial de FullPOS
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCopyright=Copyright (C) 2026 FullTech SRL

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"; Flags: checkedonce

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "redist\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "redist\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{autoprograms}\FullPOS"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\FullPOS"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Comprobando Microsoft Visual C++ Runtime..."; Flags: waituntilterminated; Check: NeedsVCRedist
Filename: "{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; Parameters: "/silent /install"; StatusMsg: "Comprobando Microsoft WebView2 Runtime..."; Flags: waituntilterminated; Check: NeedsWebView2
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir FullPOS"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[Code]
function FileExistsInSystemDirs(const FileName: string): Boolean;
begin
  Result := FileExists(ExpandConstant('{sys}\' + FileName));
  if (not Result) and IsWin64 then
    Result := FileExists(ExpandConstant('{sysnative}\' + FileName));
end;

function NeedsVCRedist(): Boolean;
var
  Installed: Cardinal;
begin
  Result :=
    not FileExistsInSystemDirs('VCRUNTIME140.dll') or
    not FileExistsInSystemDirs('VCRUNTIME140_1.dll') or
    not FileExistsInSystemDirs('MSVCP140.dll');

  if not Result then
    if RegQueryDWordValue(
      HKLM,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Installed',
      Installed
    ) then
      Result := Installed <> 1;
end;

function NeedsWebView2(): Boolean;
var
  Version: string;
begin
  Result := True;
  if RegQueryStringValue(
    HKLM,
    'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7C265-6C31-4F67-BB8C-6D5F8A2A321A}',
    'pv',
    Version
  ) then
  begin
    Result := Trim(Version) = '';
    Exit;
  end;

  if RegQueryStringValue(
    HKLM,
    'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F1E7C265-6C31-4F67-BB8C-6D5F8A2A321A}',
    'pv',
    Version
  ) then
    Result := Trim(Version) = '';
end;
