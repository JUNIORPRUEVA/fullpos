import 'permission.dart';

/// Mapeo de rutas -> permisos de pantalla (no cambia el menú; solo controla al intentar).
class RoutePermissions {
  RoutePermissions._();

  static Permission? forPath(String path) {
    if (path == '/sales') return Permissions.salesAccess;
    if (path == '/products' || path == '/products/history') {
      return Permissions.productsView;
    }
    if (path == '/clients') return Permissions.clientsView;
    if (path == '/reports') return Permissions.reportsView;
    if (path == '/tools' || path == '/electronic-documents') {
      return Permissions.toolsAccess;
    }
    if (path == '/settings') return Permissions.settingsAccess;
    if (path.startsWith('/settings/')) return Permissions.settingsAccess;
    if (path == '/factura') return Permissions.salesHistoryView;
    if (path == '/quotes' || path == '/quotes-list') {
      return Permissions.quotesView;
    }
    if (path == '/credits' || path == '/credits-list') {
      return Permissions.creditsView;
    }
    if (path.startsWith('/purchases')) return Permissions.purchasesAccess;

    return null;
  }
}
