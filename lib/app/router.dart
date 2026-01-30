import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/bootstrap/app_bootstrap_controller.dart';
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

final appRouterProvider = Provider<GoRouter>((ref) {
  final bootstrap = ref.read(appBootstrapProvider);

  return GoRouter(
    navigatorKey: ErrorHandler.navigatorKey,
    // Nota: La pantalla de arranque se maneja fuera del router (AppEntry).
    // Mantener una ruta inicial estable evita “rebotes” visuales.
    initialLocation: '/sales',
    refreshListenable: bootstrap,
    redirect: (context, state) {
      final path = state.uri.path;
      final isOnLogin = path == '/login';

      final boot = bootstrap.snapshot;
      // Mientras el bootstrap corre, no redirigir rutas: AppEntry muestra Splash/Error.
      if (boot.status != BootStatus.ready) return null;

      final isLoggedIn = boot.isLoggedIn;
      if (!isLoggedIn) {
        return isOnLogin ? null : '/login';
      }

      // Mantener UI idéntica: no redirigir por permisos.
      if (isOnLogin) return '/sales';

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
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
