import 'dart:async';

import 'package:flutter/material.dart';

import '../../../features/settings/data/user_model.dart';
import '../../../features/settings/data/users_repository.dart';
import '../../session/session_manager.dart';
import '../permission_service.dart';
import '../../security/security_config.dart';
import '../../security/app_actions.dart';
import '../../security/temporary_authorization_service.dart';
import '../../../widgets/authorization_modal.dart';
import '../../errors/error_handler.dart';
import 'authz_audit_service.dart';
import 'authz_user.dart';
import 'permission.dart';

class AuditMeta {
  final Map<String, dynamic> value;
  const AuditMeta(this.value);
}

/// AuthzService estilo Eleventa:
/// - NO oculta UI.
/// - Se llama en onTap/onPressed/onSubmit/onNavigate.
/// - Si no tiene permiso: pide override (PIN admin) via modal.
class AuthzService {
  AuthzService._();

  /// Clears ALL temporary overrides (call on logout / user switch).
  static void clearOverrideCache() {
    TemporaryAuthorizationService.clearAll();
    assert(() {
      debugPrint(
        '[AUTHZ] clearOverrideCache: all temporary authorizations cleared',
      );
      return true;
    }());
  }

  /// Clears the temporary override for a specific user+permission combination.
  /// Called by PermissionGate.dispose() so re-entry always requires fresh auth.
  static void clearOverrideFor({
    required int userId,
    required Permission permission,
  }) {
    TemporaryAuthorizationService.clearAuthorization(permission.code);
    assert(() {
      debugPrint(
        '[AUTHZ] clearOverrideFor: userId=$userId perm=${permission.code} removed',
      );
      return true;
    }());
  }

  /// Construye un usuario de autorización desde la sesión actual.
  /// Carga:
  /// - permisos legacy (módulos) desde sesión/DB (AuthRepository)
  /// - permisos de acciones (AppActions) desde DB (PermissionService.effectivePermissions)
  static Future<User?> currentUser() async {
    final userId = await SessionManager.userId();
    if (userId == null) return null;
    final role = await SessionManager.role() ?? PermissionService.roleCashier;
    final companyId = await SessionManager.companyId() ?? 1;
    final terminalId =
        await SessionManager.terminalId() ??
        await SessionManager.ensureTerminalId();

    final isAdmin = await SessionManager.isAdmin();

    // Importante: NO confiar solo en cache de sesión para permisos.
    // Si un admin cambia permisos mientras el usuario está logueado,
    // este fetch desde DB permite que los toggles tengan efecto inmediato.
    final modulePermissions = isAdmin
        ? UserPermissions.admin()
        : await UsersRepository.getPermissions(userId);
    final actionPermissions = await PermissionService.effectivePermissions(
      companyId: companyId,
      userId: userId,
      role: role,
    );

    return AuthzUser(
      userId: userId,
      companyId: companyId,
      role: role,
      terminalId: terminalId,
      modulePermissions: modulePermissions,
      actionPermissions: actionPermissions,
    );
  }

  /// API obligatoria: chequeo sin cambiar UI.
  static bool can(User u, Permission p) {
    if (u.isAdmin) return true;

    if (TemporaryAuthorizationService.isAuthorized(p.code)) return true;

    if (p.kind == PermissionKind.action) {
      return u.actionPermissions[p.code] ?? false;
    }

    final key = p.legacyKey;
    if (key == null || key.isEmpty) return false;
    return _legacyCan(u.modulePermissions, key);
  }

  /// API obligatoria: pide autorización (si no tiene permiso).
  static Future<bool> require(
    BuildContext ctx,
    User u,
    Permission p, {
    String? reason,
    AuditMeta? meta,
    String? resourceType,
    String? resourceId,
    bool isOnline = true,
  }) async {
    if (TemporaryAuthorizationService.isAuthorized(p.code)) return true;

    await AuthzAuditService.log(
      companyId: u.companyId,
      permissionCode: p.code,
      result: 'ATTEMPT',
      method: 'permission',
      terminalId: u.terminalId,
      requestedByUserId: u.userId,
      resourceType: resourceType,
      resourceId: resourceId,
      meta: {'reason': ?reason, if (meta != null) ...meta.value},
    );

    if (can(u, p)) {
      await AuthzAuditService.log(
        companyId: u.companyId,
        permissionCode: p.code,
        result: 'ALLOW',
        method: 'permission',
        terminalId: u.terminalId,
        requestedByUserId: u.userId,
        resourceType: resourceType,
        resourceId: resourceId,
      );
      return true;
    }

    final securityConfig = await SecurityConfigRepository.load(
      companyId: u.companyId,
      terminalId: u.terminalId,
    );
    final enforcedConfig = securityConfig.copyWith(offlinePinEnabled: true);

    final actionForModal = p.action ?? _pseudoActionForPermission(p);

    // No depender del ctx del caller (puede ya no estar mounted tras awaits).
    final dialogContext =
        ErrorHandler.navigatorKey.currentState?.overlay?.context ??
        ErrorHandler.navigatorKey.currentContext ??
        ctx;

    final ok = await AuthorizationModal.show(
      context: dialogContext,
      action: actionForModal,
      resourceType: resourceType ?? 'permission',
      resourceId: resourceId ?? p.code,
      companyId: u.companyId,
      requestedByUserId: u.userId,
      terminalId: u.terminalId,
      config: enforcedConfig,
      isOnline: isOnline,
    );

    await AuthzAuditService.log(
      companyId: u.companyId,
      permissionCode: p.code,
      result: ok ? 'OVERRIDE_OK' : 'OVERRIDE_CANCEL',
      method: ok ? 'override' : 'override',
      terminalId: u.terminalId,
      requestedByUserId: u.userId,
      resourceType: resourceType,
      resourceId: resourceId,
      meta: {'reason': ?reason, if (meta != null) ...meta.value},
    );

    return ok;
  }

  /// API obligatoria: ejecuta acción solo si hay permiso u override.
  static Future<T?> runGuarded<T>(
    BuildContext ctx,
    User u,
    Permission p,
    FutureOr<T> Function() action, {
    String? reason,
    AuditMeta? meta,
    String? resourceType,
    String? resourceId,
    bool isOnline = true,
  }) async {
    final ok = await require(
      ctx,
      u,
      p,
      reason: reason,
      meta: meta,
      resourceType: resourceType,
      resourceId: resourceId,
      isOnline: isOnline,
    );
    if (!ok) return null;
    return await action();
  }

  /// Helper práctico: no requiere pasar User manualmente.
  static Future<T?> runGuardedCurrent<T>(
    BuildContext ctx,
    Permission p,
    FutureOr<T> Function() action, {
    String? reason,
    AuditMeta? meta,
    String? resourceType,
    String? resourceId,
    bool isOnline = true,
  }) async {
    final user = await currentUser();
    if (user == null) return null;
    return runGuarded(
      ctx,
      user,
      p,
      action,
      reason: reason,
      meta: meta,
      resourceType: resourceType,
      resourceId: resourceId,
      isOnline: isOnline,
    );
  }

  static AppAction _pseudoActionForPermission(Permission p) {
    AppActionCategory category = AppActionCategory.settings;
    if (p.code.startsWith('rep.')) category = AppActionCategory.settings;
    if (p.code.startsWith('ventas.') || p.code.startsWith('sales.')) {
      category = AppActionCategory.sales;
    }
    if (p.code.startsWith('caja.') || p.code.startsWith('cash.')) {
      category = AppActionCategory.cash;
    }

    return AppAction(
      code: p.code,
      name: p.title,
      description: p.description,
      category: category,
      risk: ActionRisk.high,
      requiresOverrideByDefault: true,
    );
  }

  /// Helper para envolver callbacks sin deshabilitar UI.
  static VoidCallback guardedAction(
    BuildContext ctx,
    Permission p,
    FutureOr<void> Function() action, {
    String? reason,
    AuditMeta? meta,
    String? resourceType,
    String? resourceId,
    bool isOnline = true,
  }) {
    return () {
      unawaited(
        runGuardedCurrent<void>(
          ctx,
          p,
          action,
          reason: reason,
          meta: meta,
          resourceType: resourceType,
          resourceId: resourceId,
          isOnline: isOnline,
        ),
      );
    };
  }

  static bool _legacyCan(UserPermissions perms, String permissionKey) {
    switch (permissionKey) {
      case 'can_sell':
        return perms.canSell;
      case 'can_void_sale':
        return perms.canVoidSale;
      case 'can_apply_discount':
        return perms.canApplyDiscount;
      case 'can_view_sales_history':
        return perms.canViewSalesHistory;
      case 'can_view_products':
        return perms.canViewProducts;
      case 'can_edit_products':
        return perms.canEditProducts;
      case 'can_delete_products':
        return perms.canDeleteProducts;
      case 'can_adjust_stock':
        return perms.canAdjustStock;
      case 'can_view_purchase_price':
        return perms.canViewPurchasePrice;
      case 'can_view_profit':
        return perms.canViewProfit;
      case 'can_view_clients':
        return perms.canViewClients;
      case 'can_edit_clients':
        return perms.canEditClients;
      case 'can_delete_clients':
        return perms.canDeleteClients;
      case 'can_open_cash':
        return perms.canOpenCash;
      case 'can_close_cash':
        return perms.canCloseCash;
      case 'can_open_cashbox':
        return perms.canOpenCashbox;
      case 'can_close_cashbox':
        return perms.canCloseCashbox;
      case 'can_open_shift':
        return perms.canOpenShift;
      case 'can_close_shift':
        return perms.canCloseShift;
      case 'can_exit_with_open_shift':
        return perms.canExitWithOpenShift;
      case 'can_view_cash_history':
        return perms.canViewCashHistory;
      case 'can_make_cash_movements':
        return perms.canMakeCashMovements;
      case 'can_view_reports':
        return perms.canViewReports;
      case 'can_export_reports':
        return perms.canExportReports;
      case 'can_create_quotes':
        return perms.canCreateQuotes;
      case 'can_view_quotes':
        return perms.canViewQuotes;
      case 'can_convert_quotes_to_ticket':
        return perms.canConvertQuotesToTicket;
      case 'can_process_returns':
        return perms.canProcessReturns;
      case 'can_view_credits':
        return perms.canViewCredits;
      case 'can_manage_credits':
        return perms.canManageCredits;
      case 'can_manage_users':
        return perms.canManageUsers;
      case 'can_access_settings':
        return perms.canAccessSettings;
      default:
        return false;
    }
  }
}
