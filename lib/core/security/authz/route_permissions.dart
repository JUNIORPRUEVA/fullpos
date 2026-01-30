import 'permission.dart';

/// Mapeo de rutas -> permisos de pantalla (no cambia el menú; solo controla al intentar).
class RoutePermissions {
  RoutePermissions._();

  static Permission? forPath(String path) {
    if (path == '/reports') return Permissions.reportsView;
    if (path == '/settings') return Permissions.settingsAccess;
    if (path.startsWith('/settings/')) return Permissions.settingsAccess;
    if (path == '/returns' || path == '/returns-list') return Permissions.returnsView;
    if (path == '/quotes' || path == '/quotes-list') return Permissions.quotesView;
    if (path == '/credits' || path == '/credits-list') return Permissions.creditsView;

    // Módulos legacy adicionales (si se quiere gatear navegación desde sidebar).
    // Nota: no agrego todo aquí para no forzar permisos de módulos no solicitados.
    return null;
  }
}
