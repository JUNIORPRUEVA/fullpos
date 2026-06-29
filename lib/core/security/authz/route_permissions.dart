import 'permission.dart';

/// Mapeo de rutas -> permisos de pantalla (no cambia el menú; solo controla al intentar).
class RoutePermissions {
  RoutePermissions._();

  static Permission? forPath(String path) {
    if (path == '/sales') return Permissions.salesAccess;
    if (path == '/products') return Permissions.productsView;
    if (path == '/clients') return Permissions.clientsView;
    if (path == '/reports') return Permissions.reportsView;
    if (path == '/settings') return Permissions.settingsAccess;
    if (path.startsWith('/settings/') && path != '/settings/updates') {
      return Permissions.settingsAccess;
    }
    if (path == '/factura') return Permissions.salesHistoryView;
    if (path == '/quotes' || path == '/quotes-list') {
      return Permissions.quotesView;
    }
    if (path == '/credits' || path == '/credits-list') {
      return Permissions.creditsView;
    }
    if (path == '/products/stock-adjustment') {
      return Permissions.stockAdjustment;
    }
    if (path == '/products/movements' || path == '/products/history') {
      return Permissions.inventoryMovements;
    }
    if (path == '/products/count') return Permissions.inventoryCount;
    if (path == '/layaways') return Permissions.layawaysView;
    if (path == '/suppliers') return Permissions.suppliersView;
    if (path == '/suppliers/new') return Permissions.suppliersRegister;
    if (path.startsWith('/purchases')) return Permissions.purchasesAccess;

    return null;
  }
}
