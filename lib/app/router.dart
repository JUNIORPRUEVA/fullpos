import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';

import '../core/bootstrap/app_bootstrap_controller.dart';
import '../core/brand/fullpos_brand_theme.dart';
import '../core/errors/error_handler.dart';
import '../core/layout/app_shell.dart';
import '../core/security/authz/permission_gate.dart';
import '../core/security/authz/permission.dart';
import '../features/account/ui/account_page.dart';
import '../features/auth/ui/login_page.dart';
import '../features/auth/ui/force_change_password_page.dart';
import '../features/auth/services/first_run_auth_flags.dart';
import '../features/cash/ui/cash_box_page.dart';
import '../features/cash/ui/cash_history_page.dart';
import '../features/cash/ui/expenses_overview_page.dart';
import '../features/clients/ui/clients_page.dart';
import '../features/products/ui/add_stock_page.dart';
import '../features/products/ui/products_page.dart';
import '../features/products/ui/stock_history_page.dart';
import '../features/purchases/ui/purchase_auto_page.dart';
import '../features/purchases/ui/purchase_manual_page.dart';
import '../features/purchases/ui/purchase_mode_selector_page.dart';
import '../features/purchases/ui/purchase_orders_page.dart';
import '../features/purchases/ui/purchase_order_create_auto_page.dart';
import '../features/purchases/ui/purchase_order_create_manual_page.dart';
import '../features/purchases/ui/purchase_order_receive_page.dart';
import '../features/purchases/ui/purchase_orders_list_page.dart';
import '../features/reports/ui/reports_page.dart';
import '../features/sales/ui/credits_page.dart';
import '../features/sales/ui/quotes_page.dart';
import '../features/sales/ui/returns_list_page.dart';
import '../features/sales/ui/sales_list_page.dart';
import '../features/sales/ui/sales_page.dart';
import '../features/settings/ui/printer_settings_page.dart';
import '../features/settings/ui/logs_page.dart';
import '../features/settings/ui/backup_settings_page.dart';
import '../features/settings/ui/settings_page.dart';
import '../features/tools/ui/ncf_page.dart';
import '../features/tools/ui/tools_page.dart';
import '../features/license/ui/license_page.dart';
import '../features/license/ui/license_blocked_page.dart';
import '../features/license/services/license_storage.dart';
import '../features/license/services/license_api.dart';
import '../features/license/data/license_models.dart';
import '../features/license/license_config.dart';
import '../core/session/session_manager.dart';

Future<_LicenseGateDecision>? _licenseGateInFlight;
_LicenseGateDecision? _licenseGateCached;
DateTime? _licenseGateCachedAt;

// Notificador para forzar refresh del router cuando se refresca el gate en background.
final ValueNotifier<int> _licenseGateRefreshToken = ValueNotifier<int>(0);

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
    _licenseGateRefreshToken,
  ]);
  ref.onDispose(() {
    refresh.dispose();
    heartbeat.dispose();
  });

  return GoRouter(
    navigatorKey: ErrorHandler.navigatorKey,
    // Nota: La pantalla de arranque se maneja fuera del router (AppEntry).
    // Mantener una ruta inicial estable evita “rebotes” visuales.
    initialLocation: isLoggedIn ? '/sales' : '/login',
    refreshListenable: refresh,
    redirect: (context, state) async {
      final path = state.uri.path;
      final isOnLogin = path == '/login';
      final isOnForceChangePassword = path == '/force-change-password';
      final isOnPublicLicense = path == '/license';
      final isOnSettingsLicense = path == '/settings/license';
      final isOnBlocked = path == '/license-blocked';

      // Mientras el bootstrap corre, no redirigir rutas: AppEntry muestra Splash/Error.
      if (bootStatus != BootStatus.ready) return null;

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
        return isOnBlocked ? null : '/license-blocked';
      }

      // Sin licencia válida (revocada/eliminada/vencida/etc): mostrar pantalla normal.
      if (!gate.isActive) {
        return isOnPublicLicense ? null : '/license';
      }

      // Con licencia activa, no permitir volver a la pantalla de licencia/bloqueo.
      if (isOnPublicLicense || isOnSettingsLicense || isOnBlocked) {
        return isLoggedIn ? '/sales' : '/login';
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
        if (isOnForceChangePassword) return '/sales';
      }

      // Mantener UI idéntica: no redirigir por permisos.
      if (isOnLogin) return '/sales';

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const FullposBrandScope(child: LoginPage()),
      ),
      GoRoute(
        path: '/force-change-password',
        builder: (context, state) =>
            const FullposBrandScope(child: ForceChangePasswordPage()),
      ),
      GoRoute(
        path: '/license',
        builder: (context, state) =>
            const FullposBrandScope(child: LicensePage()),
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
            path: '/sales',
            builder: (context, state) => const SalesPage(),
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const ProductsPage(),
          ),
          GoRoute(
            path: '/products/history',
            builder: (context, state) => const StockHistoryPage(),
          ),
          GoRoute(
            path: '/products/add-stock/:productId',
            builder: (context, state) {
              final productId = int.parse(
                state.pathParameters['productId'] ?? '0',
              );
              return AddStockPage(productId: productId);
            },
          ),
          GoRoute(
            path: '/clients',
            builder: (context, state) => const ClientsPage(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => PermissionGate(
              permission: Permissions.reportsView,
              autoPromptOnce: true,
              reason: 'Acceso a reportes',
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
          GoRoute(path: '/ncf', builder: (context, state) => const NcfPage()),
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
            path: '/sales-list',
            builder: (context, state) => const SalesListPage(),
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
            path: '/returns',
            builder: (context, state) => PermissionGate(
              permission: Permissions.returnsView,
              autoPromptOnce: false,
              reason: 'Acceso a devoluciones',
              child: const ReturnsListPage(),
            ),
          ),
          GoRoute(
            path: '/returns-list',
            builder: (context, state) => PermissionGate(
              permission: Permissions.returnsView,
              autoPromptOnce: false,
              reason: 'Acceso a devoluciones',
              child: const ReturnsListPage(),
            ),
          ),
          GoRoute(
            path: '/credits',
            builder: (context, state) => PermissionGate(
              permission: Permissions.creditsView,
              autoPromptOnce: false,
              reason: 'Acceso a creditos',
              child: const CreditsPage(),
            ),
          ),
          GoRoute(
            path: '/credits-list',
            builder: (context, state) => PermissionGate(
              permission: Permissions.creditsView,
              autoPromptOnce: false,
              reason: 'Acceso a creditos',
              child: const CreditsPage(),
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
            builder: (context, state) => const PurchaseModeSelectorPage(),
          ),
          GoRoute(
            path: '/purchases/manual',
            builder: (context, state) => const PurchaseManualPage(),
          ),
          GoRoute(
            path: '/purchases/new',
            builder: (context, state) => const PurchaseOrderCreateManualPage(),
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
  return age < kLicenseGateFreshWindow;
}

void _refreshLicenseGateInBackground() {
  if (_licenseGateInFlight != null) return;
  unawaited(
    _getLicenseGateDecision().then((gate) {
      final before = _licenseGateCached;
      _licenseGateCached = gate;
      _licenseGateCachedAt = DateTime.now();

      // Si cambia el estado, forzar re-evaluar redirects sin reiniciar.
      if (before == null ||
          before.isActive != gate.isActive ||
          before.isBlocked != gate.isBlocked ||
          before.code != gate.code) {
        _licenseGateRefreshToken.value++;
      }
    }),
  );
}

Future<_LicenseGateDecision> _getLicenseGateDecisionFast() async {
  final cached = _licenseGateCached;
  if (cached != null) {
    if (!_isGateCacheFresh()) {
      _refreshLicenseGateInBackground();
    }
    return cached;
  }

  final gate = await _getLicenseGateDecision();
  _licenseGateCached = gate;
  _licenseGateCachedAt = DateTime.now();
  return gate;
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

  final storage = LicenseStorage();
  final cached = await storage.getLastInfo();

  final deviceId =
      (await storage.getDeviceId()) ?? await SessionManager.ensureTerminalId();
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
