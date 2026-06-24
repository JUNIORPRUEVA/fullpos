import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/core/security/permission_service.dart';
import 'package:fullpos/core/security/temporary_authorization_service.dart';
import 'package:fullpos/features/auth/data/auth_repository.dart';
import 'package:fullpos/features/settings/data/user_model.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = Directory(p.join(root.path, 'support'));
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final dir = Directory(p.join(root.path, 'documents'));
    await dir.create(recursive: true);
    return dir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fullpos_perm_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TemporaryAuthorizationService.clearAll();
    TemporaryAuthorizationService.debugResetClock();
    await AppDb.resetForTests();
  });

  tearDown(() async {
    TemporaryAuthorizationService.clearAll();
    TemporaryAuthorizationService.debugResetClock();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppDb.resetForTests();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('denies by default when there is no current user', () async {
    expect(await PermissionService.can('inventory.add_stock'), isFalse);
  });

  test('admin passes all known actions', () async {
    await _createUser(id: 101, role: 'admin');
    _mockSession(userId: 101, role: 'admin');

    expect(await PermissionService.isAdmin(), isTrue);
    expect(await PermissionService.can('inventory.add_stock'), isTrue);
    expect(await PermissionService.can('settings.update_taxes'), isTrue);
  });

  test('non-admin passes assigned granular permission only', () async {
    await _createUser(id: 2, role: 'cashier');
    await PermissionService.setUserPermission(
      companyId: 1,
      userId: 2,
      actionCode: 'inventory.add_stock',
      allowed: true,
    );
    _mockSession(userId: 2, role: 'cashier');

    expect(await PermissionService.can('inventory.add_stock'), isTrue);
    expect(await PermissionService.can('inventory.remove_stock'), isFalse);
    expect(await PermissionService.can('inventory.adjust'), isFalse);
  });

  test('legacy inventory.adjust_stock permission remains broad', () async {
    await _createUser(
      id: 3,
      role: 'cashier',
      permissions: UserPermissions.cashier()
          .copyWith(canAdjustStock: true)
          .toMap(),
    );
    _mockSession(userId: 3, role: 'cashier');

    expect(await PermissionService.can('inventory.add_stock'), isTrue);
    expect(await PermissionService.can('inventory.remove_stock'), isTrue);
    expect(await PermissionService.can('inventory.adjust'), isTrue);
    expect(await PermissionService.can('inventory.adjust_stock'), isTrue);
  });

  test('unknown, empty, and missing permissions deny', () async {
    await _createUser(id: 4, role: 'cashier');
    await PermissionService.setUserPermission(
      companyId: 1,
      userId: 4,
      actionCode: 'unknown.permission',
      allowed: true,
    );
    _mockSession(userId: 4, role: 'cashier');

    expect(await PermissionService.can(''), isFalse);
    expect(await PermissionService.can('unknown.permission'), isFalse);
    expect(await PermissionService.can('inventory.add_stock'), isFalse);
  });

  test('canAny and canAll honor assigned permissions', () async {
    await _createUser(id: 5, role: 'cashier');
    await PermissionService.setUserPermission(
      companyId: 1,
      userId: 5,
      actionCode: 'inventory.add_stock',
      allowed: true,
    );
    await PermissionService.setUserPermission(
      companyId: 1,
      userId: 5,
      actionCode: 'inventory.remove_stock',
      allowed: true,
    );
    _mockSession(userId: 5, role: 'cashier');

    expect(
      await PermissionService.canAny(<String>[
        'inventory.adjust',
        'inventory.add_stock',
      ]),
      isTrue,
    );
    expect(
      await PermissionService.canAny(<String>[
        'inventory.adjust',
        'settings.update_taxes',
      ]),
      isFalse,
    );
    expect(
      await PermissionService.canAll(<String>[
        'inventory.add_stock',
        'inventory.remove_stock',
      ]),
      isTrue,
    );
    expect(
      await PermissionService.canAll(<String>[
        'inventory.add_stock',
        'inventory.adjust',
      ]),
      isFalse,
    );
  });

  test('requirePermission throws when denied', () async {
    await _createUser(id: 6, role: 'cashier');
    _mockSession(userId: 6, role: 'cashier');

    expect(
      () => PermissionService.requirePermission('inventory.add_stock'),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('temporary authorization does not bypass an invalid session', () async {
    TemporaryAuthorizationService.authorize(
      scope: 'inventory.add_stock',
      approvedByUserId: '1',
    );

    expect(await PermissionService.can('inventory.add_stock'), isFalse);
  });

  test('logout clears all temporary authorizations', () async {
    await _createUser(id: 7, role: 'cashier');
    _mockSession(userId: 7, role: 'cashier');
    TemporaryAuthorizationService.authorize(
      scope: 'inventory.add_stock',
      approvedByUserId: '1',
    );

    expect(await PermissionService.can('inventory.add_stock'), isTrue);

    await AuthRepository.logout();

    _mockSession(userId: 7, role: 'cashier');
    expect(await PermissionService.can('inventory.add_stock'), isFalse);
  });
}

Future<void> _createUser({
  required int id,
  required String role,
  Map<String, dynamic>? permissions,
}) async {
  final db = await AppDb.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert(DbTables.users, {
    'id': id,
    'company_id': 1,
    'username': 'user$id',
    'display_name': 'User $id',
    'pin': null,
    'password_hash': null,
    'role': role,
    'is_active': 1,
    'permissions': permissions == null ? null : jsonEncode(permissions),
    'created_at_ms': now,
    'updated_at_ms': now,
    'deleted_at_ms': null,
  });
}

void _mockSession({required int userId, required String role}) {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.logged_in': true,
    'flutter.logged_user_id': userId,
    'flutter.logged_user': 'user$userId',
    'flutter.logged_display_name': 'User $userId',
    'flutter.logged_role': role,
    'flutter.logged_company_id': 1,
    'flutter.terminal_id': 'terminal-test',
  });
}
