import '../../features/settings/data/user_model.dart';

/// Centraliza la logica de "permiso para ver/entrar a un modulo/pantalla".
///
/// Regla del negocio:
/// - El sidebar puede mostrar TODOS los modulos.
/// - Entrar a un modulo depende de permisos de modulo (UserPermissions).
/// - Las acciones internas usan AppActions/override (PIN/token) por separado.
class ModuleAccess {
  ModuleAccess._();

  static bool canAccessPath({
    required String path,
    required bool isAdmin,
    required UserPermissions permissions,
  }) {
    if (isAdmin) return true;

    // Pantalla neutral: siempre permitir para que el usuario vea el mensaje.
    if (path == '/no-access') return true;

    if (path == '/sales') return permissions.canSell;
    if (path == '/sales-list') return permissions.canViewSalesHistory;

    if (path == '/quotes' || path == '/quotes-list') return permissions.canViewQuotes;
    if (path == '/credits' || path == '/credits-list') return permissions.canViewCredits;
    if (path == '/returns' || path == '/returns-list') return permissions.canProcessReturns;

    if (path == '/products') return permissions.canViewProducts;
    if (path == '/products/history') return permissions.canViewProducts;
    if (path.startsWith('/products/add-stock')) return permissions.canAdjustStock;

    if (path == '/clients') return permissions.canViewClients;

    if (path.startsWith('/purchases')) return permissions.canAdjustStock;

    if (path.startsWith('/cash')) {
      return permissions.canOpenCash || permissions.canCloseCash || permissions.canViewCashHistory;
    }

    if (path == '/reports') return permissions.canViewReports;
    if (path == '/tools' || path == '/ncf') return permissions.canAccessTools;

    if (path == '/settings' ||
        path == '/settings/printer' ||
        path == '/settings/logs' ||
        path == '/settings/backup') {
      return permissions.canAccessSettings;
    }

    // Cuenta/perfil: por defecto permitir (fallback).
    if (path == '/account') return true;

    // Rutas no contempladas: permitir para no bloquear features nuevas por accidente.
    return true;
  }

  static String moduleLabelForPath(String path) {
    if (path == '/sales') return 'Ventas';
    if (path == '/sales-list') return 'Historial de ventas';
    if (path == '/quotes' || path == '/quotes-list') return 'Cotizaciones';
    if (path == '/credits' || path == '/credits-list') return 'Creditos';
    if (path == '/returns' || path == '/returns-list') return 'Devoluciones';
    if (path.startsWith('/products')) return 'Catalogo';
    if (path == '/clients') return 'Clientes';
    if (path.startsWith('/purchases')) return 'Compras';
    if (path.startsWith('/cash/expenses')) return 'Gastos';
    if (path.startsWith('/cash')) return 'Caja';
    if (path == '/reports') return 'Reportes';
    if (path == '/tools' || path == '/ncf') return 'Herramientas';
    if (path.startsWith('/settings')) return 'Configuracion';
    if (path == '/account') return 'Cuenta';
    return 'Modulo';
  }
}

