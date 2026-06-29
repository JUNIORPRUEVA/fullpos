import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/identity/identity_health_service.dart';
import 'package:fullpos/core/identity/identity_recovery_bundle.dart';
import 'package:fullpos/core/recovery/app_recovery.dart';
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
    tempDir = await Directory.systemTemp.createTemp('fullpos_identity_health_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppRecoveryController.instance.clearResolved();
    await AppDb.resetForTests();
  });

  tearDown(() async {
    await AppDb.resetForTests();
    await AppRecoveryController.instance.clearResolved();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('app_identity se crea sin romper DB existente', () async {
    final db = await AppDb.database;
    await AppDb.ensureIdentitySchema(db);

    final rows = await db.query('app_identity', where: 'id = 1');

    expect(rows, hasLength(1));
  });

  test('prefs restauran desde SQLite cuando falta terminal_id', () async {
    final db = await AppDb.database;
    await AppDb.ensureIdentitySchema(db);
    await db.update('app_identity', {
      'terminal_id': 'terminal-db',
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = 1');

    final result = await const IdentityHealthService().check();
    final prefs = await SharedPreferences.getInstance();

    expect(result.repaired, isTrue);
    expect(
      prefs.getString(IdentityRecoveryBundle.terminalIdKey),
      'terminal-db',
    );
  });

  test('SQLite se restaura desde prefs cuando falta terminal_id', () async {
    final db = await AppDb.database;
    await AppDb.ensureIdentitySchema(db);

    SharedPreferences.setMockInitialValues({
      'flutter.${IdentityRecoveryBundle.terminalIdKey}': 'terminal-prefs',
    });

    final result = await const IdentityHealthService().check();
    final rows = await db.query('app_identity', where: 'id = 1');

    expect(result.repaired, isTrue);
    expect(rows.first['terminal_id'], 'terminal-prefs');
  });

  test('conflicto prefs vs SQLite activa RecoveryState', () async {
    final db = await AppDb.database;
    await AppDb.ensureIdentitySchema(db);

    SharedPreferences.setMockInitialValues({
      'flutter.${IdentityRecoveryBundle.terminalIdKey}': 'terminal-prefs',
    });
    await db.update('app_identity', {
      'terminal_id': 'terminal-db',
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = 1');

    final result = await const IdentityHealthService().check();

    expect(result.needsRecovery, isTrue);
    expect(AppRecoveryController.instance.state.active, isTrue);
    expect(AppRecoveryController.instance.state.reason, 'identity_conflict');
  });

  test('IdentityHealthService nunca lanza excepción fatal', () async {
    final result = await const IdentityHealthService().check();

    expect(result.needsRecovery, isFalse);
  });
}
