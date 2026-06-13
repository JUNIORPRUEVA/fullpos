$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-ExitCode {
  param([Parameter(Mandatory = $true)][string]$Step)

  if ($LASTEXITCODE -ne 0) {
    throw "$Step fallo con codigo de salida $LASTEXITCODE."
  }
}

function Parse-PackageVersion {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$Source
  )

  $match = [regex]::Match(
    $Value.Trim(),
    '^(?:version:\s*)?(\d+)\.(\d+)\.(\d+)\+([1-9]\d*)$'
  )
  if (-not $match.Success) {
    throw "La version en $Source debe tener el formato X.Y.Z+BUILD, por ejemplo: version: 1.0.2+6."
  }

  return [pscustomobject]@{
    Version = "$($match.Groups[1].Value).$($match.Groups[2].Value).$($match.Groups[3].Value)"
    Build = [int]$match.Groups[4].Value
    Major = [int]$match.Groups[1].Value
    Minor = [int]$match.Groups[2].Value
    Patch = [int]$match.Groups[3].Value
  }
}

function Parse-SemanticVersion {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$FieldName
  )

  $match = [regex]::Match($Value.Trim(), '^v?(\d+)\.(\d+)\.(\d+)$')
  if (-not $match.Success) {
    throw "$FieldName debe tener el formato X.Y.Z, por ejemplo: 1.0.1."
  }

  return [pscustomobject]@{
    Version = "$($match.Groups[1].Value).$($match.Groups[2].Value).$($match.Groups[3].Value)"
    Major = [int]$match.Groups[1].Value
    Minor = [int]$match.Groups[2].Value
    Patch = [int]$match.Groups[3].Value
  }
}

function Compare-VersionBuild {
  param(
    [Parameter(Mandatory = $true)]$Left,
    [Parameter(Mandatory = $true)]$Right
  )

  foreach ($property in @('Major', 'Minor', 'Patch', 'Build')) {
    if ($Left.$property -lt $Right.$property) { return -1 }
    if ($Left.$property -gt $Right.$property) { return 1 }
  }
  return 0
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

function Get-PreviousVersion {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$PubspecPath,
    [Parameter(Mandatory = $true)][string]$ExistingInstallerPath,
    [Parameter(Mandatory = $true)]$Current
  )

  $candidates = [System.Collections.Generic.List[object]]::new()

  try {
    $gitRoot = (git -C $ProjectRoot rev-parse --show-toplevel 2>$null).Trim()
    $relativePubspec = [System.IO.Path]::GetRelativePath($gitRoot, $PubspecPath).Replace('\', '/')
    $gitValue = git -C $gitRoot show "HEAD:$relativePubspec" 2>$null |
      Select-String -Pattern '^version:\s*\d+\.\d+\.\d+\+[1-9]\d*\s*$' |
      Select-Object -First 1
    if ($LASTEXITCODE -eq 0 -and $gitValue) {
      $candidate = Parse-PackageVersion -Value $gitValue.Line -Source 'Git HEAD'
      if ((Compare-VersionBuild -Left $candidate -Right $Current) -lt 0) {
        $candidates.Add($candidate)
      }
    }
  }
  catch {
    # Git es solo una fuente opcional para detectar la version anterior.
  }

  if (Test-Path -LiteralPath $ExistingInstallerPath) {
    try {
      $fileVersion = (Get-Item -LiteralPath $ExistingInstallerPath).VersionInfo.FileVersion
      $match = [regex]::Match(
        [string]$fileVersion,
        '^(\d+)\.(\d+)\.(\d+)\.([1-9]\d*)'
      )
      if ($match.Success) {
        $candidate = Parse-PackageVersion `
          -Value "$($match.Groups[1].Value).$($match.Groups[2].Value).$($match.Groups[3].Value)+$($match.Groups[4].Value)" `
          -Source 'instalador existente'
        if ((Compare-VersionBuild -Left $candidate -Right $Current) -lt 0) {
          $candidates.Add($candidate)
        }
      }
    }
    catch {
      # El instalador previo es tambien una fuente opcional.
    }
  }

  if ($candidates.Count -eq 0) {
    return $null
  }

  return $candidates |
    Sort-Object Major, Minor, Patch, Build -Descending |
    Select-Object -First 1
}

function Read-MandatoryChoice {
  while ($true) {
    $value = (Read-Host '¿Esta actualizacion es obligatoria? (si/no)').Trim().ToLowerInvariant()
    if ($value -in @('si', 'sí', 's', 'yes', 'y')) { return $true }
    if ($value -in @('no', 'n')) { return $false }
    Write-Host 'Responde si o no.' -ForegroundColor Yellow
  }
}

function Read-MinimumPolicy {
  param([AllowNull()]$Previous)

  $versionDefault = if ($null -ne $Previous) { $Previous.Version } else { $null }
  $buildDefault = if ($null -ne $Previous) { [string]$Previous.Build } else { $null }

  while ($true) {
    $prompt = if ($versionDefault) {
      "Version minima soportada [$versionDefault]"
    } else {
      'Version minima soportada (X.Y.Z)'
    }
    $inputValue = (Read-Host $prompt).Trim()
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
      if ($versionDefault) {
        $inputValue = $versionDefault
      } else {
        Write-Host 'No se pudo detectar una version anterior. Este valor es obligatorio.' -ForegroundColor Yellow
        continue
      }
    }

    try {
      $parsedVersion = Parse-SemanticVersion -Value $inputValue -FieldName 'La version minima'
      break
    }
    catch {
      Write-Host $_.Exception.Message -ForegroundColor Yellow
    }
  }

  while ($true) {
    $prompt = if ($buildDefault) {
      "Build minimo soportado [$buildDefault]"
    } else {
      'Build minimo soportado'
    }
    $inputValue = (Read-Host $prompt).Trim()
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
      if ($buildDefault) {
        $inputValue = $buildDefault
      } else {
        Write-Host 'No se pudo detectar un build anterior. Este valor es obligatorio.' -ForegroundColor Yellow
        continue
      }
    }

    $parsedBuild = 0
    if ([int]::TryParse($inputValue, [ref]$parsedBuild) -and $parsedBuild -gt 0) {
      break
    }
    Write-Host 'El build minimo debe ser un entero positivo.' -ForegroundColor Yellow
  }

  return [pscustomobject]@{
    Version = $parsedVersion.Version
    Build = $parsedBuild
  }
}

function Read-ReleaseNotes {
  Write-Host ''
  Write-Host 'Escribe las notas de la version, una por linea.' -ForegroundColor Cyan
  Write-Host 'Presiona Enter en una linea vacia cuando hayas terminado.'

  $notes = [System.Collections.Generic.List[string]]::new()
  while ($true) {
    $note = (Read-Host "Nota $($notes.Count + 1)").Trim()
    if ([string]::IsNullOrWhiteSpace($note)) {
      if ($notes.Count -gt 0) { break }
      Write-Host 'Debes agregar al menos una nota.' -ForegroundColor Yellow
      continue
    }
    $notes.Add($note)
  }
  return $notes.ToArray()
}

$installerDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $installerDir
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$setupScript = Join-Path $installerDir 'fullpos_setup.iss'
$outputDir = Join-Path $installerDir 'output'
$installerFilename = 'FullPOS-Setup.exe'
$installerPath = Join-Path $outputDir $installerFilename
$checksumPath = Join-Path $outputDir 'FullPOS-Setup.sha256.txt'
$releaseInfoPath = Join-Path $outputDir 'RELEASE_INFO.md'
$payloadPath = Join-Path $outputDir 'update_payload.json'
$exeName = 'fullpos.exe'

if (-not (Test-Path -LiteralPath $pubspecPath)) {
  throw "No existe pubspec.yaml en $pubspecPath."
}
if (-not (Test-Path -LiteralPath $setupScript)) {
  throw "No existe el script de Inno Setup en $setupScript."
}

$versionLine = Get-Content -LiteralPath $pubspecPath |
  Select-String -Pattern '^version:\s*\d+\.\d+\.\d+\+[1-9]\d*\s*$' |
  Select-Object -First 1
if (-not $versionLine) {
  throw 'pubspec.yaml no contiene una version valida con formato: version: X.Y.Z+BUILD.'
}

$current = Parse-PackageVersion -Value $versionLine.Line -Source 'pubspec.yaml'
$appVersion = $current.Version
$buildNumber = $current.Build
$packageVersion = "$appVersion+$buildNumber"
$githubTag = "v$appVersion"
$githubUrl = "https://github.com/JUNIORPRUEVA/fullpos-releases/releases/download/$githubTag/$installerFilename"

$previous = Get-PreviousVersion `
  -ProjectRoot $projectRoot `
  -PubspecPath $pubspecPath `
  -ExistingInstallerPath $installerPath `
  -Current $current

Write-Host ''
Write-Host 'Preparacion de release FullPOS Windows' -ForegroundColor Cyan
Write-Host "Version detectada: $appVersion"
Write-Host "Build detectado: $buildNumber"
Write-Host "Tag GitHub: $githubTag"
if ($null -ne $previous) {
  Write-Host "Version anterior detectada: $($previous.Version)+$($previous.Build)"
} else {
  Write-Host 'No se detecto de forma segura una version anterior.' -ForegroundColor Yellow
}

$mandatory = Read-MandatoryChoice
$minimumPolicy = Read-MinimumPolicy -Previous $previous
$releaseNotes = Read-ReleaseNotes

$minimumComparable = Parse-PackageVersion `
  -Value "$($minimumPolicy.Version)+$($minimumPolicy.Build)" `
  -Source 'politica minima'
if ((Compare-VersionBuild -Left $minimumComparable -Right $current) -gt 0) {
  throw 'La version minima soportada no puede ser mayor que la version que se publicara.'
}

Push-Location $projectRoot
try {
  Stop-ProjectBuildProcesses -ProjectRoot $projectRoot

  Write-Host ''
  Write-Host 'Ejecutando flutter clean...' -ForegroundColor Cyan
  flutter clean
  Assert-ExitCode 'flutter clean'

  Write-Host 'Ejecutando flutter pub get...' -ForegroundColor Cyan
  flutter pub get
  Assert-ExitCode 'flutter pub get'

  Write-Host 'Ejecutando flutter analyze...' -ForegroundColor Cyan
  flutter analyze --no-fatal-warnings --no-fatal-infos
  Assert-ExitCode 'flutter analyze'

  Write-Host 'Ejecutando flutter test...' -ForegroundColor Cyan
  flutter test
  Assert-ExitCode 'flutter test'

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

  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
  foreach ($generatedPath in @($installerPath, $checksumPath, $releaseInfoPath, $payloadPath)) {
    if (Test-Path -LiteralPath $generatedPath) {
      Remove-Item -LiteralPath $generatedPath -Force
    }
  }

  $iscc = Find-Iscc
  Write-Host "Compilando instalador con $iscc..." -ForegroundColor Cyan
  & $iscc $setupScript "/DMyAppVersion=$appVersion" "/DMyAppBuild=$buildNumber"
  Assert-ExitCode 'Compilacion Inno Setup'

  if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "No se genero el instalador esperado: $installerPath."
  }

  $installer = Get-Item -LiteralPath $installerPath
  if ($installer.Name -cne $installerFilename) {
    throw "Nombre de instalador invalido: $($installer.Name). Se esperaba $installerFilename."
  }
  if ($installer.Length -le 0) {
    throw 'El instalador generado esta vacio.'
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

  $installerSize = [long]$installer.Length
  $hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($hash -cnotmatch '^[0-9A-F]{64}$') {
    throw 'El SHA-256 calculado no contiene exactamente 64 caracteres hexadecimales.'
  }

  $publishedAt = [DateTime]::UtcNow.ToString(
    'yyyy-MM-ddTHH:mm:ssZ',
    [System.Globalization.CultureInfo]::InvariantCulture
  )

  $payload = [ordered]@{
    projectCode = 'fullpos'
    platform = 'windows'
    version = $appVersion
    buildNumber = $buildNumber
    minimumSupportedVersion = $minimumPolicy.Version
    minimumSupportedBuild = $minimumPolicy.Build
    mandatory = $mandatory
    enabled = $true
    installerUrl = $githubUrl
    installerFilename = $installerFilename
    installerSizeBytes = $installerSize
    sha256 = $hash
    releaseTitle = "FullPOS v$appVersion"
    releaseNotes = @($releaseNotes)
    publishedAt = $publishedAt
  }
  $payloadJson = $payload | ConvertTo-Json -Depth 6
  $payloadJson | Set-Content -LiteralPath $payloadPath -Encoding utf8
  $validatedPayload = Get-Content -LiteralPath $payloadPath -Raw | ConvertFrom-Json
  if (
    $validatedPayload.installerFilename -cne $installerFilename -or
    [long]$validatedPayload.installerSizeBytes -ne $installerSize -or
    [string]$validatedPayload.sha256 -cne $hash
  ) {
    throw 'La validacion posterior de update_payload.json no coincide con el instalador final.'
  }

  @(
    "FILENAME: $installerFilename"
    "VERSION: $appVersion"
    "BUILD: $buildNumber"
    "SIZE_BYTES: $installerSize"
    "SHA256: $hash"
  ) | Set-Content -LiteralPath $checksumPath -Encoding utf8

  $notesMarkdown = ($releaseNotes | ForEach-Object { "- $_" }) -join [Environment]::NewLine
  $mandatoryText = if ($mandatory) { 'Si' } else { 'No' }
  @"
# FullPOS para Windows v$appVersion

## Publicacion

- Version: ``$appVersion``
- Build: ``$buildNumber``
- Tag GitHub: ``$githubTag``
- Archivo: ``$installerFilename``
- Tamano: ``$installerSize`` bytes
- SHA-256: ``$hash``
- Actualizacion obligatoria: ``$mandatoryText``
- Minimo soportado: ``$($minimumPolicy.Version)+$($minimumPolicy.Build)``
- URL exacta: ``$githubUrl``
- Publicado UTC: ``$publishedAt``

## Notas

$notesMarkdown

## Archivos para GitHub Release

- ``installer/output/$installerFilename``
- ``installer/output/FullPOS-Setup.sha256.txt``
- ``installer/output/RELEASE_INFO.md``

## Archivo para el backend

- ``installer/output/update_payload.json``

## Publicacion manual de la politica

El release no publica la política automáticamente. Configura la llave solamente
en la sesión actual de PowerShell y ejecuta el publicador manual:

``````powershell
`$env:FULLPOS_RELEASE_API_KEY = "secret-set-locally"
.\installer\publish_update_policy.ps1
``````

El publicador exige escribir ``PUBLICAR`` antes del PUT. No guarda ni imprime la
llave. No se requiere token de GitHub.
"@ | Set-Content -LiteralPath $releaseInfoPath -Encoding utf8

  $relativeRelease = [System.IO.Path]::GetRelativePath($projectRoot, $releaseDir)
  $relativeInstaller = [System.IO.Path]::GetRelativePath($projectRoot, $installerPath)
  $relativePayload = [System.IO.Path]::GetRelativePath($projectRoot, $payloadPath)

  Write-Host ''
  Write-Host 'Release listo.' -ForegroundColor Green
  Write-Host ''
  Write-Host "Versión: $appVersion"
  Write-Host "Build: $buildNumber"
  Write-Host "Tag GitHub: $githubTag"
  Write-Host "Instalador: $relativeInstaller"
  Write-Host "Tamaño: $installerSize bytes"
  Write-Host "SHA-256: $hash"
  Write-Host "Política: obligatoria=$mandatory; mínimo=$($minimumPolicy.Version)+$($minimumPolicy.Build)"
  Write-Host "Archivo para backend: $relativePayload"
  Write-Host "URL exacta de GitHub: $githubUrl"
  Write-Host ''
  Write-Host 'Archivos listos para subir a GitHub:' -ForegroundColor Cyan
  Write-Host "  - $relativeInstaller"
  Write-Host '  - installer\output\FullPOS-Setup.sha256.txt'
  Write-Host '  - installer\output\RELEASE_INFO.md'
  Write-Host ''
  Write-Host "Build Windows: $relativeRelease\$exeName"
  Write-Host 'No se subio ningun archivo y no se llamo al backend.' -ForegroundColor Yellow
}
finally {
  Pop-Location
}
