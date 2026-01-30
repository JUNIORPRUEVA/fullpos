#define MyAppName "LOS NILKAS POS"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "LOS NILKAS"
#define MyAppExeName "nilkas.exe"

[Setup]
AppId={{9B0B3B2A-7D57-4A0C-9D2B-5C8A9B6B1F10}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=output
OutputBaseFilename={#MyAppName}_Setup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
DisableProgramGroupPage=yes
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Crear icono en el escritorio"; GroupDescription: "Iconos:"; Flags: unchecked

[Files]
; Copiar TODA la carpeta Release (exe + dll + data + plugins)
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Redistributables
Source: "redist\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "redist\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; VC++ (solo si falta)
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; \
  StatusMsg: "Instalando Microsoft Visual C++ Runtime..."; Flags: waituntilterminated; Check: NeedsVCRedist

; WebView2 (solo si falta)
Filename: "{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; Parameters: "/silent /install"; \
  StatusMsg: "Instalando Microsoft WebView2 Runtime..."; Flags: waituntilterminated; Check: NeedsWebView2

; Abrir app al final
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
function IsInstalledByDisplayName(const DisplayNamePart: string): Boolean;
var
  SubKeys: TArrayOfString;
  I: Integer;
  KeyName: string;
  DisplayName: string;
begin
  Result := False;

  if RegGetSubkeyNames(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', SubKeys) then
  begin
    for I := 0 to GetArrayLength(SubKeys)-1 do
    begin
      KeyName := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + SubKeys[I];
      if RegQueryStringValue(HKLM, KeyName, 'DisplayName', DisplayName) then
        if Pos(Lowercase(DisplayNamePart), Lowercase(DisplayName)) > 0 then begin Result := True; Exit; end;
    end;
  end;

  if RegGetSubkeyNames(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', SubKeys) then
  begin
    for I := 0 to GetArrayLength(SubKeys)-1 do
    begin
      KeyName := 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' + SubKeys[I];
      if RegQueryStringValue(HKLM, KeyName, 'DisplayName', DisplayName) then
        if Pos(Lowercase(DisplayNamePart), Lowercase(DisplayName)) > 0 then begin Result := True; Exit; end;
    end;
  end;
end;

function NeedsVCRedist(): Boolean;
begin
  Result := not IsInstalledByDisplayName('Microsoft Visual C++ 2015-2022 Redistributable (x64)');
end;

function NeedsWebView2(): Boolean;
begin
  Result := not IsInstalledByDisplayName('Microsoft Edge WebView2 Runtime');
end;
