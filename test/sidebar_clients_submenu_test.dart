import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fullpos/core/layout/sidebar.dart';

void main() {
  Finder parentClientesFinder() => find.byWidgetPredicate(
    (widget) =>
        widget is PremiumNavItem &&
        widget.title == 'Clientes' &&
        widget.route == null,
  );

  Finder parentAdministracionFinder() => find.byWidgetPredicate(
    (widget) =>
        widget is PremiumNavItem &&
        widget.title == 'Administración' &&
        widget.route == null,
  );

  Finder childFinder(String title, String route) => find.byWidgetPredicate(
    (widget) =>
        widget is PremiumNavItem && widget.title == title && widget.route == route,
  );

  bool hasActiveGradient(WidgetTester tester, Finder navItemFinder) {
    final containers = tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: navItemFinder,
        matching: find.byType(AnimatedContainer),
      ),
    );

    return containers.any((container) {
      final decoration = container.decoration;
      return decoration is BoxDecoration && decoration.gradient != null;
    });
  }

  Future<void> pumpSidebar(WidgetTester tester, {String initialLocation = '/sales'}) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/sales',
          builder: (context, state) => _SidebarHarness(currentPath: state.uri.path),
        ),
        GoRoute(
          path: '/clients',
          builder: (context, state) => _SidebarHarness(currentPath: state.uri.path),
        ),
        GoRoute(
          path: '/quotes-list',
          builder: (context, state) => _SidebarHarness(currentPath: state.uri.path),
        ),
        GoRoute(
          path: '/credits-list',
          builder: (context, state) => _SidebarHarness(currentPath: state.uri.path),
        ),
        GoRoute(
          path: '/purchases',
          builder: (context, state) => _SidebarHarness(currentPath: state.uri.path),
        ),
        GoRoute(
          path: '/cash/expenses',
          builder: (context, state) => _SidebarHarness(currentPath: state.uri.path),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('submenu de clientes expande y colapsa correctamente', (tester) async {
    await pumpSidebar(tester);

    expect(childFinder('Cotizaciones', '/quotes-list'), findsOneWidget);
    expect(childFinder('Créditos', '/credits-list'), findsOneWidget);

    await tester.tap(find.text('Clientes').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(childFinder('Cotizaciones', '/quotes-list'), findsNothing);
    expect(childFinder('Créditos', '/credits-list'), findsNothing);

    await tester.tap(find.text('Clientes').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(childFinder('Cotizaciones', '/quotes-list'), findsOneWidget);
    expect(childFinder('Créditos', '/credits-list'), findsOneWidget);
  });

  testWidgets('navega a clientes cotizaciones y creditos', (tester) async {
    await pumpSidebar(tester);

    await tester.tap(find.text('Cotizaciones'));
    await tester.pumpAndSettle();
    expect(find.text('Ruta actual: /quotes-list'), findsOneWidget);

    await tester.tap(find.text('Créditos'));
    await tester.pumpAndSettle();
    expect(find.text('Ruta actual: /credits-list'), findsOneWidget);

    await tester.tap(find.text('Clientes').last);
    await tester.pumpAndSettle();
    expect(find.text('Ruta actual: /clients'), findsOneWidget);
  });

  testWidgets('resalta item activo y mantiene el padre activo cuando un hijo esta activo', (
    tester,
  ) async {
    await pumpSidebar(tester, initialLocation: '/quotes-list');

    final parentFinder = parentClientesFinder();
    final quotesFinder = childFinder('Cotizaciones', '/quotes-list');

    expect(parentFinder, findsOneWidget);
    expect(quotesFinder, findsOneWidget);
    expect(hasActiveGradient(tester, parentFinder), isTrue);
    expect(hasActiveGradient(tester, quotesFinder), isTrue);
  });

  testWidgets('usa animaciones suaves para el submenu', (tester) async {
    await pumpSidebar(tester);

    expect(find.byType(AnimatedSize), findsWidgets);
    expect(find.byType(AnimatedRotation), findsWidgets);
  });

  testWidgets('muestra indicador visual de submenu en clientes y administracion', (
    tester,
  ) async {
    await pumpSidebar(tester);

    expect(
      find.descendant(
        of: parentClientesFinder(),
        matching: find.byKey(const Key('submenu-badge-Clientes')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: parentAdministracionFinder(),
        matching: find.byKey(const Key('submenu-badge-Administración')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('submenu de administracion expande y colapsa correctamente', (
    tester,
  ) async {
    await pumpSidebar(tester);

    expect(childFinder('Compras', '/purchases'), findsOneWidget);
    expect(childFinder('Gastos', '/cash/expenses'), findsOneWidget);

    await tester.tap(find.text('Administración'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(childFinder('Compras', '/purchases'), findsNothing);
    expect(childFinder('Gastos', '/cash/expenses'), findsNothing);

    await tester.tap(find.text('Administración'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(childFinder('Compras', '/purchases'), findsOneWidget);
    expect(childFinder('Gastos', '/cash/expenses'), findsOneWidget);
  });
}

class _SidebarHarness extends StatelessWidget {
  final String currentPath;

  const _SidebarHarness({required this.currentPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const SizedBox(
            width: 280,
            child: Sidebar(
              forcedCollapsed: false,
            ),
          ),
          Expanded(
            child: Center(
              child: Text('Ruta actual: $currentPath'),
            ),
          ),
        ],
      ),
    );
  }
}