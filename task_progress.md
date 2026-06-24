# Plan de Corrección: Bug de Permiso de Ajuste de Inventario

## Diagnóstico

### Problema 1: Ruta no registrada
La ruta `/products/stock-adjustment` NO está registrada en:
- `RoutePermissions.forPath()` → devuelve `null`
- `ModuleAccess.canAccessPath()` → devuelve `false` (fallback genérico)

Cuando el router intenta acceder, `canAccessPath()` en `router.dart` primero busca en `RoutePermissions.forPath()` (null), luego en `ModuleAccess.canAccessPath()` (false), resultando en redirección a `/no-access?from=/products/stock-adjustment`.

El mensaje "Catalogo" viene de `ModuleAccess.moduleLabelForPath()` que dice `if (path.startsWith('/products')) return 'Catalogo'`.

### Problema 2: TemporaryAuthorizationService duración incorrecta
- `defaultDuration` es 3 minutos, debe ser 2 minutos
- No hay limpieza al salir de la pantalla

### Problema 3: No hay PermissionGate en la ruta
La ruta en `router.dart` línea 346-348 no tiene `PermissionGate` ni `BlankPermissionGate`.

## Archivos a modificar

1. **lib/core/security/authz/route_permissions.dart** - Agregar ruta `/products/stock-adjustment`
2. **lib/core/security/module_access.dart** - Agregar ruta `/products/stock-adjustment`
3. **lib/core/security/temporary_authorization_service.dart** - Cambiar defaultDuration a 2 min
4. **lib/app/router.dart** - Agregar BlankPermissionGate a la ruta stock-adjustment
5. **lib/features/products/ui/inventory_module_pages.dart** - Agregar limpieza de temp auth en dispose()
6. **test/core/security/temporary_authorization_service_test.dart** - Actualizar tests
7. **test/core/security/permission_service_test.dart** - Agregar tests de ruta
