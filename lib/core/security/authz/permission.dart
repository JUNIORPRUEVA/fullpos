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

  static final creditsView = Permission.screen(
    code: 'ventas.creditos.ver',
    title: 'Creditos',
    description: 'Acceso a la pantalla de creditos.',
    legacyKey: 'can_view_credits',
  );

  // Acciones críticas (AppActions)
  static final processReturn = Permission.action(AppActions.processReturn);
}
