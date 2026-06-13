$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RequiredText {
  param(
    [Parameter(Mandatory = $true)]$Payload,
    [Parameter(Mandatory = $true)][string]$Field
  )

  $value = [string]$Payload.$Field
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "El campo '$Field' es obligatorio en update_payload.json."
  }
  return $value.Trim()
}

function Get-RequiredPositiveInteger {
  param(
    [Parameter(Mandatory = $true)]$Payload,
    [Parameter(Mandatory = $true)][string]$Field
  )

  $parsed = 0L
  if (
    -not [long]::TryParse([string]$Payload.$Field, [ref]$parsed) -or
    $parsed -le 0
  ) {
    throw "El campo '$Field' debe ser un entero positivo."
  }
  return $parsed
}

$installerDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $installerDir
$payloadPath = Join-Path $projectRoot 'installer\output\update_payload.json'
$backendUrl = 'https://fullpos-backend-fullpos-backend.onqyr1.easypanel.host/api/app-updates/fullpos/windows'

if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
  throw "No existe el archivo de política: $payloadPath. Ejecuta primero .\installer\build_release.ps1."
}

try {
  $payload = Get-Content -LiteralPath $payloadPath -Raw | ConvertFrom-Json
}
catch {
  throw 'update_payload.json no contiene JSON válido.'
}

$projectCode = Get-RequiredText -Payload $payload -Field 'projectCode'
$platform = Get-RequiredText -Payload $payload -Field 'platform'
if ($projectCode -cne 'fullpos' -or $platform -cne 'windows') {
  throw "La política debe pertenecer exactamente a fullpos/windows."
}

$version = Get-RequiredText -Payload $payload -Field 'version'
if ($version -notmatch '^\d+\.\d+\.\d+$') {
  throw "El campo 'version' debe tener el formato X.Y.Z."
}
$buildNumber = Get-RequiredPositiveInteger -Payload $payload -Field 'buildNumber'
$installerUrl = Get-RequiredText -Payload $payload -Field 'installerUrl'
$installerFilename = Get-RequiredText -Payload $payload -Field 'installerFilename'
$installerSize = Get-RequiredPositiveInteger -Payload $payload -Field 'installerSizeBytes'
$sha256 = Get-RequiredText -Payload $payload -Field 'sha256'
if ($sha256 -notmatch '^[0-9a-fA-F]{64}$') {
  throw "El campo 'sha256' debe contener exactamente 64 caracteres hexadecimales."
}
if ($installerFilename -cne 'FullPOS-Setup.exe') {
  throw "El instalador debe llamarse exactamente FullPOS-Setup.exe."
}
if ($installerUrl -notmatch '^https://') {
  throw "El campo 'installerUrl' debe usar HTTPS."
}
if ($null -eq $payload.enabled -or $payload.enabled -isnot [bool]) {
  throw "El campo 'enabled' debe ser booleano."
}
if ($null -eq $payload.mandatory -or $payload.mandatory -isnot [bool]) {
  throw "El campo 'mandatory' debe ser booleano."
}

$releaseKey = [string]$env:FULLPOS_RELEASE_API_KEY
if ([string]::IsNullOrWhiteSpace($releaseKey)) {
  throw 'FULLPOS_RELEASE_API_KEY no está configurada en esta sesión de PowerShell.'
}
$releaseKey = $releaseKey.Trim()
if ($releaseKey.Length -lt 32) {
  throw 'FULLPOS_RELEASE_API_KEY debe contener al menos 32 caracteres.'
}

$mandatoryText = if ($payload.mandatory -eq $true) { 'Sí' } else { 'No' }
$minimumVersion = Get-RequiredText -Payload $payload -Field 'minimumSupportedVersion'
$minimumBuild = Get-RequiredPositiveInteger -Payload $payload -Field 'minimumSupportedBuild'

Write-Host ''
Write-Host 'Política de actualización preparada' -ForegroundColor Cyan
Write-Host "Versión: $version"
Write-Host "Build: $buildNumber"
Write-Host "Obligatoria: $mandatoryText"
Write-Host "Mínimo soportado: $minimumVersion+$minimumBuild"
Write-Host "Instalador: $installerFilename"
Write-Host "URL: $installerUrl"
Write-Host "Tamaño: $installerSize bytes"
Write-Host "Backend: $backendUrl"
Write-Host ''

$confirmation = Read-Host 'Escribe PUBLICAR para continuar'
if ($confirmation -cne 'PUBLICAR') {
  Write-Host 'Publicación cancelada. No se realizó ningún cambio.' -ForegroundColor Yellow
  exit 0
}

$headers = @{
  'X-Release-Key' = $releaseKey
}

try {
  $response = Invoke-RestMethod `
    -Method Put `
    -Uri $backendUrl `
    -Headers $headers `
    -Body (Get-Content -LiteralPath $payloadPath -Raw) `
    -ContentType 'application/json'

  Write-Host ''
  Write-Host 'Política publicada correctamente.' -ForegroundColor Green
  $publishedVersion = if ($response.latestVersion) {
    $response.latestVersion
  } elseif ($response.version) {
    $response.version
  } else {
    $version
  }
  $publishedBuild = if ($response.latestBuild) {
    $response.latestBuild
  } elseif ($response.buildNumber) {
    $response.buildNumber
  } else {
    $buildNumber
  }
  Write-Host "Versión publicada: $publishedVersion"
  Write-Host "Build publicado: $publishedBuild"
  Write-Host 'El instalador no fue subido a GitHub por este script.'
}
catch {
  $statusCode = $null
  if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
    $statusCode = [int]$_.Exception.Response.StatusCode
  }

  $safeMessage = switch ($statusCode) {
    400 { 'El backend rechazó la política por datos inválidos.' }
    401 { 'La llave de publicación no fue aceptada.' }
    403 { 'La publicación no está autorizada.' }
    404 { 'No se encontró el endpoint de publicación.' }
    429 { 'Se excedió el límite de intentos. Espera y vuelve a intentarlo.' }
    { $_ -ge 500 } { 'El backend no pudo procesar la publicación.' }
    default { 'No se pudo conectar con el backend de FullPOS.' }
  }
  throw $safeMessage
}
