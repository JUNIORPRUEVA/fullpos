import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/core/security/authz/permission.dart';
import 'package:fullpos/core/security/authz/permission_gate.dart';
import 'package:fullpos/core/session/session_manager.dart';
import 'package:fullpos/features/sales/ui/credits_page.dart';
import 'package:fullpos/features/sales/ui/returns_list_page.dart';
import 'package:fullpos/features/tools/ui/ncf_page.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this._docsDir);

  final Directory _docsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsDir.path;

  @override
  Future<String?> getApplicationSupportPath() async =>
      p.join(_docsDir.path, 'support');
}

GoRouter _buildSmokeRouter() {
  return GoRouter(
    routes: [
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
        path: '/returns',
        builder: (context, state) => PermissionGate(
          permission: Permissions.returnsView,
          autoPromptOnce: false,
          reason: 'Acceso a devoluciones',
          child: const ReturnsListPage(),
        ),
      ),
      GoRoute(path: '/ncf', builder: (context, state) => const NcfPage()),
    ],
    initialLocation: '/credits',
  );
}

Future<void> _seedUsersForTestDb() async {
  final db = await AppDb.database;

  final now = DateTime.now().millisecondsSinceEpoch;

  // Admin user exists via AppDb integrity check, but ensure it here too to
  // avoid coupling the test to migration side effects.
  await db.insert(
    DbTables.users,
    {
      'id': 1,
      'company_id': 1,
      'username': 'admin',
      'pin': '9999',
      'role': 'admin',
      'is_active': 1,
      'created_at_ms': now,
      'updated_at_ms': now,
      'display_name': 'Admin',
      'permissions': null,
      'password_hash':
          '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', // admin123
      'deleted_at_ms': null,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  await db.insert(
    DbTables.users,
    {
      'id': 2,
      'company_id': 1,
      'username': 'cashier',
      'pin': null,
      'role': 'cashier',
      'is_active': 1,
      'created_at_ms': now,
      'updated_at_ms': now,
      'display_name': 'Cashier',
      // No custom permissions => defaults should apply.
      'permissions': null,
      'password_hash':
          'b4c94003c562bb0d89535eca77f07284fe560fd48a7cc1ed99f0a56263d616ba', // cashier123
      'deleted_at_ms': null,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUpAll(() async {
    DbInit.ensureInitialized();
    docsDir = await Directory.systemTemp.createTemp('fullpos_docs_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir);
    SharedPreferences.setMockInitialValues({});

    await AppDb.resetForTests();
    await AppDb.database;
    await _seedUsersForTestDb();
  });

  tearDownAll(() async {
    await AppDb.resetForTests();
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets(
    'Cashier: navigate Credits/Returns/NCF quickly (no setState-after-dispose, no infinite loaders)',
    (tester) async {
      // Simulate a logged-in cashier session.
      await SessionManager.login(
        userId: 2,
        username: 'cashier',
        displayName: 'Cashier',
        role: 'cashier',
        companyId: 1,
        terminalId: 'test-terminal',
      );

      final router = _buildSmokeRouter();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      // Navigate quickly between modules a few times.
      for (var i = 0; i < 10; i++) {
        router.go('/credits');
        await tester.pump(const Duration(milliseconds: 20));

        router.go('/returns');
        await tester.pump(const Duration(milliseconds: 20));

        router.go('/ncf');
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Let pending async work settle.
      await tester.pump(const Duration(seconds: 2));

      // If any route keeps an internal spinner forever, this will time out and fail.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );
}
