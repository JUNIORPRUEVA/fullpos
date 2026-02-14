# Auditoría de licenciamiento FULLPOS (estado actual)

Fecha: 2026-02-14

> Objetivo: documentar el flujo actual (trial/licencia/activación), storage local, endpoints existentes, y **dónde se usa `device_id`**.
> 
> **Nota importante (scope):** esta auditoría no cambia código; solo documenta lo encontrado.

---

## 1) ¿Dónde se guarda el “trial” y datos del negocio?

### 1.1 Datos del negocio (local)

- FULLPOS tiene una tabla local SQLite `business_settings` (sqflite) para la configuración del negocio/empresa.
- Se maneja desde:
  - `lib/features/settings/data/business_settings_repository.dart`
  - `lib/features/settings/data/business_settings_model.dart`
- Campos relevantes existentes: `business_name`, `phone`, `email`, etc.
- También existen campos de nube en esa tabla (no son licenciamiento): `cloud_enabled`, `cloud_endpoint`, `cloud_api_key`, `cloud_company_id`, etc.

### 1.2 Trial (estado actual)

- **No existe un trial local de 5 días** implementado como “contador offline” en Flutter (no se encontró persistencia tipo `trial_start` en `SharedPreferences` ni en SQLite).
- El comportamiento tipo “DEMO” actual está implementado como **licencia DEMO del backend**, creada vía endpoint público `POST /api/licenses/start-demo` y activada para un dispositivo.

En Flutter:
- La DEMO se inicia desde la UI de licencias y llama a `LicenseController.startDemo()`:
  - `lib/features/license/services/license_controller.dart`
  - `lib/features/license/ui/license_page.dart`

En Backend:
- La DEMO se crea y se activa “atado” a device:
  - `backend/controllers/licensesDemoController.js` (`POST /api/licenses/start-demo`)
  - DB: tabla `demo_trials` (migraciones `009_create_demo_trials.sql`, `010_add_demo_trials_device_id.sql`)

---

## 2) Endpoints existentes (licenciamiento)

### 2.1 Endpoints públicos para app escritorio (backend licencias)

Definidos en `backend/routes/licensesPublicRoutes.js`:

- `POST /api/licenses/activate`
  - Body: `{ license_key, device_id, project_code|project_id }`
- `POST /api/licenses/check`
  - Body: `{ license_key, device_id, project_code|project_id }`
- `POST /api/licenses/auto-activate`
  - Body: `{ device_id, project_code|project_id }`
  - Resuelve una licencia activa por historial del dispositivo.
- `POST /api/licenses/start-demo`
  - Body (FULLPOS): `{ project_code, device_id, nombre_negocio, rol_negocio, contacto_nombre, contacto_telefono }`
- `POST /api/licenses/verify-offline-file`
  - Verifica firma del archivo offline y opcionalmente match de `device_id`.
- `GET /api/licenses/public-signing-key`
  - Devuelve la clave pública Ed25519 en formato JWK.

### 2.2 Endpoints admin (panel)

Documentados en `FULLTECHPOS_BAKEND_LICENCIA/README.md`:

- Projects:
  - `GET /api/admin/projects`
  - `POST /api/admin/projects`
- Licencias:
  - `POST /api/admin/licenses`
  - `GET /api/admin/licenses?project_code=...`
- Archivo de licencia offline (JSON firmado):
  - `GET /api/admin/licenses/:id/license-file?download=1`
  - Opcional (atar a un equipo): `.../license-file?device_id=MI-PC&download=1`

---

## 3) ¿Dónde se usa `device_id` hoy?

### 3.1 En Flutter (FULLPOS)

**Generación / persistencia**
- `device_id` se deriva del `terminal_id` local de `SessionManager.ensureTerminalId()`.
  - Storage: `SharedPreferences` key `terminal_id`.
  - Archivo: `lib/core/session/session_manager.dart`

**Licencias (módulo features/license)**
- API envía `device_id` en requests:
  - `lib/features/license/services/license_api.dart`
    - `activate()`, `check()`, `autoActivateByDevice()`, `startDemo()`.
- Controller fuerza `deviceId` y lo guarda:
  - `lib/features/license/services/license_controller.dart`
    - `_ensureDeviceId()` reutiliza terminalId.
- Storage de `device_id` de licencias:
  - `lib/features/license/services/license_storage.dart`
    - `SharedPreferences` key `license.deviceId`.

**Gate de inicio (router)**
- `lib/app/router.dart` implementa “auto-resolver” licencias y demo upgrade **por `device_id`**:
  - Llama `POST /api/licenses/auto-activate`.
  - Si `check()` devuelve `NOT_FOUND` intenta `activate()` para registrar el dispositivo.

**DB local interna (no necesariamente licenciamiento)**
- SQLite `terminals` incluye `device_id TEXT NOT NULL UNIQUE(device_id)`:
  - `lib/core/db/app_db.dart`

### 3.2 En Backend (FULLTECHPOS_BAKEND_LICENCIA)

- Activaciones por dispositivo:
  - Tabla `license_activations` tiene `device_id`.
  - `backend/controllers/licensesController.js`:
    - `activate()` y `check()` requieren `device_id`.
    - `autoActivateByDevice()` resuelve licencia por historial de `device_id`.

- DEMO trials por dispositivo:
  - Tabla `demo_trials` incluye `device_id`.
  - Migración que impone unique por (project_id, device_id): `010_add_demo_trials_device_id.sql`.

---

## 4) ¿Dónde se guarda la licencia hoy?

### 4.1 En Flutter

No existe un `license.dat` persistido como archivo.

Hoy se persiste principalmente en `SharedPreferences`:
- `license.licenseKey` (texto)
- `license.lastInfo` (JSON cacheado de `LicenseInfo`)
- `license.deviceId`
- `license_signing_pubkey_b64_v1` (clave pública Ed25519 cache)

Implementación:
- `lib/features/license/services/license_storage.dart`

### 4.2 Licencia offline firmada (JSON)

- Flutter ya soporta aplicar un “archivo de licencia offline” firmado Ed25519, pero se maneja como **Map JSON** (payload + signature) y se guarda como estado (`licenseKey` + `lastInfo`) en SharedPreferences.
- La verificación offline en Flutter usa el paquete `cryptography` (Ed25519) y firma sobre `jsonEncode(payload)`.
- Payload actual incluye opcionalmente `device_id` y el cliente puede rechazar si no coincide:
  - Verificación en `LicenseController.applyOfflineLicenseFile()`.

Backend:
- Generación/firmado del archivo offline:
  - `backend/utils/licenseFile.js`
  - Payload actual (v=1) incluye: `project_code`, `license_key`, `tipo`, `fecha_inicio`, `fecha_fin`, `dias_validez`, `max_dispositivos`, `device_id` (opcional), `customer`.
- Endpoint para clave pública (JWK): `GET /api/licenses/public-signing-key`.

---

## 5) Conclusiones para el rediseño pedido

- El flujo actual depende fuertemente de `device_id` tanto en:
  - backend (activations/demo_trials)
  - app (router gate + LicenseApi)
- La “DEMO 5 días” hoy parece ser una **licencia DEMO backend** y no un trial offline local.
- Ya existe infraestructura útil para el nuevo requerimiento:
  - Firma Ed25519 (private key en backend, public key en app)
  - Verificación offline en Flutter
- Falta en el estado actual:
  - `business_id` estable (UUID) persistido localmente
  - endpoint para registro de negocio (cloud) independiente de device
  - endpoint para recuperar licencia por `business_id` (200/204)
  - `license.dat` como archivo local y polling suave de auto-descarga

---

## 6) Referencias rápidas (archivos clave)

Flutter:
- `lib/features/license/services/license_api.dart`
- `lib/features/license/services/license_controller.dart`
- `lib/features/license/services/license_storage.dart`
- `lib/app/router.dart`
- `lib/core/session/session_manager.dart`
- `lib/features/settings/data/business_settings_repository.dart`

Backend:
- `backend/routes/licensesPublicRoutes.js`
- `backend/controllers/licensesController.js`
- `backend/controllers/licensesDemoController.js`
- `backend/utils/licenseFile.js`
- `README.md`
