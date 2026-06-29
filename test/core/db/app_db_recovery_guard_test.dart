import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/core/recovery/app_recovery.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

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
    tempDir = await Directory.systemTemp.createTemp('fullpos_db_guard_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppRecoveryController.instance.clearForTests();
    await AppDb.resetForTests();
  });

  tearDown(() async {
    await AppDb.resetForTests();
    AppRecoveryController.instance.clearForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('DB existente nunca crea demo automaticamente', () async {
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    final dbFile = File(p.join(docs!, 'fullpos.db'));
    await dbFile.create(recursive: true);

    final db = await AppDb.database;
    final demoCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM ${DbTables.products} WHERE code LIKE '${AppDb.demoProductCodePrefix}%'",
          ),
        ) ??
        0;

    expect(demoCount, 0);
  });

  test(
    '_syncDemoCatalog no corre cuando hay evidencia de backup previo',
    () async {
      final docs = await PathProviderPlatform.instance
          .getApplicationDocumentsPath();
      await Directory(p.join(docs!, 'FULLPOS_BACKUPS')).create(recursive: true);

      await expectLater(
        AppDb.database,
        throwsA(isA<AppRecoveryRequiredException>()),
      );

      expect(
        AppRecoveryController.instance.state.kind,
        AppRecoveryKind.database,
      );
      expect(
        AppRecoveryController.instance.state.reason,
        'main_database_missing_prior_installation',
      );
      expect(await File(p.join(docs, 'fullpos.db')).exists(), isFalse);
    },
  );

  test(
    'business_id en prefs sin DB activa recovery y no crea esquema',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.business.business_id_v1': 'business-previo',
      });

      await expectLater(
        AppDb.database,
        throwsA(isA<AppRecoveryRequiredException>()),
      );

      final docs = await PathProviderPlatform.instance
          .getApplicationDocumentsPath();
      expect(await File(p.join(docs!, 'fullpos.db')).exists(), isFalse);
      expect(
        AppRecoveryController.instance.state.kind,
        AppRecoveryKind.database,
      );
    },
  );

  test('terminal_id en prefs sin DB activa recovery y no crea demo', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.terminal_id': 'terminal-previo',
    });

    await expectLater(
      AppDb.database,
      throwsA(isA<AppRecoveryRequiredException>()),
    );

    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    expect(await File(p.join(docs!, 'fullpos.db')).exists(), isFalse);
    expect(AppRecoveryController.instance.state.kind, AppRecoveryKind.database);
  });
}
