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
    'C:\Program Files\Inno Setup 7\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 7\ISCC.exe',
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
$packScript = Join-Path $projectRoot 'tool\pack_windows_release.ps1'

if (!(Test-Path $pubspec)) { throw "No existe pubspec.yaml en: $pubspec" }
if (!(Test-Path $setupIss)) { throw "No existe setup.iss en: $setupIss" }
if (!(Test-Path $packScript)) { throw "No existe pack_windows_release.ps1 en: $packScript" }

$versionLine = Select-String -Path $pubspec -Pattern '^version:\s*(.+)\s*$' -ErrorAction Stop | Select-Object -First 1
if (-not $versionLine) { throw 'No se encontró la línea version: en pubspec.yaml' }

$version = $versionLine.Matches[0].Groups[1].Value.Trim()
if ([string]::IsNullOrWhiteSpace($version)) { throw 'La versión en pubspec.yaml está vacía.' }

$safeVersion = $version.Replace('+','_')
$out = Join-Path $projectRoot ("installer\\output\\FULLPOS_Setup_{0}.exe" -f $safeVersion)

Write-Host "Version detectada: $version" -ForegroundColor Cyan

Push-Location $projectRoot
try {
  Write-Host 'flutter clean...' -ForegroundColor Cyan
  flutter clean
  Assert-LastExitCode 'flutter clean'

  Write-Host 'flutter pub get...' -ForegroundColor Cyan
  flutter pub get
  Assert-LastExitCode 'flutter pub get'

  Write-Host 'flutter build windows --release...' -ForegroundColor Cyan
  flutter build windows --release
  Assert-LastExitCode 'flutter build windows --release'

  $releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
  $updaterSource = Join-Path $projectRoot 'tool\fullpos_updater.dart'
  $updaterExe = Join-Path $releaseDir 'FullPOSUpdater.exe'
  if (!(Test-Path $updaterSource)) { throw "No existe fullpos_updater.dart en: $updaterSource" }

  Write-Host 'Compilando FullPOSUpdater.exe...' -ForegroundColor Cyan
  dart compile exe $updaterSource -o $updaterExe
  Assert-LastExitCode 'dart compile exe FullPOSUpdater'

  $required = @(
    (Join-Path $releaseDir 'fullpos.exe'),
    $updaterExe,
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

  Write-Host 'Empaquetando release distribuible...' -ForegroundColor Cyan
  & powershell -ExecutionPolicy Bypass -File $packScript
  Assert-LastExitCode 'pack_windows_release.ps1'

  $iscc = Find-Iscc
  Write-Host "Compilando instalador con ISCC: $iscc" -ForegroundColor Cyan

  if (Test-Path $out) {
    Write-Host "Eliminando instalador anterior: $out" -ForegroundColor DarkGray
    Remove-Item -Force $out
  }

  Push-Location (Join-Path $projectRoot 'installer')
  try {
    & $iscc 'setup.iss' ("/DMyAppVersion=$version") | Out-Host
    Assert-LastExitCode 'ISCC setup.iss'
  }
  finally {
    Pop-Location
  }

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
