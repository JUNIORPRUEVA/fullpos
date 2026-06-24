import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../db/tables.dart';
import '../../features/settings/data/users_repository.dart';
import '../session/session_manager.dart';
import 'action_access.dart';
import 'app_actions.dart';
import 'security_config.dart';
import 'temporary_authorization_service.dart';

class PermissionDeniedException implements Exception {
  final String permissionKey;
  final String message;

  const PermissionDeniedException(
    this.permissionKey, [
    this.message = 'No tienes permiso para realizar esta acción.',
  ]);

  @override
  String toString() => '$message ($permissionKey)';
}

class PermissionDecision {
  final bool allowed;
  final bool overrideAllowed;
  final bool requiresOverride;
  final AppAction? action;

  PermissionDecision({
    required this.allowed,
    required this.overrideAllowed,
    required this.requiresOverride,
    required this.action,
  });
}

class PermissionService {
  PermissionService._();

  static const String roleAdmin = 'admin';
  static const String roleSupervisor = 'supervisor';
  static const String roleCashier = 'cashier';
  static const String roleCajero = 'cajero';

  static Future<PermissionDecision> check({
    required String actionCode,
    int? companyId,
    int? userId,
    String? role,
    SecurityConfig? config,
  }) async {
    final resolvedUserId = userId ?? await SessionManager.userId();
    final resolvedRole = normalizeRole(
      role ?? (await SessionManager.role()) ?? roleCashier,
    );
    final resolvedCompanyId =
        companyId ?? await SessionManager.companyId() ?? 1;
    final action = AppActions.findByCode(actionCode);
    if (resolvedUserId == null) {
      final requiresOverride = await SecurityConfigRepository.requiresOverride(
        actionCode,
        companyId: resolvedCompanyId,
        cached: config,
      );
      return PermissionDecision(
        allowed: false,
        overrideAllowed: action?.overrideAllowed ?? true,
        requiresOverride: requiresOverride,
        action: action,
      );
    }

    final allowed = await can(
      actionCode,
      companyId: resolvedCompanyId,
      userId: resolvedUserId,
      role: resolvedRole,
    );
    final requiresOverride = await SecurityConfigRepository.requiresOverride(
      actionCode,
      companyId: resolvedCompanyId,
      cached: config,
    );

    return PermissionDecision(
      allowed: allowed,
      overrideAllowed: action?.overrideAllowed ?? true,
      requiresOverride: requiresOverride,
      action: action,
    );
  }

  static Future<bool> can(
    String permissionKey, {
    int? companyId,
    int? userId,
    String? role,
  }) async {
    final actionCode = normalizePermissionKey(permissionKey);
    if (actionCode.isEmpty) return false;
    final action = AppActions.findByCode(actionCode);
    if (action == null) return false;

    final resolvedUserId = userId ?? await SessionManager.userId();
    if (resolvedUserId == null) return false;

    final resolvedRole = normalizeRole(
      role ?? (await SessionManager.role()) ?? roleCashier,
    );
    if (resolvedRole == roleAdmin) return true;
    if (TemporaryAuthorizationService.isAuthorized(actionCode)) return true;
    final resolvedCompanyId =
        companyId ?? await SessionManager.companyId() ?? 1;

    final explicit = await _explicitUserPermission(
      companyId: resolvedCompanyId,
      userId: resolvedUserId,
      actionCode: actionCode,
    );
    if (explicit != null) return explicit;

    // Per product rules, module permissions are the authority for critical actions.
    final modulePerms = await UsersRepository.getPermissions(resolvedUserId);
    return ActionAccess.isAllowed(
      action: action,
      isAdmin: false,
      permissions: modulePerms,
    );
  }

  static Future<bool?> _explicitUserPermission({
    required int companyId,
    required int userId,
    required String actionCode,
  }) async {
    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.userPermissions,
      columns: ['allowed'],
      where: 'company_id = ? AND user_id = ? AND action_code = ?',
      whereArgs: [companyId, userId, actionCode],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      return (rows.first['allowed'] as int? ?? 0) == 1;
    }
    return null;
  }

  static Future<bool> canAny(List<String> permissionKeys) async {
    for (final permissionKey in permissionKeys) {
      if (await can(permissionKey)) return true;
    }
    return false;
  }

  static Future<bool> canAll(List<String> permissionKeys) async {
    for (final permissionKey in permissionKeys) {
      if (!await can(permissionKey)) return false;
    }
    return true;
  }

  static Future<void> requirePermission(String permissionKey) async {
    if (await can(permissionKey)) return;
    throw PermissionDeniedException(normalizePermissionKey(permissionKey));
  }

  static Future<void> setUserPermission({
    required int companyId,
    required int userId,
    required String actionCode,
    required bool allowed,
  }) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(DbTables.userPermissions, {
      'company_id': companyId,
      'user_id': userId,
      'action_code': actionCode,
      'allowed': allowed ? 1 : 0,
      'created_at_ms': now,
      'updated_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, bool>> effectivePermissions({
    required int companyId,
    required int userId,
    required String role,
  }) async {
    final map = <String, bool>{};
    final normalizedRole = normalizeRole(role);
    if (normalizedRole == roleAdmin) {
      for (final action in AppActions.all) {
        map[action.code] = true;
      }
      return map;
    }

    final modulePerms = await UsersRepository.getPermissions(userId);
    for (final action in AppActions.all) {
      map[action.code] =
          await _explicitUserPermission(
            companyId: companyId,
            userId: userId,
            actionCode: action.code,
          ) ??
          ActionAccess.isAllowed(
            action: action,
            isAdmin: false,
            permissions: modulePerms,
          );
    }
    return map;
  }

  static Set<String> defaultAllowedActionsForRole(String role) {
    final normalized = normalizeRole(role);
    if (normalized == roleAdmin) {
      return AppActions.all.map((a) => a.code).toSet();
    }
    if (normalized == roleSupervisor) {
      return <String>{
        AppActions.cancelSale.code,
        AppActions.deleteSaleItem.code,
        AppActions.modifyLinePrice.code,
        AppActions.applyDiscount.code,
        AppActions.chargeSale.code,
        AppActions.createQuote.code,
        AppActions.grantCredit.code,
        AppActions.createLayaway.code,
        AppActions.processReturn.code,
        AppActions.addStock.code,
        AppActions.removeStock.code,
        AppActions.adjustInventory.code,
        AppActions.adjustStock.code,
        AppActions.editCost.code,
        AppActions.editSalePrice.code,
        AppActions.updateProduct.code,
        AppActions.deleteProduct.code,
        AppActions.createProduct.code,
        AppActions.importProducts.code,
        AppActions.startSession.code,
        AppActions.closeSession.code,
        AppActions.cashMovement.code,
        AppActions.configureScanner.code,
      };
    }
    // Cajero: solo lo basico de venta/caja.
    return <String>{
      AppActions.deleteSaleItem.code,
      AppActions.applyDiscount.code,
      AppActions.chargeSale.code,
      AppActions.createQuote.code,
      AppActions.startSession.code,
      AppActions.closeSession.code,
      AppActions.configureScanner.code,
    };
  }

  static String normalizeRole(String role) {
    final lower = role.trim().toLowerCase();
    if (lower == roleCajero) return roleCashier;
    return lower;
  }

  static String normalizePermissionKey(String permissionKey) {
    return TemporaryAuthorizationService.normalizeScope(permissionKey);
  }

  static Future<bool> isAdmin() => SessionManager.isAdmin();
}
