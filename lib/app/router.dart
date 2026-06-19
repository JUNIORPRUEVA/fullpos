import 'dart:async';

import 'package:flutter/material.dart' hide LicensePage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';

import '../core/bootstrap/app_bootstrap_controller.dart';
import '../core/brand/fullpos_brand_theme.dart';
import '../core/errors/error_handler.dart';
import '../core/layout/app_shell.dart';
import '../core/security/module_access.dart';
import '../core/security/authz/authz_service.dart';
import '../core/security/authz/authz_user.dart';
import '../core/security/authz/permission_gate.dart';
import '../core/security/authz/permission.dart';
import '../core/security/authz/route_permissions.dart';
import '../core/ui/no_access_page.dart';
import '../features/account/ui/account_page.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/ui/login_page.dart';
import '../features/auth/ui/force_change_password_page.dart';
import '../features/auth/services/first_run_auth_flags.dart';
import '../features/cash/ui/cash_box_page.dart';
import '../features/cash/ui/cash_gate_page.dart';
import '../features/cash/ui/cash_history_page.dart';
import '../features/cash/ui/expenses_overview_page.dart';
import '../features/cash/data/operation_flow_service.dart';
import '../features/clients/ui/clients_page.dart';
import '../features/products/ui/inventory_module_pages.dart';
import '../features/purchases/ui/purchase_auto_page.dart';
import '../features/purchases/ui/purchase_manual_page.dart';
import '../features/purchases/ui/purchase_orders_page.dart';
import '../features/purchases/ui/purchase_order_create_auto_page.dart';
import '../features/purchases/ui/purchase_order_create_manual_page.dart';
import '../features/purchases/ui/purchase_order_receive_page.dart';
import '../features/purchases/ui/purchase_orders_list_page.dart';
import '../features/purchases/ui/suppliers_management_pages.dart';
import '../features/reports/ui/reports_page.dart';
import '../core/security/authz/blank_permission_gate.dart';
import '../features/sales/ui/client_credit_pages.dart';
import '../features/sales/ui/quotes_page.dart';
import '../features/sales/ui/factura_page.dart';
import '../features/sales/ui/sales_page.dart';
import '../features/settings/ui/printer_settings_page.dart';
import '../features/settings/ui/logs_page.dart';
import '../features/settings/ui/backup_settings_page.dart';
import '../features/settings/ui/settings_page.dart';
import '../features/settings/ui/users_page.dart';
import '../features/tools/ui/electronic_invoicing_page.dart';
import '../features/tools/ui/tools_page.dart';
import '../features/license/ui/license_page.dart';
import '../features/license/ui/license_blocked_page.dart';
import '../features/license/ui/license_purchase_page.dart';
import '../features/license/services/license_storage.dart';
import '../features/license/services/license_api.dart';
import '../features/license/services/business_license_sync.dart';
import '../features/license/services/license_gate_refresh.dart';
import '../features/license/data/license_models.dart';
import '../features/license/license_config.dart';
import '../core/session/session_manager.dart';
import '../core/identity/identity_recovery_bundle.dart';
import '../features/settings/data/user_model.dart';
import '../features/registration/services/business_identity_guard.dart';
import '../features/registration/services/business_identity_storage.dart';
import '../core/update/app_update_coordinator.dart';

Future<_LicenseGateDecision>? _licenseGateInFlight;
_LicenseGateDecision? _licenseGateCached;
DateTime? _licenseGateCachedAt;
int _licenseGateCachedEpoch = 0;
Future<void>? _cloudRevokeCheckInFlight;
Future<void>? _blockedCloudProbeInFlight;
DateTime? _blockedCloudProbeAt;

const _kCloudGateMinPollInterval = Duration(seconds: 15);
const _kActiveGateDecisionCacheWindow = Duration(seconds: 10);
const _kInactiveGateDecisionCacheWindow = Duration(seconds: 1);
const _kInactiveCloudGateMinPollInterval = Duration(seconds: 2);
const _kBlockedGateProbeInterval = Duration(seconds: 5);

void _runCloudRevocationCheckInBackground(BusinessLicenseSync sync) {
  if (_cloudRevokeCheckInFlight != null) return;
  _cloudRevokeCheckInFlight = sync
      .tryPollFromCloudIfDue(
        minInterval: _kCloudGateMinPollInterval,
        networkTimeout: const Duration(seconds: 2),
      )
      .then((changed) {
        if (changed) {
          // Si el backend eliminó/bloqueó y el sync limpió/actualizó cache,
          // forzar re-evaluar redirects inmediatamente.
          bumpLicenseGateRefresh();
        }
      })
      .catchError((_) {})
      .whenComplete(() {
        _cloudRevokeCheckInFlight = null;
      });
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final bootStatus = ref.watch(
    appBootstrapProvider.select((b) => b.snapshot.status),
  );
  final isLoggedIn = ref.watch(
    appBootstrapProvider.select((b) => b.snapshot.isLoggedIn),
  );
  final bootstrap = ref.read(appBootstrapProvider);

  // Heartbeat para re-evaluar redirects (ej: vencimiento o revocación) sin reiniciar.
  // El valor se controla en license_config.dart.
  final heartbeat = _RouterHeartbeat(kLicenseGateHeartbeatInterval);
  final refresh = _MergedListenable([
    bootstrap,
    heartbeat,
    licenseGateRefreshToken,
  ]);
  ref.onDispose(() {
    refresh.dispose();
    heartbeat.dispose();
  });

  return GoRouter(
    navigatorKey: ErrorHandler.navigatorKey,
    // Nota: La pantalla de arranque se maneja fuera del router (AppEntry).
    // Mantener una ruta inicial estable evita “rebotes” visuales.
    initialLocation: isLoggedIn ? '/cash-gate' : '/login',
    refreshListenable: refresh,
    redirect: (context, state) async {
      final path = state.uri.path;
      final isOnLogin = path == '/login';
      final isOnForceChangePassword = path == '/force-change-password';
      final isOnPublicLicense = path == '/license';
      final isOnLicensePurchase = path == '/license/purchase';
      final isOnSettingsLicense = path == '/settings/license';
      final isOnBlocked = path == '/license-blocked';
      final isOnCashGate = path == '/cash-gate';
      final isOnNoAccess = path == '/no-access';

      bool? isAdminCache;
      Future<bool> loadIsAdmin() async {
        isAdminCache ??= await SessionManager.isAdmin();
        return isAdminCache!;
      }

      UserPermissions? permissionsCache;
      Future<UserPermissions> loadPermissions() async {
        permissionsCache ??= await AuthRepository.getCurrentPermissions();
        return permissionsCache!;
      }

      User? authzUserCache;
      Future<User?> loadAuthzUser() async {
        authzUserCache ??= await AuthzService.currentUser();
        return authzUserCache;
      }

      String noAccessLocation(String requestedPath) => Uri(
        path: '/no-access',
        queryParameters: {'from': requestedPath},
      ).toString();

      Future<bool> canAccessPath(String targetPath) async {
        final screenPermission = RoutePermissions.forPath(targetPath);
        if (screenPermission != null) {
          final user = await loadAuthzUser();
          return user != null && AuthzService.can(user, screenPermission);
        }

        final isAdmin = await loadIsAdmin();
        final permissions = await loadPermissions();
        return ModuleAccess.canAccessPath(
          path: targetPath,
          isAdmin: isAdmin,
          permissions: permissions,
        );
      }

      // Mientras el bootstrap corre, no redirigir rutas: AppEntry muestra Splash/Error.
      if (bootStatus != BootStatus.ready) return null;

      ActiveSession? activeSessionCache;
      Future<ActiveSession?> loadActiveSession() async {
        activeSessionCache ??= await OperationFlowService.loadActiveSession();
        return activeSessionCache;
      }

      Future<String> privateLanding() async {
        final session = await loadActiveSession();
        return session == null ? '/cash-gate' : '/sales';
      }

      // Gate de licencia: distinguir ACTIVA vs BLOQUEADA vs no válida.
      final gate = await _getLicenseGateDecisionFast();
      assert(() {
        debugPrint(
          '[LICENSE] gate: active=${gate.isActive} blocked=${gate.isBlocked} code=${gate.code} path=$path',
        );
        return true;
      }());

      // Si está BLOQUEADA: no permitir hacer nada, solo mostrar pantalla de bloqueo.
      if (gate.isBlocked) {
        return (isOnBlocked || isOnLicensePurchase) ? null : '/license-blocked';
      }

      // Sin licencia válida (revocada/eliminada/vencida/etc): mostrar pantalla normal.
      if (!gate.isActive) {
        return (isOnPublicLicense || isOnLicensePurchase) ? null : '/license';
      }

      // Una sola comprobación central, después de conocer el estado de licencia.
      // Un fallo de red nunca bloquea; una política obligatoria validada sí.
      await AppUpdateCoordinator.instance.ensureStarted();

      // Con licencia activa, no permitir volver a la pantalla de licencia/bloqueo.
      if (isOnBlocked) {
        return isLoggedIn ? await privateLanding() : '/login';
      }
      if (isOnPublicLicense) {
        return isLoggedIn ? await privateLanding() : '/login';
      }
      if (isOnLicensePurchase) {
        return isLoggedIn ? await privateLanding() : '/login';
      }
      if (isOnSettingsLicense) {
        // En debug permitimos abrir la pantalla de licencia desde Configuración
        // para poder resetear TRIAL/licencia en esta misma PC.
        if (kDebugMode) return null;
        return isLoggedIn ? await privateLanding() : '/login';
      }

      assert(() {
        debugPrint(
          '[ROUTER] redirect check: path=$path loggedIn=$isLoggedIn status=$bootStatus',
        );
        return true;
      }());
      if (!isLoggedIn) {
        if (isOnForceChangePassword) return '/login';
        return (isOnLogin || isOnPublicLicense) ? null : '/login';
      }

      // Cambio de contraseña obligatorio: debe ganar sobre cualquier ruta privada.
      // Importante: NO debe saltarse el gate de licencia (ya evaluado arriba).
      final mustChangePassword = await FirstRunAuthFlags.mustChangePassword();
      if (mustChangePassword) {
        if (!isOnForceChangePassword) {
          FirstRunAuthFlags.log(
            'mustChangePassword=true redirecting path=$path',
          );
          return '/force-change-password';
        }
        return null;
      } else {
        if (isOnForceChangePassword) return await privateLanding();
      }

      if (isOnLogin) return await privateLanding();

      if (isOnNoAccess) return null;

      final activeSession = await loadActiveSession();
      if (activeSession == null) {
        if (isOnCashGate) {
          final canAccessCashGate = await canAccessPath('/cash-gate');
          return canAccessCashGate ? null : noAccessLocation('/cash-gate');
        }
        return '/cash-gate';
      }

      if (isOnCashGate) {
        return '/sales';
      }

      final allowed = await canAccessPath(path);
      if (!allowed) {
        return noAccessLocation(path);
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => FullposBrandScope(child: LoginPage()),
      ),
      GoRoute(
        path: '/cash-gate',
        builder: (context, state) =>
            const FullposBrandScope(child: CashGatePage()),
      ),
      GoRoute(
        path: '/force-change-password',
        builder: (context, state) =>
            FullposBrandScope(child: ForceChangePasswordPage()),
      ),
      GoRoute(
        path: '/license',
        builder: (context, state) =>
            const FullposBrandScope(child: LicensePage()),
      ),
      GoRoute(
        path: '/license/purchase',
        builder: (context, state) =>
            const FullposBrandScope(child: LicensePurchasePage()),
      ),
      GoRoute(
        path: '/license-blocked',
        builder: (context, state) =>
            const FullposBrandScope(child: LicenseBlockedPage()),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/no-access',
            builder: (context, state) => _NoAccessRoutePage(
              requestedPath: state.uri.queryParameters['from'] ?? '',
            ),
          ),
          GoRoute(
            path: '/sales',
            builder: (context, state) {
              int? ticketId;
              final extra = state.extra;
              if (extra is int) {
                ticketId = extra;
              } else if (extra is String) {
                ticketId = int.tryParse(extra);
              }

              ticketId ??= int.tryParse(
                state.uri.queryParameters['ticketId'] ?? '',
              );

              return SalesPage(initialTicketId: ticketId);
            },
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const ProductsServicesPage(),
          ),
          GoRoute(
            path: '/products/stock-adjustment',
            builder: (context, state) => const StockAdjustmentWorkspacePage(),
          ),
          GoRoute(
            path: '/products/movements',
            builder: (context, state) => const InventoryMovementsPage(),
          ),
          GoRoute(
            path: '/products/count',
            builder: (context, state) => const InventoryCountPage(),
          ),
          GoRoute(
            path: '/products/history',
            builder: (context, state) => const InventoryMovementsPage(),
          ),
          GoRoute(
            path: '/clients',
            builder: (context, state) => const ClientsPage(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => BlankPermissionGate(
              permission: Permissions.reportsView,
              autoPromptOnce: true,
              reason: 'Acceso a reportes',
              resourceType: 'screen',
              resourceId: 'reports',
              child: const ReportsPage(),
            ),
          ),
          GoRoute(
            path: '/tools',
            builder: (context, state) => const ToolsPage(),
          ),
          GoRoute(
            path: '/settings/license',
            builder: (context, state) =>
                const FullposBrandScope(child: LicensePage()),
          ),
          GoRoute(
            path: '/electronic-documents',
            builder: (context, state) => const ElectronicInvoicingPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => PermissionGate(
              permission: Permissions.settingsAccess,
              autoPromptOnce: false,
              reason: 'Acceso a configuración',
              child: const SettingsPage(),
            ),
          ),
          GoRoute(
            path: '/settings/users',
            builder: (context, state) => PermissionGate(
              permission: Permissions.settingsAccess,
              autoPromptOnce: false,
              reason: 'Gestión de usuarios',
              child: const UsersPage(),
            ),
          ),
          GoRoute(
            path: '/settings/printer',
            builder: (context, state) => const PrinterSettingsPage(),
          ),
          GoRoute(
            path: '/settings/logs',
            builder: (context, state) => const LogsPage(),
          ),
          GoRoute(
            path: '/settings/backup',
            builder: (context, state) => const BackupSettingsPage(),
          ),
          GoRoute(
            path: '/account',
            builder: (context, state) => const AccountPage(),
          ),

          // Rutas de ventas
          GoRoute(
            path: '/factura',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: const Duration(milliseconds: 320),
              reverseTransitionDuration: const Duration(milliseconds: 220),
              child: PermissionGate(
                permission: Permissions.salesHistoryView,
                autoPromptOnce: false,
                reason: 'Acceso a factura',
                child: FacturaPage(
                  initialSaleId: int.tryParse(
                    state.uri.queryParameters['saleId'] ?? '',
                  ),
                  openRefund: state.uri.queryParameters['refund'] == '1',
                ),
              ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    );
                    return FadeTransition(
                      opacity: Tween<double>(begin: 0, end: 1).animate(curved),
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.022, 0),
                          end: Offset.zero,
                        ).animate(curved),
                        child: child,
                      ),
                    );
                  },
            ),
          ),
          GoRoute(
            path: '/quotes',
            builder: (context, state) => PermissionGate(
              permission: Permissions.quotesView,
              autoPromptOnce: false,
              reason: 'Acceso a cotizaciones',
              child: const QuotesPage(),
            ),
          ),
          GoRoute(
            path: '/quotes-list',
            builder: (context, state) => PermissionGate(
              permission: Permissions.quotesView,
              autoPromptOnce: false,
              reason: 'Acceso a cotizaciones',
              child: const QuotesPage(),
            ),
          ),
          GoRoute(
            path: '/credits',
            builder: (context, state) => PermissionGate(
              permission: Permissions.creditsView,
              autoPromptOnce: false,
              reason: 'Acceso a creditos',
              child: const ClientCreditsPage(),
            ),
          ),
          GoRoute(
            path: '/credits-list',
            builder: (context, state) => PermissionGate(
              permission: Permissions.creditsView,
              autoPromptOnce: false,
              reason: 'Acceso a creditos',
              child: const ClientCreditsPage(),
            ),
          ),
          GoRoute(
            path: '/layaways',
            builder: (context, state) => PermissionGate(
              permission: Permissions.creditsView,
              autoPromptOnce: false,
              reason: 'Acceso a apartados',
              child: const ClientLayawaysPage(),
            ),
          ),
          GoRoute(
            path: '/cash',
            builder: (context, state) => const CashBoxPage(),
          ),
          GoRoute(
            path: '/cash/history',
            builder: (context, state) => const CashHistoryPage(),
          ),
          GoRoute(
            path: '/cash/expenses',
            builder: (context, state) => const ExpensesOverviewPage(),
          ),

          // Compras / Órdenes de compra
          GoRoute(
            path: '/purchases',
            builder: (context, state) => const PurchaseOrdersListPage(),
          ),
          GoRoute(
            path: '/purchases/manual',
            builder: (context, state) => const PurchaseManualPage(),
          ),
          GoRoute(
            path: '/purchases/new',
            builder: (context, state) => const PurchaseOrderCreateManualPage(),
          ),
          GoRoute(
            path: '/suppliers',
            builder: (context, state) => const SuppliersListPage(),
          ),
          GoRoute(
            path: '/suppliers/new',
            builder: (context, state) => const SupplierRegistrationPage(),
          ),
          // Alias legacy: mantener el listado original accesible.
          GoRoute(
            path: '/purchases/list',
            builder: (context, state) => const PurchaseOrdersListPage(),
          ),
          GoRoute(
            path: '/purchases/orders',
            builder: (context, state) => const PurchaseOrdersPage(),
          ),
          GoRoute(
            path: '/purchases/edit/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              return PurchaseOrderCreateManualPage(orderId: id);
            },
          ),
          GoRoute(
            path: '/purchases/auto',
            builder: (context, state) => const PurchaseAutoPage(),
          ),
          // Auto legacy (pantalla anterior)
          GoRoute(
            path: '/purchases/auto-legacy',
            builder: (context, state) => const PurchaseOrderCreateAutoPage(),
          ),
          GoRoute(
            path: '/purchases/receive/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              return PurchaseOrderReceivePage(orderId: id ?? 0);
            },
          ),
        ],
      ),
    ],
  );
});

bool _isGateCacheFresh() {
  final at = _licenseGateCachedAt;
  if (at == null) return false;
  final age = DateTime.now().difference(at);
  final cached = _licenseGateCached;
  // Cuando la licencia está activa, no queremos quedarnos “pegados” demasiado
  // tiempo si la nube la revoca/elimina. Reducimos la ventana del cache para
  // permitir detectar el cambio casi al instante (vía heartbeat + polling).
  final maxAge = (cached?.isActive ?? false)
      ? _kActiveGateDecisionCacheWindow
      : _kInactiveGateDecisionCacheWindow;
  return age < maxAge;
}

void _refreshLicenseGateInBackground() {
  if (_licenseGateInFlight != null) return;
  unawaited(
    _getLicenseGateDecision().then((gate) {
      final before = _licenseGateCached;
      _licenseGateCached = gate;
      _licenseGateCachedAt = DateTime.now();
      _licenseGateCachedEpoch = licenseGateRefreshToken.value;

      // Si cambia el estado, forzar re-evaluar redirects sin reiniciar.
      if (before == null ||
          before.isActive != gate.isActive ||
          before.isBlocked != gate.isBlocked ||
          before.code != gate.code) {
        bumpLicenseGateRefresh();
      }
    }),
  );
}

Future<_LicenseGateDecision> _getLicenseGateDecisionFast() async {
  final cached = _licenseGateCached;
  if (cached != null) {
    // Si algún flujo externo (ej: iniciar prueba) solicita refresh,
    // invalidamos la decisión cacheada de inmediato.
    if (_licenseGateCachedEpoch != licenseGateRefreshToken.value) {
      final gate = await _getLicenseGateDecision();
      _licenseGateCached = gate;
      _licenseGateCachedAt = DateTime.now();
      _licenseGateCachedEpoch = licenseGateRefreshToken.value;
      return gate;
    }

    if (!_isGateCacheFresh()) {
      _refreshLicenseGateInBackground();
    }
    return cached;
  }

  final gate = await _getLicenseGateDecision();
  _licenseGateCached = gate;
  _licenseGateCachedAt = DateTime.now();
  _licenseGateCachedEpoch = licenseGateRefreshToken.value;
  return gate;
}

class _NoAccessRoutePage extends StatelessWidget {
  final String requestedPath;

  const _NoAccessRoutePage({required this.requestedPath});

  Future<_NoAccessRouteData> _load() async {
    final isAdmin = await SessionManager.isAdmin();
    final permissions = await AuthRepository.getCurrentPermissions();
    return _NoAccessRouteData(isAdmin: isAdmin, permissions: permissions);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_NoAccessRouteData>(
      future: _load(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return NoAccessPage(
          requestedPath: requestedPath,
          isAdmin: data.isAdmin,
          permissions: data.permissions,
        );
      },
    );
  }
}

class _NoAccessRouteData {
  final bool isAdmin;
  final UserPermissions permissions;

  const _NoAccessRouteData({required this.isAdmin, required this.permissions});
}

class _RouterHeartbeat extends ChangeNotifier {
  late final Timer _timer;

  _RouterHeartbeat(Duration interval) {
    _timer = Timer.periodic(interval, (_) => notifyListeners());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}

class _MergedListenable extends ChangeNotifier {
  final List<Listenable> _listenables;

  _MergedListenable(this._listenables) {
    for (final l in _listenables) {
      l.addListener(notifyListeners);
    }
  }

  @override
  void dispose() {
    for (final l in _listenables) {
      l.removeListener(notifyListeners);
    }
    super.dispose();
  }
}

class _LicenseGateDecision {
  final bool isActive;
  final bool isBlocked;
  final String? code;

  const _LicenseGateDecision({
    required this.isActive,
    required this.isBlocked,
    required this.code,
  });
}

Future<_LicenseGateDecision> _getLicenseGateDecision() async {
  // Evita disparar múltiples requests en paralelo cuando el router refresca
  // frecuentemente. Todas las llamadas concurrentes comparten el mismo Future.
  final inFlight = _licenseGateInFlight;
  if (inFlight != null) return inFlight;

  final future = _getLicenseGateDecisionImpl();
  _licenseGateInFlight = future;
  future.whenComplete(() {
    if (identical(_licenseGateInFlight, future)) {
      _licenseGateInFlight = null;
    }
  });
  return future;
}

Future<_LicenseGateDecision> _getLicenseGateDecisionImpl() async {
  // En widget tests no debe haber dependencia de red/licencias.
  if (const bool.fromEnvironment('FLUTTER_TEST')) {
    return const _LicenseGateDecision(
      isActive: true,
      isBlocked: false,
      code: 'TEST',
    );
  }

  // 1) OFFLINE-FIRST: si existe %APPDATA%/FullPOS/license.dat y es válida,
  // permitir acceso sin red y sin device_id.
  final businessSync = BusinessLicenseSync();
  final storage = LicenseStorage();

  // Nuevo flujo por negocio: si existe businessId, Apyra/backend manda sobre
  // cualquier token local. Esto evita que un license.dat viejo deje entrar
  // cuando la licencia ya figura vencida/eliminada en Apyra.
  final identityStorage = BusinessIdentityStorage();
  var businessId = await identityStorage.getBusinessId();
  var currentBusinessId = (businessId ?? '').trim();
  if (currentBusinessId.isEmpty) {
    final restored = await IdentityRecoveryBundle.instance
        .recoverToSharedPreferences('router_initial_business_id_missing');
    if (restored) {
      businessId = await identityStorage.getBusinessId();
      currentBusinessId = (businessId ?? '').trim();
      await IdentityRecoveryBundle.instance.log(
        'router_restored_business_id_from_bundle',
      );
    }
  }
  if (currentBusinessId.isNotEmpty) {
    await businessSync.tryPollFromCloudIfDue(
      minInterval: Duration.zero,
      ignoreMinInterval: true,
      networkTimeout: const Duration(seconds: 4),
    );

    await businessSync.applyLocalLicenseIfValid();
    final info = await storage.getLastInfo();

    if (info?.isBlocked == true) {
      return _LicenseGateDecision(
        isActive: false,
        isBlocked: true,
        code: info?.code,
      );
    }

    if (info?.isActive == true && info?.isExpired == false) {
      _runCloudRevocationCheckInBackground(businessSync);
      return const _LicenseGateDecision(
        isActive: true,
        isBlocked: false,
        code: 'OK',
      );
    }

    return _LicenseGateDecision(
      isActive: false,
      isBlocked: false,
      code: info?.code ?? 'NO_LICENSE',
    );
  }

  var hasValidLocalToken = await businessSync.applyLocalLicenseIfValid();
  if (!hasValidLocalToken && currentBusinessId.isEmpty) {
    final recoveredFromFile = await businessSync
        .recoverIdentityFromLocalLicenseFile(
          reason: 'router_missing_business_id',
        );
    if (recoveredFromFile) {
      businessId = await identityStorage.getBusinessId();
      currentBusinessId = (businessId ?? '').trim();
      hasValidLocalToken = await businessSync.applyLocalLicenseIfValid();
      if (currentBusinessId.isNotEmpty && hasValidLocalToken) {
        return const _LicenseGateDecision(
          isActive: true,
          isBlocked: false,
          code: 'OK',
        );
      }
    }
  }

  // Si el token local representa un bloqueo, debe ganar sobre TRIAL.
  final cachedAfterLocal = await storage.getLastInfo();
  if (cachedAfterLocal?.isBlocked == true) {
    // IMPORTANTE:
    // Si el admin desbloquea en el servidor, el cliente debe poder “salir” del
    // bloqueo sin borrar datos locales. Antes, este branch retornaba bloqueado
    // sin re-consultar la nube, dejando la app atrapada.
    final now = DateTime.now();
    final lastProbe = _blockedCloudProbeAt;
    final canProbe =
        lastProbe == null ||
        now.difference(lastProbe) >= _kBlockedGateProbeInterval;

    if (canProbe && _blockedCloudProbeInFlight == null) {
      _blockedCloudProbeAt = now;
      _blockedCloudProbeInFlight = businessSync
          .tryPollFromCloudIfDue(
            minInterval: Duration.zero,
            ignoreMinInterval: true,
            networkTimeout: const Duration(seconds: 2),
          )
          .catchError((_) => false)
          .whenComplete(() {
            _blockedCloudProbeInFlight = null;
          });

      // Esperar a que termine este intento rápido.
      await _blockedCloudProbeInFlight;
    }

    // Si el poll trajo una licencia ACTIVA, salir del bloqueo.
    final refreshed = await storage.getLastInfo();
    if (refreshed != null &&
        !refreshed.isBlocked &&
        refreshed.isActive &&
        !refreshed.isExpired) {
      return const _LicenseGateDecision(
        isActive: true,
        isBlocked: false,
        code: 'OK',
      );
    }

    return _LicenseGateDecision(
      isActive: false,
      isBlocked: true,
      code: cachedAfterLocal?.code,
    );
  }

  // Importante: la app NO debe depender de internet.
  // Si hay token local válido, permitimos acceso inmediatamente.
  // A la vez, en segundo plano consultamos la nube para detectar
  // eliminaciones/bloqueos y aplicar el cambio sin reiniciar.
  if (hasValidLocalToken) {
    _runCloudRevocationCheckInBackground(businessSync);
    return const _LicenseGateDecision(
      isActive: true,
      isBlocked: false,
      code: 'OK',
    );
  }

  // 2) Sin token local válido: intentar sincronizar desde la nube.
  await businessSync.tryPollFromCloudIfDue(
    minInterval: _kInactiveCloudGateMinPollInterval,
    networkTimeout: const Duration(seconds: 2),
  );
  if (await businessSync.applyLocalLicenseIfValid()) {
    return const _LicenseGateDecision(
      isActive: true,
      isBlocked: false,
      code: 'OK',
    );
  }

  final cachedAfterPoll = await storage.getLastInfo();
  if (cachedAfterPoll?.isBlocked == true) {
    return _LicenseGateDecision(
      isActive: false,
      isBlocked: true,
      code: cachedAfterPoll?.code,
    );
  }
  if (cachedAfterPoll?.isExpired == true) {
    return _LicenseGateDecision(
      isActive: false,
      isBlocked: false,
      code: cachedAfterPoll?.code ?? 'EXPIRED',
    );
  }

  // 3) TRIAL offline-first: permitir acceso durante 5 días desde el inicio.
  // Esto evita depender del endpoint legacy /start-demo (device_id).
  final cloudDeniedAt = await storage.getCloudDeniedAt();
  final trialStart = await identityStorage.getTrialStart();
  if (trialStart != null) {
    final now = DateTime.now().toUtc();
    final expires = trialStart.toUtc().add(kLocalTrialDuration);
    if (now.isBefore(expires)) {
      // Si el backend explícitamente respondió 204 (sin licencia) luego de
      // iniciada la prueba, NO permitir que el TRIAL local la ignore.
      if (cloudDeniedAt != null && cloudDeniedAt.isAfter(trialStart.toUtc())) {
        // Continuar flujo normal: terminará en pantalla de licencia.
      } else {
        return const _LicenseGateDecision(
          isActive: true,
          isBlocked: false,
          code: 'TRIAL',
        );
      }
    }
  }

  // Si ya existe business_id (nuevo flujo), NO debemos re-activar por device_id
  // ni por licenseKey legacy; eso haría que una licencia eliminada en la nube
  // vuelva a aparecer automáticamente.
  final cached = await storage.getLastInfo();
  var resolvedBusinessId = (businessId ?? '').trim();
  final cachedBusinessId = (cached?.businessId ?? '').trim();
  if (resolvedBusinessId.isEmpty && cachedBusinessId.isNotEmpty) {
    try {
      final restored = await BusinessIdentityGuard.resolveAndApply(
        storage: identityStorage,
        incomingBusinessId: cachedBusinessId,
        source: 'router_license_gate',
        allowInitialSet: false,
        allowRestoreWhenLocalMissing: true,
        allowOverwrite: false,
      );
      resolvedBusinessId = restored.trim();
    } on BusinessIdentityConflictException {
      resolvedBusinessId = '';
    }
  }
  final hasBusinessId = resolvedBusinessId.isNotEmpty;
  final canonicalBusinessId = hasBusinessId ? resolvedBusinessId : null;

  String? businessIdFromMap(Map<String, dynamic> map) {
    final candidate = (map['business_id'] ?? '').toString().trim();
    if (candidate.isNotEmpty) return candidate;
    final camelCandidate = (map['businessId'] ?? '').toString().trim();
    if (camelCandidate.isNotEmpty) return camelCandidate;
    final business = map['business'];
    if (business is Map) {
      final nestedBusinessId = (business['business_id'] ?? '')
          .toString()
          .trim();
      if (nestedBusinessId.isNotEmpty) return nestedBusinessId;
      final nestedCamel = (business['businessId'] ?? '').toString().trim();
      if (nestedCamel.isNotEmpty) return nestedCamel;
      final nestedId = (business['id'] ?? '').toString().trim();
      if (nestedId.isNotEmpty) return nestedId;
    }
    return canonicalBusinessId;
  }

  if (hasBusinessId) {
    if (cached != null) {
      if (cached.isBlocked) {
        return _LicenseGateDecision(
          isActive: false,
          isBlocked: true,
          code: cached.code,
        );
      }
      if (cached.isActive && !cached.isExpired) {
        return const _LicenseGateDecision(
          isActive: true,
          isBlocked: false,
          code: 'OK',
        );
      }
    }

    return const _LicenseGateDecision(
      isActive: false,
      isBlocked: false,
      code: 'NO_LICENSE',
    );
  }

  final recoveryRequired = await IdentityRecoveryBundle.instance
      .isRecoveryRequired();
  final priorInstallation = await IdentityRecoveryBundle.instance
      .hasPriorInstallationEvidence();
  if (recoveryRequired || priorInstallation) {
    await IdentityRecoveryBundle.instance.markRecoveryRequired(
      recoveryRequired
          ? 'router_recovery_required'
          : 'router_prevented_legacy_prior_installation',
    );
    await IdentityRecoveryBundle.instance.log(
      'router_legacy_device_flow_blocked '
      'recoveryRequired=$recoveryRequired priorInstallation=$priorInstallation',
    );
    return const _LicenseGateDecision(
      isActive: false,
      isBlocked: false,
      code: 'RECOVERY_REQUIRED',
    );
  }

  String deviceId;
  try {
    deviceId =
        (await storage.getDeviceId()) ??
        await SessionManager.ensureTerminalId();
  } on IdentityRecoveryException {
    return const _LicenseGateDecision(
      isActive: false,
      isBlocked: false,
      code: 'RECOVERY_REQUIRED',
    );
  }
  await storage.setDeviceId(deviceId);

  Future<_LicenseGateDecision?> tryAutoActivate() async {
    try {
      final map = await LicenseApi().autoActivateByDevice(
        baseUrl: kLicenseBackendBaseUrl,
        deviceId: deviceId,
        projectCode: kFullposProjectCode,
      );

      final ok = map['ok'] == true;
      final code = map['code']?.toString();
      final estado = map['estado']?.toString();
      final motivo = (map['motivo'] ?? map['notas'] ?? map['motivo_bloqueo'])
          ?.toString();

      // Si devuelve una nueva licencia, persistirla para que el POS ya quede actualizado.
      final resolvedKey = (map['license_key'] ?? '').toString().trim();
      if (resolvedKey.isNotEmpty) {
        await storage.setLicenseKey(resolvedKey);
      }

      if (!ok) {
        final isBlocked =
            (estado ?? '').toUpperCase() == 'BLOQUEADA' ||
            (code ?? '').toUpperCase() == 'BLOCKED';

        if (isBlocked) {
          final info = LicenseInfo(
            backendBaseUrl: kLicenseBackendBaseUrl,
            licenseKey: resolvedKey.isNotEmpty
                ? resolvedKey
                : (await storage.getLicenseKey()) ?? '',
            deviceId: deviceId,
            projectCode: kFullposProjectCode,
            businessId: businessIdFromMap(map),
            ok: false,
            code: code,
            estado: 'BLOQUEADA',
            motivo: motivo,
            lastCheckedAt: DateTime.now(),
          );
          await storage.setLastInfo(info);
          return _LicenseGateDecision(
            isActive: false,
            isBlocked: true,
            code: code,
          );
        }

        // No hay licencia activa para este device/cliente.
        return null;
      }

      final info = LicenseInfo(
        backendBaseUrl: kLicenseBackendBaseUrl,
        licenseKey: resolvedKey.isNotEmpty
            ? resolvedKey
            : (await storage.getLicenseKey()) ?? '',
        deviceId: deviceId,
        projectCode: kFullposProjectCode,
        businessId: businessIdFromMap(map),
        ok: true,
        code: code,
        tipo: map['tipo']?.toString(),
        estado: estado ?? 'ACTIVA',
        motivo: motivo,
        fechaInicio: DateTime.tryParse((map['fecha_inicio'] ?? '').toString()),
        fechaFin: DateTime.tryParse((map['fecha_fin'] ?? '').toString()),
        maxDispositivos: int.tryParse(
          (map['max_dispositivos'] ?? '').toString(),
        ),
        usados: int.tryParse((map['usados'] ?? '').toString()),
        lastCheckedAt: DateTime.now(),
      );
      await storage.setLastInfo(info);

      if (info.isActive && !info.isExpired) {
        return const _LicenseGateDecision(
          isActive: true,
          isBlocked: false,
          code: 'OK',
        );
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  bool isFresh(DateTime? lastCheckedAt) {
    if (lastCheckedAt == null) return false;
    final age = DateTime.now().difference(lastCheckedAt);
    return age < kLicenseGateFreshWindow;
  }

  if (cached != null) {
    if (cached.isExpired) {
      final auto = await tryAutoActivate();
      if (auto != null) return auto;

      return const _LicenseGateDecision(
        isActive: false,
        isBlocked: false,
        code: 'EXPIRED',
      );
    }
    if (cached.isActive && isFresh(cached.lastCheckedAt)) {
      return const _LicenseGateDecision(
        isActive: true,
        isBlocked: false,
        code: 'OK',
      );
    }
    if (cached.isBlocked && isFresh(cached.lastCheckedAt)) {
      return _LicenseGateDecision(
        isActive: false,
        isBlocked: true,
        code: cached.code,
      );
    }
  }

  final licenseKey = await storage.getLicenseKey();
  if (licenseKey == null || licenseKey.trim().isEmpty) {
    final auto = await tryAutoActivate();
    if (auto != null) return auto;
    return const _LicenseGateDecision(
      isActive: false,
      isBlocked: false,
      code: 'NO_KEY',
    );
  }

  try {
    final map = await LicenseApi().check(
      baseUrl: kLicenseBackendBaseUrl,
      licenseKey: licenseKey.trim(),
      deviceId: deviceId,
      projectCode: kFullposProjectCode,
    );

    final checkCode = (map['code'] ?? '').toString().trim().toUpperCase();

    final info = LicenseInfo(
      backendBaseUrl: kLicenseBackendBaseUrl,
      licenseKey: licenseKey.trim(),
      deviceId: deviceId,
      projectCode: kFullposProjectCode,
      businessId: businessIdFromMap(map),
      ok: map['ok'] == true,
      code: map['code']?.toString(),
      tipo: map['tipo']?.toString(),
      estado: map['estado']?.toString(),
      motivo: (map['motivo'] ?? map['notas'] ?? map['motivo_bloqueo'])
          ?.toString(),
      fechaInicio: DateTime.tryParse((map['fecha_inicio'] ?? '').toString()),
      fechaFin: DateTime.tryParse((map['fecha_fin'] ?? '').toString()),
      lastCheckedAt: DateTime.now(),
    );
    await storage.setLastInfo(info);

    // Licencia ONLINE: si la licencia existe pero este dispositivo aún no está activado,
    // check() típicamente devuelve NOT_FOUND. En ese caso intentamos activar automáticamente
    // para crear la activación y permitir entrar sin pasos extra.
    if (checkCode == 'NOT_FOUND') {
      try {
        final activated = await LicenseApi().activate(
          baseUrl: kLicenseBackendBaseUrl,
          licenseKey: licenseKey.trim(),
          deviceId: deviceId,
          projectCode: kFullposProjectCode,
        );

        final actInfo = LicenseInfo(
          backendBaseUrl: kLicenseBackendBaseUrl,
          licenseKey: licenseKey.trim(),
          deviceId: deviceId,
          projectCode: kFullposProjectCode,
          businessId: businessIdFromMap(activated),
          ok: activated['ok'] == true,
          code: activated['code']?.toString(),
          tipo: activated['tipo']?.toString(),
          estado: activated['estado']?.toString(),
          motivo:
              (activated['motivo'] ??
                      activated['notas'] ??
                      activated['motivo_bloqueo'])
                  ?.toString(),
          fechaInicio: DateTime.tryParse(
            (activated['fecha_inicio'] ?? '').toString(),
          ),
          fechaFin: DateTime.tryParse(
            (activated['fecha_fin'] ?? '').toString(),
          ),
          maxDispositivos: int.tryParse(
            (activated['max_dispositivos'] ?? '').toString(),
          ),
          usados: int.tryParse((activated['usados'] ?? '').toString()),
          lastCheckedAt: DateTime.now(),
        );
        await storage.setLastInfo(actInfo);

        if (actInfo.isActive && !actInfo.isExpired) {
          return const _LicenseGateDecision(
            isActive: true,
            isBlocked: false,
            code: 'OK',
          );
        }
      } catch (_) {
        // Si no se puede activar automáticamente, se conserva el resultado del check.
      }

      // Si la clave actual ya no aplica (ej: DEMO terminó y se creó FULL nueva),
      // intentar resolver automáticamente por device_id.
      final auto = await tryAutoActivate();
      if (auto != null) return auto;
    }

    // DEMO vencida / licencia vieja: intentar auto-resolver FULL por device_id.
    if (checkCode == 'EXPIRED') {
      final auto = await tryAutoActivate();
      if (auto != null) return auto;
    }

    if (info.isBlocked) {
      return _LicenseGateDecision(
        isActive: false,
        isBlocked: true,
        code: info.code,
      );
    }
    if (info.isActive && !info.isExpired) {
      return const _LicenseGateDecision(
        isActive: true,
        isBlocked: false,
        code: 'OK',
      );
    }
    return _LicenseGateDecision(
      isActive: false,
      isBlocked: false,
      code: info.code,
    );
  } catch (_) {
    // Falla de red: conservar el último estado local si es utilizable.
    if (cached != null) {
      if (cached.isBlocked) {
        return _LicenseGateDecision(
          isActive: false,
          isBlocked: true,
          code: cached.code,
        );
      }
      if (cached.isActive && !cached.isExpired) {
        return const _LicenseGateDecision(
          isActive: true,
          isBlocked: false,
          code: 'OK',
        );
      }
    }
    return const _LicenseGateDecision(
      isActive: false,
      isBlocked: false,
      code: 'UNKNOWN',
    );
  }
}
