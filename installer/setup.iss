#define MyAppName "FULLPOS"

; Permite override desde línea de comandos:
;   ISCC setup.iss /DMyAppVersion=1.2.3+4
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

; Para el nombre del instalador, evitamos caracteres problemáticos como '+'
#define MyAppVersionFile StringChange(MyAppVersion, "+", "_")

#define MyAppPublisher "FULLTECH SRL"
#define MyAppExeName "fullpos.exe"

; Carpeta de release de Flutter Windows (se genera con: flutter build windows --release)
#define MyAppSourceDir "..\build\windows\x64\runner\Release"

; Branding (ajusta estos paths si cambias los archivos)
; Icono del instalador (lo que ves en el .exe del Setup)
#define BrandSetupIcon "..\assets\imagen\app_icon.ico"

; Imágenes del wizard (Inno Setup suele trabajar mejor con PNG/BMP aquí)
#define BrandWizardImage "..\assets\imagen\lonchericon.png"
#define BrandWizardSmallImage "..\assets\imagen\lonchericon.png"

#define SupportPhone "8295344286"
#define SupportWhatsAppURL "https://wa.me/18295344286?text=Hola%20FULLTECH%20SRL,%20necesito%20soporte%20o%20instalacion%20de%20FULLPOS."

[Setup]
; ⚠️ AppId NUEVO para FULLPOS
AppId={{A7F1C9D4-2E91-4C3B-8F6A-1E9D7C5B2A11}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}

; ✅ Branding (icono + logo)
SetupIconFile={#BrandSetupIcon}
WizardImageFile={#BrandWizardImage}
WizardSmallImageFile={#BrandWizardSmallImage}

DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; Generar el instalador dentro de installer/output (evita la carpeta dist)
OutputDir=output
OutputBaseFilename={#MyAppName}_Setup_{#MyAppVersionFile}
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern

; ✅ CONTRATO OBLIGATORIO (EULA)
LicenseFile=license_fullpos.txt

; ✅ Windows mínimo recomendado
MinVersion=10.0

[Tasks]
Name: "desktopicon"; Description: "Crear icono en el escritorio"; GroupDescription: "Iconos:"; Flags: unchecked

[Files]
; Copiar TODO el release de Windows (exe + dll + data + flutter_assets + plugins)
; Importante: para Flutter Windows NO basta con el .exe; también se requiere la carpeta data/ y DLLs.
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs

; Redistributables
Source: "redist\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "redist\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
; Acceso principal
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"

; Abrir carpeta de instalación
Name: "{group}\Abrir carpeta de instalación"; Filename: "{app}"; WorkingDir: "{app}"

; Soporte por WhatsApp
Name: "{group}\Soporte por WhatsApp ({#SupportPhone})"; Filename: "{#SupportWhatsAppURL}"

; Acceso en escritorio (opcional)
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; VC++ (solo si falta)
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Instalando Microsoft Visual C++ Runtime..."; Flags: waituntilterminated; Check: NeedsVCRedist

; WebView2 (solo si falta)
Filename: "{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; Parameters: "/silent /install"; StatusMsg: "Instalando Microsoft WebView2 Runtime..."; Flags: waituntilterminated; Check: NeedsWebView2

; Abrir FULLPOS
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent

; WhatsApp soporte (opcional al final)
Filename: "{#SupportWhatsAppURL}"; Description: "Soporte / Instalación por WhatsApp ({#SupportPhone})"; Flags: postinstall shellexec skipifsilent unchecked

[Code]
var
  SupportAccentLabel: TNewStaticText;

function RGB(const R, G, B: Integer): Integer;
begin
  { Inno Setup Pascal Script no siempre incluye RGB(); esto crea un COLORREF (0x00BBGGRR) }
  Result := (R and $FF) or ((G and $FF) shl 8) or ((B and $FF) shl 16);
end;

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
        if Pos(Lowercase(DisplayNamePart), Lowercase(DisplayName)) > 0 then
        begin
          Result := True;
          Exit;
        end;
    end;
  end;

  if RegGetSubkeyNames(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', SubKeys) then
  begin
    for I := 0 to GetArrayLength(SubKeys)-1 do
    begin
      KeyName := 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' + SubKeys[I];
      if RegQueryStringValue(HKLM, KeyName, 'DisplayName', DisplayName) then
        if Pos(Lowercase(DisplayNamePart), Lowercase(DisplayName)) > 0 then
        begin
          Result := True;
          Exit;
        end;
    end;
  end;
end;

function FileExistsInSystemDirs(const FileName: string): Boolean; forward;
function VcRuntimeFilesPresent(): Boolean; forward;

function NeedsVCRedist(): Boolean;
var
  Installed: Cardinal;
begin
  { Verificación directa de DLLs: evita falsos positivos (p.ej. runtime viejo instalado sin VCRUNTIME140_1.dll) }
  if not VcRuntimeFilesPresent() then
  begin
    Result := True;
    Exit;
  end;

  { Clave oficial de VC++ runtime x64 (útil como señal adicional) }
  if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
  begin
    Result := Installed <> 1;
    Exit;
  end;

  { Fallback por nombre en desinstalador }
  Result := not IsInstalledByDisplayName('Microsoft Visual C++ 2015-2022 Redistributable (x64)');
end;

function FileExistsInSystemDirs(const FileName: string): Boolean;
var
  P: string;
begin
  P := ExpandConstant('{sys}\' + FileName);
  Result := FileExists(P);

  // En instalador 32-bit en Windows 64-bit, la constante sys puede apuntar a SysWOW64;
  // revisamos también System32 vía sysnative.
  if (not Result) and IsWin64 then
  begin
    P := ExpandConstant('{sysnative}\' + FileName);
    Result := FileExists(P);
  end;
end;

function VcRuntimeFilesPresent(): Boolean;
begin
  { FULLPOS (Flutter Windows x64) típicamente requiere estas DLLs del VC++ Runtime }
  Result :=
    FileExistsInSystemDirs('VCRUNTIME140.dll') and
    FileExistsInSystemDirs('VCRUNTIME140_1.dll') and
    FileExistsInSystemDirs('MSVCP140.dll');
end;

function NeedsWebView2(): Boolean;
var
  Pv: string;
begin
  { Método robusto: clave oficial de EdgeUpdate para WebView2 Runtime }
  if RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7C265-6C31-4F67-BB8C-6D5F8A2A321A}', 'pv', Pv) then
  begin
    Result := Trim(Pv) = '';
    Exit;
  end;

  if RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F1E7C265-6C31-4F67-BB8C-6D5F8A2A321A}', 'pv', Pv) then
  begin
    Result := Trim(Pv) = '';
    Exit;
  end;

  { Fallback por nombre en desinstalador }
  Result := not IsInstalledByDisplayName('Microsoft Edge WebView2 Runtime');
end;

procedure InitializeWizard();
begin
  { Paleta FULLPOS: azul / blanco / negro / rojo }
  { Nota: los botones y algunos controles siguen el tema de Windows. }
  WizardForm.Color := clWhite;
  { Azul tomado del logo (aprox): #0030B0 }
  WizardForm.WelcomeLabel1.Font.Color := RGB(0, 48, 176);
  WizardForm.WelcomeLabel1.Font.Style := [fsBold];
  WizardForm.WelcomeLabel2.Font.Color := clBlack;

  { ✅ Bienvenida PRO (esto sí existe y no da error) }
  WizardForm.WelcomeLabel1.Caption := 'Bienvenido a ' + ExpandConstant('{#MyAppName}');
  WizardForm.WelcomeLabel2.Caption :=
    'Este asistente instalará ' + ExpandConstant('{#MyAppName}') + ' en su computadora.' + #13#10#13#10 +
    'Haga clic en "Siguiente" para continuar.';

  { Acento rojo para soporte }
  if SupportAccentLabel = nil then
  begin
    SupportAccentLabel := TNewStaticText.Create(WizardForm);
    SupportAccentLabel.Parent := WizardForm.WelcomePage;
    SupportAccentLabel.Left := WizardForm.WelcomeLabel2.Left;
    SupportAccentLabel.Top := WizardForm.WelcomeLabel2.Top + WizardForm.WelcomeLabel2.Height + ScaleY(6);
    SupportAccentLabel.AutoSize := True;
    SupportAccentLabel.Font.Style := [fsBold];
    SupportAccentLabel.Font.Color := RGB(200, 0, 0);
    SupportAccentLabel.Caption := 'Soporte e instalación: WhatsApp ' + ExpandConstant('{#SupportPhone}');
  end;
end;
