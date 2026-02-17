param(
	[string]$BaseUrl = "https://fullpos-backend-fullposlicenciaswed.onqyr1.easypanel.host"
)

$ErrorActionPreference = "Stop"

function Write-Section([string]$title) {
	Write-Host ""
	Write-Host "==== $title ====" -ForegroundColor Cyan
}

function Write-Pass([string]$msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red }

function Try-InvokeJson([string]$method, [string]$url, $body = $null) {
	try {
		if ($null -ne $body) {
			return Invoke-RestMethod -Method $method -Uri $url -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 6) -TimeoutSec 20
		}
		return Invoke-RestMethod -Method $method -Uri $url -TimeoutSec 20
	}
	catch {
		throw $_
	}
}

function Try-InvokeRaw([string]$method, [string]$url, $body = $null) {
	try {
		if ($null -ne $body) {
			return Invoke-WebRequest -Method $method -Uri $url -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 6) -TimeoutSec 20
		}
		return Invoke-WebRequest -Method $method -Uri $url -TimeoutSec 20
	}
	catch {
		if ($_.Exception.Response) {
			return $_.Exception.Response
		}
		throw $_
	}
}

Write-Section "Ambiente"
Write-Host "Fecha local: $((Get-Date).ToString('s'))"
Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
Write-Host "BaseUrl: $BaseUrl"

$uri = [System.Uri]$BaseUrl
$hostName = $uri.Host

Write-Section "DNS"
try {
	$dns = Resolve-DnsName -Name $hostName -ErrorAction Stop
	$ips = $dns | Where-Object { $_.Type -eq 'A' -or $_.Type -eq 'AAAA' } | Select-Object -ExpandProperty IPAddress -ErrorAction SilentlyContinue
	if ($ips) {
		Write-Pass "DNS resuelve $hostName -> $($ips -join ', ')"
	} else {
		Write-Warn "DNS respondió, pero no se extrajeron IPs A/AAAA"
	}
}
catch {
	Write-Fail "No resuelve DNS para $hostName. Error: $($_.Exception.Message)"
}

Write-Section "Puerto 443"
try {
	$tnc = Test-NetConnection -ComputerName $hostName -Port 443 -WarningAction SilentlyContinue
	if ($tnc.TcpTestSucceeded) {
		Write-Pass "Conexión TCP 443 exitosa"
	} else {
		Write-Fail "TCP 443 falló (firewall/proxy/red)"
	}
}
catch {
	Write-Fail "No se pudo probar TCP 443: $($_.Exception.Message)"
}

Write-Section "Health API"
try {
	$health = Try-InvokeJson -method "GET" -url "$BaseUrl/api/health"
	Write-Pass "/api/health responde: $($health | ConvertTo-Json -Compress)"
}
catch {
	Write-Fail "Fallo /api/health: $($_.Exception.Message)"
}

Write-Section "Ruta licencias (lectura)"
try {
	$fakeBusinessId = "diag-$(Get-Date -Format yyyyMMddHHmmss)-$([System.Guid]::NewGuid().ToString('N').Substring(0,6))"
	$resp = Try-InvokeRaw -method "GET" -url "$BaseUrl/businesses/$fakeBusinessId/license"

	$statusCode = $null
	if ($resp -and $resp.StatusCode) {
		try { $statusCode = [int]$resp.StatusCode } catch { $statusCode = $resp.StatusCode }
	}

	if ($statusCode -eq 404) {
		Write-Pass "Ruta /businesses/:id/license accesible (404 esperado para business_id ficticio)"
	}
	elseif ($statusCode -ge 200 -and $statusCode -lt 500) {
		Write-Warn "Ruta respondió HTTP $statusCode (hay conectividad, revisar respuesta)"
	}
	else {
		Write-Fail "Ruta devolvió HTTP inesperado: $statusCode"
	}
}
catch {
	Write-Fail "No se pudo consultar /businesses/:id/license: $($_.Exception.Message)"
}

Write-Section "Proxy del sistema"
try {
	$proxy = netsh winhttp show proxy | Out-String
	Write-Host $proxy
}
catch {
	Write-Warn "No se pudo leer proxy WinHTTP: $($_.Exception.Message)"
}

Write-Section "Cola pendiente FULLPOS"
try {
	$candidates = @(
		"$env:APPDATA",
		"$env:LOCALAPPDATA"
	) | Where-Object { $_ -and (Test-Path $_) }

	$found = @()
	foreach ($root in $candidates) {
		try {
			$matches = Get-ChildItem -Path $root -Recurse -File -Filter "pending_registration_queue_v1.json" -ErrorAction SilentlyContinue
			if ($matches) { $found += $matches }
		} catch {}
	}

	if (-not $found -or $found.Count -eq 0) {
		Write-Warn "No se encontró pending_registration_queue_v1.json"
	} else {
		foreach ($f in $found | Select-Object -Unique FullName) {
			Write-Host "Archivo: $($f.FullName)"
			try {
				$raw = Get-Content -Path $f.FullName -Raw -ErrorAction Stop
				$json = $raw | ConvertFrom-Json -ErrorAction Stop
				$count = @($json).Count
				if ($count -gt 0) {
					Write-Warn "Hay $count registro(s) pendiente(s) en cola"
				} else {
					Write-Pass "Cola vacía"
				}
			} catch {
				Write-Warn "No se pudo parsear la cola: $($_.Exception.Message)"
			}
		}
	}
}
catch {
	Write-Warn "No se pudo revisar cola pendiente: $($_.Exception.Message)"
}

Write-Section "Conclusión rápida"
Write-Host "Si DNS+443+health OK y la cola tiene items, hubo fallo temporal y FULLPOS quedó en modo pendiente para reintento."
Write-Host "Si DNS o 443 fallan, el bloqueo es de red/firewall/proxy/antivirus/TLS de esa PC."
