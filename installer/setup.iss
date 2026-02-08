#define MyAppName "FULLPOS"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "FULLTECH SRL"
#define MyAppExeName "fullpos.exe"

; Branding (ajusta estos paths si cambias los archivos)
#define BrandSetupIcon "..\assets\imagen\fullpos_icon (1).ico"
#define BrandWizardImage "..\assets\imagen\windowlogo.png"
#define BrandWizardSmallImage "..\assets\imagen\lonchericon.png"

#define SupportPhone "8295319442"
#define SupportWhatsAppURL "https://wa.me/18295319442?text=Hola%20FULLTECH%20SRL,%20necesito%20soporte%20o%20instalacion%20de%20FULLPOS."

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
OutputDir=output
OutputBaseFilename={#MyAppName}_Setup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
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
; Copiar TODA la carpeta Release (exe + dll + data + plugins)
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

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

function NeedsVCRedist(): Boolean;
begin
  Result := not IsInstalledByDisplayName('Microsoft Visual C++ 2015-2022 Redistributable (x64)');
end;

function NeedsWebView2(): Boolean;
begin
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
