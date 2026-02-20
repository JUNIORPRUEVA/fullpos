$ErrorActionPreference = 'Stop'

function Assert-LastExitCode {
  param(
    [Parameter(Mandatory=$true)][string]$StepName
  )
  if ($LASTEXITCODE -ne 0) {
    throw "$StepName falló (exit code: $LASTEXITCODE)."
  }
}

function Find-Iscc {
  $cmd = Get-Command -Name iscc.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidates = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 5\ISCC.exe',
    'C:\Program Files\Inno Setup 5\ISCC.exe'
  )

  foreach ($p in $candidates) {
    if (Test-Path $p) { return $p }
  }

  throw 'No se encontró ISCC.exe (Inno Setup). Instala Inno Setup 6 o agrega ISCC al PATH.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $projectRoot 'pubspec.yaml'
$setupIss = Join-Path $projectRoot 'installer\setup.iss'

if (!(Test-Path $pubspec)) { throw "No existe pubspec.yaml en: $pubspec" }
if (!(Test-Path $setupIss)) { throw "No existe setup.iss en: $setupIss" }

$versionLine = Select-String -Path $pubspec -Pattern '^version:\s*(.+)\s*$' -ErrorAction Stop | Select-Object -First 1
if (-not $versionLine) { throw 'No se encontró la línea version: en pubspec.yaml' }

$version = $versionLine.Matches[0].Groups[1].Value.Trim()
if ([string]::IsNullOrWhiteSpace($version)) { throw 'La versión en pubspec.yaml está vacía.' }

Write-Host "Version detectada: $version" -ForegroundColor Cyan

Push-Location $projectRoot
try {
  Write-Host 'flutter pub get...' -ForegroundColor Cyan
  flutter pub get
  Assert-LastExitCode 'flutter pub get'

  Write-Host 'flutter build windows --release...' -ForegroundColor Cyan
  flutter build windows --release
  Assert-LastExitCode 'flutter build windows --release'

  $releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
  $required = @(
    (Join-Path $releaseDir 'fullpos.exe'),
    (Join-Path $releaseDir 'flutter_windows.dll'),
    (Join-Path $releaseDir 'data'),
    (Join-Path $releaseDir 'data\flutter_assets'),
    (Join-Path $releaseDir 'data\icudtl.dat')
  )
  foreach ($p in $required) {
    if (!(Test-Path $p)) {
      throw "Build incompleto: falta '$p'."
    }
  }

  $iscc = Find-Iscc
  Write-Host "Compilando instalador con ISCC: $iscc" -ForegroundColor Cyan

  Push-Location (Join-Path $projectRoot 'installer')
  try {
    & $iscc 'setup.iss' ("/DMyAppVersion=$version") | Out-Host
  }
  finally {
    Pop-Location
  }

  $safeVersion = $version.Replace('+','_')
  $out = Join-Path $projectRoot ("installer\\output\\FULLPOS_Setup_{0}.exe" -f $safeVersion)
  if (Test-Path $out) {
    Write-Host "OK: Instalador listo: $out" -ForegroundColor Green
  } else {
    Write-Host 'Compilación finalizada, pero no se encontró el .exe esperado en installer/output.' -ForegroundColor Yellow
    Get-ChildItem -Path (Join-Path $projectRoot 'installer\output') -Filter 'FULLPOS_Setup_*.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
  }
}
finally {
  Pop-Location
}
