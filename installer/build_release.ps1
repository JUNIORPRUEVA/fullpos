$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-ExitCode {
  param([Parameter(Mandatory = $true)][string]$Step)

  if ($LASTEXITCODE -ne 0) {
    throw "$Step fallo con codigo de salida $LASTEXITCODE."
  }
}

function Find-Iscc {
  $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 7\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 7\ISCC.exe'
  )

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  throw 'No se encontro ISCC.exe. Instala Inno Setup 6 o agrega ISCC.exe al PATH.'
}

function Stop-ProjectBuildProcesses {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)

  $buildRoot = Join-Path $ProjectRoot 'build'
  $processes = Get-Process -Name 'fullpos' -ErrorAction SilentlyContinue
  foreach ($process in $processes) {
    $processPath = $process.Path
    if ([string]::IsNullOrWhiteSpace($processPath)) {
      continue
    }
    if (-not $processPath.StartsWith(
      $buildRoot + [System.IO.Path]::DirectorySeparatorChar,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
      continue
    }

    Write-Host "Cerrando copia de desarrollo: $processPath" -ForegroundColor Yellow
    if ($process.MainWindowHandle -ne 0) {
      $null = $process.CloseMainWindow()
      if ($process.WaitForExit(5000)) {
        continue
      }
    }
    Stop-Process -Id $process.Id -Force
    $process.WaitForExit(5000)
  }
}

function Get-ReleaseDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ExeName
  )

  $windowsBuild = Join-Path $ProjectRoot 'build\windows'
  $matches = @(
    Get-ChildItem -LiteralPath $windowsBuild -Directory -Recurse |
      Where-Object {
        $_.Name -eq 'Release' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName $ExeName))
      }
  )

  if ($matches.Count -ne 1) {
    throw "Se esperaba una carpeta Release con $ExeName y se encontraron $($matches.Count)."
  }

  return $matches[0].FullName
}

$installerDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $installerDir
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$setupScript = Join-Path $installerDir 'fullpos_setup.iss'
$outputDir = Join-Path $installerDir 'output'
$installerPath = Join-Path $outputDir 'FullPOS-Setup.exe'
$checksumPath = Join-Path $outputDir 'FullPOS-Setup.sha256.txt'
$releaseInfoPath = Join-Path $outputDir 'RELEASE_INFO.md'
$exeName = 'fullpos.exe'

$versionMatch = Select-String -LiteralPath $pubspecPath -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$' |
  Select-Object -First 1
if (-not $versionMatch) {
  throw 'La version de pubspec.yaml no tiene el formato esperado: X.Y.Z+BUILD.'
}

$appVersion = $versionMatch.Matches[0].Groups[1].Value
$buildNumber = $versionMatch.Matches[0].Groups[2].Value
$packageVersion = "$appVersion+$buildNumber"

Push-Location $projectRoot
try {
  Stop-ProjectBuildProcesses -ProjectRoot $projectRoot

  Write-Host 'Ejecutando flutter clean...' -ForegroundColor Cyan
  flutter clean
  Assert-ExitCode 'flutter clean'

  Write-Host 'Ejecutando flutter pub get...' -ForegroundColor Cyan
  flutter pub get
  Assert-ExitCode 'flutter pub get'

  Write-Host 'Ejecutando flutter analyze...' -ForegroundColor Cyan
  flutter analyze --no-fatal-warnings --no-fatal-infos
  Assert-ExitCode 'flutter analyze'

  Write-Host 'Compilando FullPOS para Windows Release...' -ForegroundColor Cyan
  flutter build windows --release `
    --build-name $appVersion `
    --build-number $buildNumber `
    --dart-define "FULLPOS_APP_VERSION=$packageVersion" `
    --dart-define "APP_VERSION=$packageVersion"
  Assert-ExitCode 'flutter build windows --release'

  $releaseDir = Get-ReleaseDirectory -ProjectRoot $projectRoot -ExeName $exeName
  $requiredPaths = @(
    (Join-Path $releaseDir $exeName),
    (Join-Path $releaseDir 'flutter_windows.dll'),
    (Join-Path $releaseDir 'data'),
    (Join-Path $releaseDir 'data\flutter_assets'),
    (Join-Path $releaseDir 'data\icudtl.dat'),
    (Join-Path $releaseDir 'data\app.so')
  )
  foreach ($requiredPath in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
      throw "Build incompleto: falta $requiredPath."
    }
  }

  $iscc = Find-Iscc
  Write-Host "Compilando instalador con $iscc..." -ForegroundColor Cyan
  & $iscc $setupScript "/DMyAppVersion=$appVersion" "/DMyAppBuild=$buildNumber"
  Assert-ExitCode 'Compilacion Inno Setup'

  if (-not (Test-Path -LiteralPath $installerPath)) {
    throw "No se genero el instalador esperado: $installerPath."
  }

  $stream = [System.IO.File]::OpenRead($installerPath)
  try {
    if (($stream.ReadByte() -ne 0x4D) -or ($stream.ReadByte() -ne 0x5A)) {
      throw 'El instalador generado no tiene una cabecera PE valida.'
    }
  }
  finally {
    $stream.Dispose()
  }

  $hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
  @(
    'FILENAME: FullPOS-Setup.exe'
    "VERSION: $appVersion"
    "SHA256: $hash"
  ) | Set-Content -LiteralPath $checksumPath -Encoding UTF8

  @"
# FullPOS para Windows v$appVersion

## Archivo

``FullPOS-Setup.exe``

## Version

``$appVersion``

## Build

``$buildNumber``

## SHA-256

``$hash``

## Requisitos

- Windows 10 o superior
- Arquitectura x64
- Permisos de administrador para instalar

## Instalacion

1. Descarga ``FullPOS-Setup.exe``.
2. Cierra FullPOS si esta abierto.
3. Ejecuta el instalador.
4. Autoriza los permisos de Windows.
5. Completa la instalacion.
6. Abre FullPOS.

## Actualizacion

El instalador puede ejecutarse encima de una instalacion anterior.

Los datos del negocio, la configuracion y la licencia se conservan porque se almacenan fuera de la carpeta del programa.

## Cambios

- Primera version oficial de FullPOS para Windows.
- Gestion de ventas.
- Gestion de inventario.
- Clientes y cotizaciones.
- Apertura y cierre de turnos.
- Reportes.
- FullPOS Cloud.
- Compatibilidad con FullPOS Owner.
"@ | Set-Content -LiteralPath $releaseInfoPath -Encoding UTF8

  $relativeRelease = [System.IO.Path]::GetRelativePath($projectRoot, $releaseDir)
  Write-Host ''
  Write-Host 'Release de FullPOS generado correctamente.' -ForegroundColor Green
  Write-Host "Version: $appVersion"
  Write-Host "Build: $buildNumber"
  Write-Host "Ejecutable: $relativeRelease\$exeName"
  Write-Host "Instalador: installer\output\FullPOS-Setup.exe"
  Write-Host "SHA-256: $hash"
}
finally {
  Pop-Location
}
