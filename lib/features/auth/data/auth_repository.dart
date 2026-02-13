import 'dart:convert';
import '../../settings/data/user_model.dart';
import '../../settings/data/users_repository.dart';
import '../../../core/session/session_manager.dart';

/// Repositorio de autenticación
class AuthRepository {
  AuthRepository._();

  /// Valida las credenciales del usuario y retorna el usuario si es válido
  static Future<UserModel?> login(String username, String password) async {
    final user = await UsersRepository.verifyCredentials(username, password);

    if (user != null) {
      await _startSession(user);
    }

    return user;
  }

  /// Valida acceso por PIN y guarda la sesión.
  static Future<UserModel?> loginWithPin(String username, String pin) async {
    final user = await UsersRepository.verifyPin(username, pin);

    if (user != null) {
      await _startSession(user);
    }

    return user;
  }

  static Future<void> _startSession(UserModel user) async {
    await SessionManager.login(
      userId: user.id!,
      username: user.username,
      displayName: user.displayLabel,
      role: user.role,
      permissions: user.permissions,
      companyId: user.companyId,
    );
  }

  /// Cierra la sesión del usuario
  static Future<void> logout() async {
    await SessionManager.logout();
  }

  /// Cambia la contraseña del usuario actual validando la contraseña vigente.
  ///
  /// - No loggea contraseñas.
  /// - Usa el hashing existente (`UsersRepository.hashPassword`).
  static Future<void> changeCurrentUserPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final userId = await SessionManager.userId();
    final username = await SessionManager.username();
    final companyId = await SessionManager.companyId();
    if (userId == null || username == null || username.isEmpty) {
      throw StateError('No hay sesión activa');
    }

    final verified = await UsersRepository.verifyCredentials(
      username,
      currentPassword,
      companyId: companyId,
    );
    if (verified == null) {
      throw ArgumentError('Contraseña actual incorrecta');
    }

    await UsersRepository.changePassword(userId, newPassword);
  }

  /// Verifica si hay un usuario logueado
  static Future<bool> isLoggedIn() async {
    return await SessionManager.isLoggedIn();
  }

  /// Obtiene el usuario actual logueado
  static Future<UserModel?> getCurrentUser() async {
    final userId = await SessionManager.userId();
    if (userId == null) return null;

    // Preferir datos de sesión para evitar re-hits a DB durante navegación rápida
    // (p.ej. widget tests / loaders). Si falta información, caer a DB.
    final username = await SessionManager.username();
    final displayName = await SessionManager.displayName();
    final role = await SessionManager.role();
    final companyId = await SessionManager.companyId() ?? 1;
    final permissionsJson = await SessionManager.permissions();

    if (username != null && username.trim().isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return UserModel(
        id: userId,
        companyId: companyId,
        username: username,
        displayName: displayName,
        role: role ?? 'cashier',
        isActive: 1,
        permissions: permissionsJson,
        createdAtMs: now,
        updatedAtMs: now,
      );
    }

    return await UsersRepository.getById(userId, companyId: companyId);
  }

  /// Obtiene los permisos del usuario actual
  static Future<UserPermissions> getCurrentPermissions() async {
    if (await SessionManager.isAdmin()) return UserPermissions.admin();

    final userId = await SessionManager.userId();
    if (userId == null) return UserPermissions.none();

    // Fuente de verdad: DB. Evita inconsistencias con cache viejo en sesión.
    final perms = await UsersRepository.getPermissions(userId);
    // Mantener cache actualizado para pantallas que usan SessionManager.permissions().
    final nextJson = jsonEncode(perms.toMap());
    final existing = await SessionManager.permissions();
    if (existing != nextJson) {
      await SessionManager.setPermissions(nextJson);
    }
    return perms;
  }

  /// Verifica si el usuario tiene un permiso específico
  static Future<bool> hasPermission(String permission) async {
    final permissions = await getCurrentPermissions();

    switch (permission) {
      case 'can_sell':
        return permissions.canSell;
      case 'can_void_sale':
        return permissions.canVoidSale;
      case 'can_apply_discount':
        return permissions.canApplyDiscount;
      case 'can_view_sales_history':
        return permissions.canViewSalesHistory;
      case 'can_view_products':
        return permissions.canViewProducts;
      case 'can_edit_products':
        return permissions.canEditProducts;
      case 'can_delete_products':
        return permissions.canDeleteProducts;
      case 'can_adjust_stock':
        return permissions.canAdjustStock;
      case 'can_view_purchase_price':
        return permissions.canViewPurchasePrice;
      case 'can_view_profit':
        return permissions.canViewProfit;
      case 'can_view_clients':
        return permissions.canViewClients;
      case 'can_edit_clients':
        return permissions.canEditClients;
      case 'can_delete_clients':
        return permissions.canDeleteClients;
      case 'can_open_cash':
        return permissions.canOpenCash;
      case 'can_close_cash':
        return permissions.canCloseCash;
      case 'can_view_cash_history':
        return permissions.canViewCashHistory;
      case 'can_make_cash_movements':
        return permissions.canMakeCashMovements;
      case 'can_view_reports':
        return permissions.canViewReports;
      case 'can_export_reports':
        return permissions.canExportReports;
      case 'can_create_quotes':
        return permissions.canCreateQuotes;
      case 'can_view_quotes':
        return permissions.canViewQuotes;
      case 'can_access_tools':
        return permissions.canAccessTools;
      case 'can_process_returns':
        return permissions.canProcessReturns;
      case 'can_view_credits':
        return permissions.canViewCredits;
      case 'can_manage_credits':
        return permissions.canManageCredits;
      case 'can_manage_users':
        return permissions.canManageUsers;
      case 'can_access_settings':
        return permissions.canAccessSettings;
      default:
        return false;
    }
  }

  /// Verifica si el usuario actual es admin
  static Future<bool> isAdmin() async {
    // Fast path: el rol está cacheado en sesión.
    return SessionManager.isAdmin();
  }
}
