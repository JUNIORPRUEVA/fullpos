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
import '../features/cash/ui/cash_box_page.dart';
import '../features/cash/ui/cash_history_page.dart';
import '../features/cash/ui/expenses_overview_page.dart';
import '../features/clients/ui/clients_page.dart';
import '../features/products/ui/add_stock_page.dart';
import '../features/products/ui/products_page.dart';
import '../features/products/ui/stock_history_page.dart';
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
import '../features/license/services/license_storage.dart';
import '../features/license/services/license_api.dart';
import '../features/license/data/license_models.dart';
import '../features/license/license_config.dart';
import '../core/session/session_manager.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final bootStatus = ref.watch(
    appBootstrapProvider.select((b) => b.snapshot.status),
  );
  final isLoggedIn = ref.watch(
    appBootstrapProvider.select((b) => b.snapshot.isLoggedIn),
  );
  final bootstrap = ref.read(appBootstrapProvider);

  return GoRouter(
    navigatorKey: ErrorHandler.navigatorKey,
    // Nota: La pantalla de arranque se maneja fuera del router (AppEntry).
    // Mantener una ruta inicial estable evita “rebotes” visuales.
    initialLocation: isLoggedIn ? '/sales' : '/login',
    refreshListenable: bootstrap,
    redirect: (context, state) async {
      final path = state.uri.path;
      final isOnLogin = path == '/login';
      final isOnPublicLicense = path == '/license';

      // Mientras el bootstrap corre, no redirigir rutas: AppEntry muestra Splash/Error.
      if (bootStatus != BootStatus.ready) return null;

      // Gate de licencia: si no hay licencia activa, mostrar pantalla de licencia/prueba.
      final hasLicense = await _hasActiveLicense();
      assert(() {
        debugPrint('[LICENSE] gate: hasLicense=$hasLicense path=$path');
        return true;
      }());
      if (!hasLicense) {
        return isOnPublicLicense ? null : '/license';
      }

      assert(() {
        debugPrint(
          '[ROUTER] redirect check: path=$path loggedIn=$isLoggedIn status=$bootStatus',
        );
        return true;
      }());
      if (!isLoggedIn) {
        return (isOnLogin || isOnPublicLicense) ? null : '/login';
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
        path: '/license',
        builder: (context, state) =>
            const FullposBrandScope(child: LicensePage()),
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
            builder: (context, state) => const PurchaseOrdersListPage(),
          ),
          GoRoute(
            path: '/purchases/new',
            builder: (context, state) => const PurchaseOrderCreateManualPage(),
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

Future<bool> _hasActiveLicense() async {
  final storage = LicenseStorage();
  final cached = await storage.getLastInfo();
  if (cached != null && cached.isActive && !cached.isExpired) {
    final last = cached.lastCheckedAt;
    if (last != null) {
      final age = DateTime.now().difference(last);
      if (age.inHours < kLicenseGateRefreshHours) return true;
    } else {
      // Sin timestamp: aceptar por ahora.
      return true;
    }
  }

  final licenseKey = await storage.getLicenseKey();
  if (licenseKey == null || licenseKey.trim().isEmpty) return false;

  final deviceId =
      (await storage.getDeviceId()) ?? await SessionManager.ensureTerminalId();
  await storage.setDeviceId(deviceId);

  try {
    final map = await LicenseApi().check(
      baseUrl: kLicenseBackendBaseUrl,
      licenseKey: licenseKey.trim(),
      deviceId: deviceId,
      projectCode: kFullposProjectCode,
    );

    final info = LicenseInfo(
      backendBaseUrl: kLicenseBackendBaseUrl,
      licenseKey: licenseKey.trim(),
      deviceId: deviceId,
      projectCode: kFullposProjectCode,
      ok: map['ok'] == true,
      code: map['code']?.toString(),
      tipo: map['tipo']?.toString(),
      estado: map['estado']?.toString(),
      fechaInicio: DateTime.tryParse((map['fecha_inicio'] ?? '').toString()),
      fechaFin: DateTime.tryParse((map['fecha_fin'] ?? '').toString()),
      lastCheckedAt: DateTime.now(),
    );
    await storage.setLastInfo(info);

    return info.isActive && !info.isExpired;
  } catch (_) {
    return false;
  }
}
