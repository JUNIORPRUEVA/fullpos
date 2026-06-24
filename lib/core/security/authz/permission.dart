import '../app_actions.dart';

enum PermissionKind { screen, action }

/// Permiso del sistema (pantalla o acción).
///
/// - **Pantalla**: se valida contra permisos de módulo (UserPermissions legacy).
/// - **Acción**: se valida contra el sistema de acciones (AppActions / PermissionService).
class Permission {
  final String code;
  final String title;
  final String description;
  final PermissionKind kind;

  /// Clave legacy almacenada en `UserModel.permissions` (JSON) via `UserPermissions`.
  /// Ej: `can_view_reports`.
  final String? legacyKey;

  /// Si es un permiso de acción, se usa para mostrar detalles en el override modal.
  final AppAction? action;

  const Permission._({
    required this.code,
    required this.title,
    required this.description,
    required this.kind,
    this.legacyKey,
    this.action,
  });

  factory Permission.screen({
    required String code,
    required String title,
    required String description,
    required String legacyKey,
  }) {
    return Permission._(
      code: code,
      title: title,
      description: description,
      kind: PermissionKind.screen,
      legacyKey: legacyKey,
    );
  }

  factory Permission.action(AppAction action) {
    return Permission._(
      code: action.code,
      title: action.name,
      description: action.description,
      kind: PermissionKind.action,
      action: action,
    );
  }
}

/// Catálogo mínimo (se puede ampliar sin romper UI).
class Permissions {
  Permissions._();

  // Pantallas (módulos)
  static final salesAccess = Permission.screen(
    code: 'ventas.ver',
    title: 'Ventas',
    description: 'Acceso a la pantalla principal de ventas.',
    legacyKey: 'can_sell',
  );

  static final productsView = Permission.screen(
    code: 'productos.ver',
    title: 'Productos',
    description: 'Acceso al catálogo y al historial de productos.',
    legacyKey: 'can_view_products',
  );

  static final clientsView = Permission.screen(
    code: 'clientes.ver',
    title: 'Clientes',
    description: 'Acceso al módulo de clientes.',
    legacyKey: 'can_view_clients',
  );

  static final purchasesAccess = Permission.screen(
    code: 'compras.ver',
    title: 'Compras',
    description: 'Acceso al módulo de compras y órdenes.',
    legacyKey: 'can_adjust_stock',
  );

  static final reportsView = Permission.screen(
    code: 'rep.ver',
    title: 'Reportes',
    description: 'Acceso a la pantalla de reportes.',
    legacyKey: 'can_view_reports',
  );

  static final settingsAccess = Permission.screen(
    code: 'cfg.ver',
    title: 'Configuración',
    description: 'Acceso a la pantalla de configuración.',
    legacyKey: 'can_access_settings',
  );

  static final settingsPermissions = Permission.screen(
    code: 'cfg.permisos',
    title: 'Permisos',
    description: 'Acceso a la administración de permisos de usuarios.',
    legacyKey: 'can_manage_users',
  );

  static final salesHistoryView = Permission.screen(
    code: 'ventas.factura.ver',
    title: 'Factura',
    description: 'Acceso a la pantalla unificada de facturas y devoluciones.',
    legacyKey: 'can_view_sales_history',
  );

  static final returnsView = Permission.screen(
    code: 'ventas.devolucion.ver',
    title: 'Devoluciones',
    description: 'Acceso a la pantalla de devoluciones.',
    legacyKey: 'can_process_returns',
  );

  static final quotesView = Permission.screen(
    code: 'ventas.cotizaciones.ver',
    title: 'Cotizaciones',
    description: 'Acceso a la pantalla de cotizaciones.',
    legacyKey: 'can_view_quotes',
  );

  static final quotesConvertToTicket = Permission.screen(
    code: 'ventas.cotizaciones.pasar_ticket',
    title: 'Cotizaciones: pasar a ticket pendiente',
    description:
        'Permite convertir una cotización en un ticket pendiente desde el módulo de cotizaciones.',
    legacyKey: 'can_convert_quotes_to_ticket',
  );

  static final creditsView = Permission.screen(
    code: 'ventas.creditos.ver',
    title: 'Creditos',
    description: 'Acceso a la pantalla de creditos.',
    legacyKey: 'can_view_credits',
  );

  /// Permiso para acceder a la pantalla de ajuste de inventario.
  ///
  /// Mapea al permiso legacy `can_adjust_stock` (UserPermissions) y al
  /// código de acción `inventory.adjust_stock` (AppActions).
  /// La UI de permisos muestra "Productos -> Ajustar inventario".
  static final stockAdjustment = Permission.screen(
    code: 'inventory.adjust_stock',
    title: 'Ajustar inventario',
    description: 'Acceso a la pantalla de ajuste de stock.',
    legacyKey: 'can_adjust_stock',
  );

  // Acciones críticas (AppActions)
  static final processReturn = Permission.action(AppActions.processReturn);
}
