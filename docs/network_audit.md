# Network audit (FASE 0) — FULLPOS (Windows)

> Objetivo: documentar el estado actual de networking/base URLs antes de cambiar código (auditoría obligatoria).

## Resumen ejecutivo

- **Stack actual (Flutter):** `package:http` + `http.Client` y llamadas directas `http.get/post/put` y `http.MultipartRequest`.
- **Configuración de base URL (actual):** existen **2 “base URLs” distintas** en Flutter:
  - `backendBaseUrl` (nube / backend general) vía `--dart-define=BACKEND_BASE_URL` con default hardcoded.
  - `kLicenseBackendBaseUrl` (licenciamiento/registro) hardcoded a otro host.
- **Robustez (actual):** timeouts son **dispersos** e inconsistentes; **sin retry** estándar; **sin cancelación**; mensajes de error suelen ser genéricos.
- **SSL:** no se encontraron patrones de bypass (`HttpOverrides`, `badCertificateCallback`).
- **Backend Node (FULLTECHPOS_BAKEND_LICENCIA):** ya expone `GET /api/health` y un CORS “allow all” (`Access-Control-Allow-Origin: *`).

## Alcance revisado

- Flutter app: `FULLPOS/lib/**` (y referencias puntuales a `windows/` sólo si aplica).
- Backend licencia/nube: `FULLTECHPOS_BAKEND_LICENCIA/backend/server.js` + rutas.

## Inventario: fuentes de URLs / configuración

### 1) Base URL backend (nube)

- Fuente: [lib/core/config/backend_config.dart](../lib/core/config/backend_config.dart)
  - `backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL', defaultValue: 'https://fullpos-proyecto-producion-fullpos-bakend.gcdndd.easypanel.host')`
  - Observación: es un **single-source** parcial, pero el default no coincide con el objetivo nuevo (`https://api.fulltechrd.com/`).

- Uso con fallback en UI: [lib/widgets/authorization_modal.dart](../lib/widgets/authorization_modal.dart)
  - `_resolveRemoteBaseUrl()` prioriza `settings.cloudEndpoint` (configurable por usuario), si no usa el `BACKEND_BASE_URL` por `String.fromEnvironment` con el mismo default hardcoded.

### 2) Base URL licenciamiento/registro

- Fuente: [lib/features/license/license_config.dart](../lib/features/license/license_config.dart)
  - `kLicenseBackendBaseUrl = 'https://fulltechpos-proyects-fulltechpos-backend-wed.gcdndd.easypanel.host'`
  - Observación: **hardcoded** y distinta a `backendBaseUrl`.

- Usos principales (no exhaustivo):
  - [lib/features/license/services/license_controller.dart](../lib/features/license/services/license_controller.dart)
  - [lib/features/license/services/business_license_sync.dart](../lib/features/license/services/business_license_sync.dart)
  - [lib/features/registration/services/business_registration_service.dart](../lib/features/registration/services/business_registration_service.dart)
  - [lib/app/router.dart](../lib/app/router.dart)

### 3) URL por `dart-define` (info corporativa)

- Fuente: [lib/features/settings/ui/logs_page.dart](../lib/features/settings/ui/logs_page.dart)
  - `_companyInfoUrl = String.fromEnvironment('FULLPOS_COMPANY_INFO_URL', defaultValue: '')`
  - Se consulta con `http.get(Uri.parse(_companyInfoUrl)).timeout(6s)`.
  - Nota: no es la “API base” de negocio; es un endpoint informativo opcional.

### 4) URLs externas no-API (no objetivo de centralización)

- WhatsApp soporte: [lib/features/license/ui/license_page.dart](../lib/features/license/ui/license_page.dart), [lib/features/license/ui/license_blocked_page.dart](../lib/features/license/ui/license_blocked_page.dart)
- Imágenes Unsplash (seed/demo): [lib/core/db/app_db.dart](../lib/core/db/app_db.dart)

## Inventario: módulos con llamadas HTTP (Flutter)

### Licencias / registro

- [lib/features/license/services/license_api.dart](../lib/features/license/services/license_api.dart)
  - Usa `http.Client` interno; construye `Uri` desde `baseUrl` + `path`.
  - Endpoints típicos: `/api/licenses/*`.
  - Timeouts: presentes en algunos métodos; no estándar global.

- [lib/features/license/services/business_license_api.dart](../lib/features/license/services/business_license_api.dart)
  - Usa `http.Client`.

- [lib/features/registration/services/business_registration_api.dart](../lib/features/registration/services/business_registration_api.dart)
  - Usa `http.Client`.

### Seguridad / aprobaciones remotas

- [lib/core/security/authorization_service.dart](../lib/core/security/authorization_service.dart)
  - Helper `_postJson(...)` normaliza baseUrl: si no hay esquema, fuerza `https://`.
  - Llama a `/api/override/verify` con header `x-override-key`.
  - Nota: este módulo ya tiene su propia lógica de URL/timeouts (parcialmente centralizada, pero aislada).

- [lib/widgets/authorization_modal.dart](../lib/widgets/authorization_modal.dart)
  - Resuelve baseUrl remoto desde settings (`cloudEndpoint`) o `BACKEND_BASE_URL`.

### Nube: sync / backups

- [lib/core/services/cloud_sync_service.dart](../lib/core/services/cloud_sync_service.dart)
  - Múltiples `http.post/put/...` con `.timeout(...)` (8–10s típicamente).
  - Construye `baseUrl` con `_resolveBaseUrl(settings)` y fallback a `backendBaseUrl`.
  - Headers incluyen `x-cloud-key` cuando aplica.

- [lib/core/backup/cloud_backup_service.dart](../lib/core/backup/cloud_backup_service.dart)
  - Descargas/listados vía `http.get/post(...).timeout(...)`.
  - Subida de backups usa `http.MultipartRequest('POST', uri)` y `request.send()`.
  - BaseUrl: `settings.cloudEndpoint` o `backendBaseUrl`.

- [lib/core/backup/cloud_status_service.dart](../lib/core/backup/cloud_status_service.dart)
  - Chequeo de “internet disponible” por `InternetAddress.lookup(host)` (DNS) con timeout 3s.
  - No realiza request HTTP a health endpoint.

### Herramientas

- [lib/features/tools/data/owner_app_links.dart](../lib/features/tools/data/owner_app_links.dart)
  - `GET $backendBaseUrl/api/downloads/owner-app`.
  - Sin timeout ni retry.

### Soporte / logs

- [lib/features/settings/ui/logs_page.dart](../lib/features/settings/ui/logs_page.dart)
  - Consulta externa opcional (`FULLPOS_COMPANY_INFO_URL`) con timeout 6s.
  - Exporta logs mediante `AppLogger` (no es un NetworkLogger dedicado).

## Timeouts, retries, cancelación (estado actual)

- **Timeouts:**
  - Presentes en varios módulos (`cloud_sync_service`, `cloud_backup_service`, `authorization_service`, `logs_page`).
  - **No existe una política única** (valores 6–20s según caso).

- **Retries:**
  - No se encontró una capa de retry unificada. Cualquier retry sería manual/por feature.

- **Cancelación:**
  - Con `package:http`, las llamadas actuales no exponen cancelación (no hay `CancelToken` o equivalente).

## Logging y diagnósticos

- `AppLogger` se usa para `logInfo/logWarn` en nube/backups.
- En UI, [lib/features/settings/ui/logs_page.dart](../lib/features/settings/ui/logs_page.dart) permite exportar logs.
- No se encontró un “NetworkLogger” separado que:
  - registre requests/responses sistemáticamente,
  - rote archivos,
  - exporte diagnóstico de red.

## SSL / certificados (estado actual)

- En búsqueda sobre Dart no se hallaron usos típicos de bypass:
  - `HttpOverrides`, `badCertificateCallback`, `allowBadCertificates`.
- Implicación: hoy FULLPOS depende de validación SSL estándar del runtime.

## Backend (Node/Express) — health y CORS

- Archivo: [FULLTECHPOS_BAKEND_LICENCIA/backend/server.js](../../FULLTECHPOS_BAKEND_LICENCIA/backend/server.js)
  - `GET /api/health` devuelve `{ ok: true, status: 'up', ts }`.
  - `GET /api/health/db` prueba DB pero responde 200 incluso si DB down (diagnóstico, no health estricto).
  - Middleware CORS:
    - `Access-Control-Allow-Origin: *`
    - `Allow-Methods: GET,POST,PUT,PATCH,DELETE,OPTIONS`
    - `Allow-Headers: Content-Type, Authorization, x-session-id, apikey, x-license-key, x-device-id`

## Hallazgos clave vs. requerimiento nuevo

- Ya existe un punto de configuración (`BACKEND_BASE_URL`), pero:
  - el default actual no apunta al dominio objetivo,
  - licenciamiento usa otra constante hardcoded (`kLicenseBackendBaseUrl`).
- Hay módulos que **deben seguir permitiendo** endpoint configurable por settings (`cloudEndpoint`) (por ejemplo nube/override), por lo que la centralización debe diferenciar:
  - **API oficial** (nuevo `https://api.fulltechrd.com/`),
  - **endpoint configurable de nube** (settings) cuando aplique.

## Recomendaciones para la FASE 1 (implementación) — sin ejecutar aquí

- Unificar una sola “API oficial” por config (ej. `AppConfig.apiBaseUrl`) y migrar:
  - `backendBaseUrl` default,
  - `kLicenseBackendBaseUrl`.
- Introducir un wrapper `ApiClient` sobre `http.Client` con:
  - timeouts consistentes,
  - retry exponencial acotado (1/2/4s) para `SocketException`, `TimeoutException`, y `5xx`.
- Agregar healthcheck cliente apuntando a un endpoint estable (idealmente `/health` o `/api/health`) y usarlo para UI estado online/offline.
- Implementar logging de red (a archivo) y export desde settings.

---

### Checklist de verificación (para cuando se implemente)

- Búsqueda global sin URLs hardcoded de backend anteriores (excepto externas legítimas: WhatsApp/Unsplash).
- Prueba en Windows con:
  - internet ok,
  - DNS falla,
  - proxy/firewall bloqueando,
  - SSL handshake failure (cert inválido) — **sin bypass**.
- Confirmar que `cloudEndpoint` (settings) sigue funcionando sin forzarlo al API oficial.
