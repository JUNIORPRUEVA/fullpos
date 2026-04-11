import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fullpos/core/bootstrap/app_bootstrap_controller.dart';
import 'package:fullpos/core/errors/error_handler.dart';
import 'package:fullpos/core/session/session_manager.dart';
import 'package:fullpos/features/auth/services/logout_flow_service.dart';

class _TestAppBootstrapController extends AppBootstrapController {
  _TestAppBootstrapController(super.ref);

  @override
  void ensureStarted() {}

  @override
  Future<void> retry() async {}

  @override
  Future<void> refreshAuth() async {}
}

GoRouter _buildRouter() {
  return GoRouter(
    navigatorKey: ErrorHandler.navigatorKey,
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('home')),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('login')),
        ),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SessionManager.logout();
  });

  testWidgets(
    'defaultPerformLogout clears session and routes to login',
    (tester) async {
      await SessionManager.login(
        userId: 1,
        username: 'admin',
        displayName: 'Admin',
        role: 'admin',
        companyId: 1,
        terminalId: 'test-terminal',
      );

      final router = _buildRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWith(
              (ref) => _TestAppBootstrapController(ref),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(find.text('home'), findsOneWidget);
      expect(await SessionManager.isLoggedIn(), isTrue);

      final context = tester.element(find.text('home'));
      await LogoutFlowService.defaultPerformLogout(context);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(await SessionManager.isLoggedIn(), isFalse);
      expect(find.text('login'), findsOneWidget);
    },
  );
}