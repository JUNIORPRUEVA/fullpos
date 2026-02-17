$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$distDir = Join-Path $projectRoot 'dist'
$outFolder = Join-Path $distDir 'FULLPOS_Windows_Release'
$outZip = Join-Path $distDir 'FULLPOS_Windows_Release.zip'

if (!(Test-Path $releaseDir)) {
  throw "No existe la carpeta Release: $releaseDir. Ejecuta: flutter build windows --release"
}

New-Item -ItemType Directory -Force -Path $distDir | Out-Null

if (Test-Path $outFolder) {
  Remove-Item -Recurse -Force $outFolder
}
if (Test-Path $outZip) {
  Remove-Item -Force $outZip
}

Copy-Item -Recurse -Force -Path (Join-Path $releaseDir '*') -Destination $outFolder

# Validaciones mínimas: el exe, flutter_windows.dll y flutter_assets deben ir juntos
$exe = Join-Path $outFolder 'fullpos.exe'
$dll = Join-Path $outFolder 'flutter_windows.dll'
$assets = Join-Path $outFolder 'flutter_assets'
if (!(Test-Path $exe)) { throw "Falta fullpos.exe en $outFolder" }
if (!(Test-Path $dll)) { throw "Falta flutter_windows.dll en $outFolder" }
if (!(Test-Path $assets)) { throw "Falta carpeta flutter_assets/ en $outFolder" }

Compress-Archive -Path (Join-Path $outFolder '*') -DestinationPath $outZip

Write-Host "OK: empaquetado creado" -ForegroundColor Green
Write-Host "Carpeta: $outFolder"
Write-Host "ZIP:     $outZip"
Write-Host "Ejecuta SIEMPRE desde la carpeta (no copies solo el .exe)."