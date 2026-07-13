# Auditoria de rutas y organizacion de datos FullPOS

Fecha: 2026-07-08

## Resumen

La aplicacion ya instala el ejecutable en una carpeta de sistema mediante Inno Setup:

- Instalacion actual: `{autopf}\FullPOS`
- En Windows 64-bit normalmente equivale a `C:\Program Files\FullPOS`
- Instalador: `installer/fullpos_setup.iss`

El problema principal no es la ubicacion del ejecutable, sino que los datos vivos de FullPOS estan repartidos entre varias carpetas del usuario:

- Documents
- AppData/Roaming
- AppData/Local
- Application Support
- Downloads
- Temp

Esto explica la sensacion de que "todo esta regado" en la PC.

## Mapa actual encontrado

### Base de datos principal

Archivo:

- `fullpos.db`
- `fullpos_test.db` en modo de prueba
- Tambien puede existir `fullpos.db-wal` y `fullpos.db-shm`

Ruta actual preferida:

- `getApplicationDocumentsDirectory()/fullpos.db`
- En Windows suele ser `C:\Users\<usuario>\Documents\fullpos.db`

Fallback si Documents no permite escritura:

- `getApplicationSupportDirectory()/fullpos.db`

Codigo:

- `lib/core/db/app_db.dart`
- Metodo: `AppDb._resolveDbPath()`

### Backups principales

Ruta actual:

- `getApplicationDocumentsDirectory()/FULLPOS_BACKUPS`
- En Windows suele ser `C:\Users\<usuario>\Documents\FULLPOS_BACKUPS`

Contenido:

- Backups `.zip`
- Backups antes de restaurar
- Cuarentena de DB corrupta
- Pre-repair
- Pre-migration
- Identity mirror

Codigo:

- `lib/core/backup/backup_paths.dart`
- `lib/core/backup/backup_service.dart`
- `lib/core/db/app_db.dart`
- `lib/core/database/migrations/migration_safety.dart`
- `lib/core/identity/identity_recovery_bundle.dart`

### Imagenes de productos

Ruta actual:

- `getApplicationDocumentsDirectory()/product_images`

Codigo:

- `lib/features/products/ui/dialogs/product_form_dialog.dart`
- `lib/features/products/data/products_repository.dart`
- `lib/core/backup/backup_paths.dart`

Observacion:

- Los backups incluyen `product_images`.

### Imagenes de categorias

Ruta actual:

- `getApplicationDocumentsDirectory()/category_images`

Codigo:

- `lib/features/products/ui/dialogs/category_form_dialog.dart`

Observacion:

- Actualmente `BackupPaths.optionalDataDirs()` solo incluye `product_images`, no `category_images`.

### Licencia local

Ruta actual en Windows:

- `%APPDATA%\FullPOS\license.dat`
- Normalmente: `C:\Users\<usuario>\AppData\Roaming\FullPOS\license.dat`

Fallback:

- `getApplicationSupportDirectory()/FullPOS/license.dat`

Codigo:

- `lib/features/license/services/license_file_storage.dart`

### Identidad local y recuperacion

Rutas actuales:

- `getApplicationSupportDirectory()/identity/identity_bundle.json`
- `getApplicationSupportDirectory()/identity/identity_bundle.bak.json`
- `getApplicationDocumentsDirectory()/FULLPOS_BACKUPS/identity/identity_bundle.json`
- `getApplicationDocumentsDirectory()/FULLPOS_BACKUPS/identity/identity_bundle.bak.json`

Codigo:

- `lib/core/identity/identity_recovery_bundle.dart`

### SharedPreferences

Rutas candidatas actuales:

- `getApplicationSupportDirectory()/shared_preferences.json`
- `getApplicationSupportDirectory()/shared_preferences/shared_preferences.json`
- `getApplicationSupportDirectory()/flutter_shared_preferences.json`

Codigo:

- `lib/core/storage/prefs_safe.dart`
- `lib/core/identity/identity_recovery_bundle.dart`

### Logs de aplicacion

Ruta actual:

- `getApplicationSupportDirectory()/logs`

Archivos:

- `app_YYYY-MM-DD.log`
- `db_hardening.log`
- `identity_recovery.log`

Codigo:

- `lib/core/logging/app_logger.dart`
- `lib/core/db_hardening/db_logger.dart`
- `lib/core/identity/identity_recovery_bundle.dart`

### Logs de soporte

Ruta actual para ZIPs:

- `getApplicationDocumentsDirectory()/FULLPOS_LOGS`

Codigo:

- `lib/core/support/support_logs_service.dart`
- `lib/features/settings/ui/logs_page.dart`

### Backups tecnicos de DB hardening

Ruta actual:

- `getApplicationSupportDirectory()/backups`

Codigo:

- `lib/core/db_hardening/db_backup.dart`

### Updates e instaladores descargados

Ruta actual:

- `%LOCALAPPDATA%\FullPOS\updates`
- Normalmente: `C:\Users\<usuario>\AppData\Local\FullPOS\updates`

Archivos:

- `FullPOS-Setup-v...exe`
- `.part`
- `FullPOSUpdater.log`
- Estado pendiente de update

Codigo:

- `lib/core/update/update_downloader.dart`
- `lib/core/update/installer_launcher.dart`
- `tool/fullpos_updater.dart`

### Exportaciones manuales

Rutas actuales:

- Excel productos: Downloads
- PDFs/catalogos/reportes/facturas: Downloads o Documents como fallback

Codigo:

- `lib/features/products/utils/products_exporter.dart`
- `lib/features/products/utils/catalog_pdf_launcher.dart`
- `lib/core/printing/sale_invoice_pdf_service.dart`
- `lib/features/reports/ui/reports_page.dart`
- `lib/features/clients/ui/clients_page.dart`
- `lib/features/sales/ui/quotes_page.dart`

Observacion:

- Esto puede quedarse en Downloads porque son archivos que el usuario pide exportar. No necesariamente deben vivir dentro de datos internos del sistema.

## Riesgos actuales

1. La DB en Documents queda visible y facil de borrar por accidente.
2. Los backups estan en Documents, mezclados con documentos personales.
3. La licencia vive en AppData/Roaming, mientras updates viven en AppData/Local.
4. Las imagenes de productos/categorias estan en Documents, separadas de logs y licencia.
5. Hay varias rutas con nombres distintos: `FullPOS`, `FULLPOS_BACKUPS`, `FULLPOS_LOGS`, `logs`, `backups`.
6. Mover solo una ruta puede romper restauracion, auto-repair, identidad, backups o actualizaciones.
7. Guardar datos vivos en `Program Files` o `Program Files (x86)` puede fallar por permisos de administrador y UAC.

## Recomendacion

No recomiendo guardar la base de datos viva dentro de `Program Files` ni `Program Files (x86)`.

La mejor estructura para Windows es:

```text
C:\Program Files\FullPOS\
  fullpos.exe
  FullPOSUpdater.exe
  flutter_windows.dll
  data\
  ...

C:\ProgramData\FullPOS_PTV\
  data\
    fullpos.db
    fullpos.db-wal
    fullpos.db-shm
  backups\
    automaticos\
    manuales\
    pre_migration\
    pre_repair\
    quarantine\
  media\
    products\
    categories\
  logs\
    app\
    db\
    support\
  license\
    license.dat
  identity\
    identity_bundle.json
    identity_bundle.bak.json
  updates\
    installers\
    logs\
  temp\
```

Ventajas:

- Una sola raiz ordenada para datos del sistema.
- `ProgramData` es la ubicacion correcta para datos compartidos de una aplicacion instalada.
- Evita problemas de permisos de `Program Files`.
- Permite que todos los usuarios de Windows vean el mismo FullPOS si hace falta.
- Facilita soporte, backup, restauracion y migracion.

## Plan de migracion recomendado

### Fase 1: crear un servicio central de rutas

Crear algo como:

- `lib/core/storage/fullpos_paths.dart`

Responsabilidad:

- Resolver `C:\ProgramData\FullPOS_PTV`
- Crear subcarpetas
- Centralizar DB, backups, media, logs, licencia, identity, updates y temp
- Tener fallback seguro si `ProgramData` no permite escritura

### Fase 2: migracion no destructiva

Al iniciar la app:

1. Detectar si existe DB nueva en `ProgramData`.
2. Si no existe, buscar DB vieja en Documents/Application Support.
3. Copiar DB vieja a la nueva ruta.
4. Copiar WAL/SHM si existen.
5. Copiar `product_images` y `category_images`.
6. Copiar backups existentes.
7. Copiar licencia.
8. Copiar identity bundles.
9. Crear un archivo `migration_manifest.json` con origen, destino, hashes y fecha.
10. No borrar los archivos viejos en la primera version.

### Fase 3: adaptar codigo por modulos

Cambiar de forma controlada:

- `AppDb.databasePath()`
- `BackupPaths`
- `AppLogger`
- `DbLogger`
- `DbBackup`
- `LicenseFileStorage`
- `IdentityRecoveryBundle`
- `UpdateDownloader`
- `SupportLogsService`
- Imagenes de productos y categorias

### Fase 4: validaciones

Pruebas necesarias:

- Abrir app con DB vieja en Documents y migrar a ProgramData.
- Abrir app con DB ya migrada.
- Crear backup y verificar que incluya DB, WAL/SHM, productos, categorias e identidad.
- Restaurar backup.
- Validar licencia offline con `license.dat`.
- Descargar update y lanzar updater.
- Verificar logs de soporte.
- Validar que no se creen nuevas carpetas viejas salvo exportaciones manuales.

## Decision pendiente

Nombre recomendado:

- `C:\ProgramData\FullPOS_PTV`

Alternativas:

- `C:\ProgramData\FullPOS`
- `C:\ProgramData\FullTech\FullPOS`

Mi recomendacion es `C:\ProgramData\FullPOS_PTV` si quieres que el nombre sea especifico para el punto de venta.

## Conclusion

Si, se puede ordenar el sistema como quieres.

Pero no conviene mover la DB y los datos vivos a `Program Files` o `Program Files (x86)`. Lo correcto es:

- Ejecutable en `C:\Program Files\FullPOS`
- Datos en `C:\ProgramData\FullPOS_PTV`
- Exportaciones manuales en Downloads o carpeta elegida por el usuario

El cambio debe hacerse con migracion automatica y no destructiva para proteger instalaciones existentes.
