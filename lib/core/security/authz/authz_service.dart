import 'dart:async';

import 'package:flutter/material.dart';

import '../../../features/settings/data/user_model.dart';
import '../../../features/settings/data/users_repository.dart';
import '../../session/session_manager.dart';
import '../permission_service.dart';
import '../../security/security_config.dart';
import '../../security/app_actions.dart';
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

  // Prevents back-to-back prompts for the same permission after a successful override.
  // This is intentionally short-lived and in-memory only.
  // Only a short cooldown to prevent back-to-back prompts caused by multiple guards
  // running in sequence for the same user interaction.
  static const Duration _overrideTtl = Duration(seconds: 3);
  static final Map<String, DateTime> _overrideCache = <String, DateTime>{};

  // Small cache to avoid re-hitting the DB for permissions repeatedly during
  // rapid route transitions (e.g. smoke tests / fast navigation).
  static const Duration _currentUserCacheTtl = Duration(milliseconds: 500);
  static int? _cachedUserId;
  static User? _cachedCurrentUser;
  static DateTime? _cachedCurrentUserAt;
  static Future<User?>? _currentUserInFlight;

  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

  static String _overrideKey({
    required int userId,
    required Permission permission,
    required String? resourceType,
    required String? resourceId,
  }) {
    // Cache at permission level (not resource-level) to avoid back-to-back prompts
    // triggered by multiple guards during the same user flow.
    return '$userId|${permission.code}';
  }

  static bool _hasValidCachedOverride(String key) {
    final until = _overrideCache[key];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _overrideCache.remove(key);
      return false;
    }
    return true;
  }

  /// Construye un usuario de autorización desde la sesión actual.
  /// Carga:
  /// - permisos legacy (módulos) desde sesión/DB (AuthRepository)
  /// - permisos de acciones (AppActions) desde DB (PermissionService.effectivePermissions)
  static Future<User?> currentUser() async {
    final userId = await SessionManager.userId();
    if (userId == null) {
      _cachedUserId = null;
      _cachedCurrentUser = null;
      _cachedCurrentUserAt = null;
      _currentUserInFlight = null;
      return null;
    }

    final cachedAt = _cachedCurrentUserAt;
    final cachedUser = _cachedCurrentUser;
    if (_cachedUserId == userId && cachedAt != null && cachedUser != null) {
      final age = DateTime.now().difference(cachedAt);
      if (age <= _currentUserCacheTtl) {
        return cachedUser;
      }
    }

    final inFlight = _currentUserInFlight;
    if (inFlight != null) return inFlight;

    final future = () async {
      final role = await SessionManager.role() ?? PermissionService.roleCashier;
      final companyId = await SessionManager.companyId() ?? 1;
      final terminalId =
          await SessionManager.terminalId() ??
          await SessionManager.ensureTerminalId();

      final isAdmin = await SessionManager.isAdmin();

      if (_isFlutterTest) {
        final modulePermissions =
            isAdmin ? UserPermissions.admin() : UserPermissions.cashier();
        return AuthzUser(
          userId: userId,
          companyId: companyId,
          role: role,
          terminalId: terminalId,
          modulePermissions: modulePermissions,
          actionPermissions: const {},
        );
      }

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
    }();

    _currentUserInFlight = future;
    try {
      final user = await future;
      if (user != null) {
        _cachedUserId = userId;
        _cachedCurrentUser = user;
        _cachedCurrentUserAt = DateTime.now();
      }
      return user;
    } finally {
      if (identical(_currentUserInFlight, future)) {
        _currentUserInFlight = null;
      }
    }
  }

  /// API obligatoria: chequeo sin cambiar UI.
  static bool can(User u, Permission p) {
    if (u.isAdmin) return true;

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
    final cachedKey = _overrideKey(
      userId: u.userId,
      permission: p,
      resourceType: resourceType,
      resourceId: resourceId,
    );
    if (_hasValidCachedOverride(cachedKey)) return true;

    await AuthzAuditService.log(
      companyId: u.companyId,
      permissionCode: p.code,
      result: 'ATTEMPT',
      method: 'permission',
      terminalId: u.terminalId,
      requestedByUserId: u.userId,
      resourceType: resourceType,
      resourceId: resourceId,
      meta: {
        if (reason != null) 'reason': reason,
        if (meta != null) ...meta.value,
      },
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

    if (ok) {
      _overrideCache[cachedKey] = DateTime.now().add(_overrideTtl);
    }

    await AuthzAuditService.log(
      companyId: u.companyId,
      permissionCode: p.code,
      result: ok ? 'OVERRIDE_OK' : 'OVERRIDE_CANCEL',
      method: ok ? 'override' : 'override',
      terminalId: u.terminalId,
      requestedByUserId: u.userId,
      resourceType: resourceType,
      resourceId: resourceId,
      meta: {
        if (reason != null) 'reason': reason,
        if (meta != null) ...meta.value,
      },
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
      case 'can_access_tools':
        return perms.canAccessTools;
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
