import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/auto_repair.dart';
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
    tempDir = await Directory.systemTemp.createTemp('fullpos_reindex_test_');
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

  test('DB dañada intenta REINDEX antes de requerir recovery', () async {
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    final dbFile = File(p.join(docs!, 'fullpos.db'));
    await dbFile.create(recursive: true);
    await dbFile.writeAsString('not a sqlite database', flush: true);

    await expectLater(
      AutoRepair.instance.ensureDbHealthy(reason: 'test_reindex_first'),
      throwsA(isA<AppRecoveryRequiredException>()),
    );

    final log = File(p.join(docs, 'FULLPOS_LOGS', 'auto_repair.log'));
    expect(await log.exists(), isTrue);
    expect(await log.readAsString(), contains('REINDEX'));
    expect(await dbFile.exists(), isTrue);
    expect(AppRecoveryController.instance.state.kind, AppRecoveryKind.database);
  });

  test('WAL con transacciones pendientes se preserva con checkpoint', () async {
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    final walFile = File(p.join(docs!, 'fullpos.db-wal'));
    final db = await AppDb.database;
    await _createWalTableAndRow(db, 'pendiente');

    expect(await walFile.exists(), isTrue);

    await AutoRepair.instance.ensureDbHealthy(reason: 'test_wal_pending');

    final reopened = await AppDb.database;
    final count = await _qaWalCount(reopened, 'pendiente');
    expect(count, 1);
    final log = await _autoRepairLog(docs);
    expect(log, contains('wal_checkpoint(TRUNCATE) ok=true'));
    expect(log, isNot(contains('deleted ${walFile.path}')));
  });

  test('checkpoint correcto no elimina WAL valido como primer paso', () async {
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    final walFile = File(p.join(docs!, 'fullpos.db-wal'));
    final db = await AppDb.database;
    await _createWalTableAndRow(db, 'checkpoint');

    await AutoRepair.instance.ensureDbHealthy(reason: 'test_checkpoint');

    final log = await _autoRepairLog(docs);
    expect(log, contains('wal_checkpoint(TRUNCATE) ok=true'));
    expect(log, isNot(contains('deleted ${walFile.path}')));
    expect(await _qaWalCount(await AppDb.database, 'checkpoint'), 1);
  });

  test('WAL corrupto solo se resetea si SQLite no puede abrirlo', () async {
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    final db = await AppDb.database;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS qa_wal (id INTEGER PRIMARY KEY, value TEXT)',
    );
    await AppDb.close();

    final walFile = File(p.join(docs!, 'fullpos.db-wal'));
    await walFile.writeAsString('wal corrupto', flush: true);

    await AutoRepair.instance.ensureDbHealthy(reason: 'test_corrupt_wal');

    final log = await _autoRepairLog(docs);
    expect(log, contains('wal_checkpoint'));
    if (log.contains('wal_checkpoint(TRUNCATE) ok=false')) {
      expect(log, contains('resetWalShmIfNeeded start'));
    }
  });

  test(
    'DB sin WAL ejecuta checkpoint y quick_check sin borrar archivos',
    () async {
      final docs = await PathProviderPlatform.instance
          .getApplicationDocumentsPath();
      final db = await AppDb.database;
      await db.execute(
        'CREATE TABLE IF NOT EXISTS qa_wal (id INTEGER PRIMARY KEY, value TEXT)',
      );
      await AppDb.close();
      final walFile = File(p.join(docs!, 'fullpos.db-wal'));
      if (await walFile.exists()) await walFile.delete();

      await AutoRepair.instance.ensureDbHealthy(reason: 'test_no_wal');

      final log = await _autoRepairLog(docs);
      expect(log, contains('wal_checkpoint(TRUNCATE) ok=true'));
      expect(log, isNot(contains('deleted ${walFile.path}')));
    },
  );

  test('DB con WAL valido conserva datos y no entra en recovery', () async {
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    final db = await AppDb.database;
    await _createWalTableAndRow(db, 'valido');

    await AutoRepair.instance.ensureDbHealthy(reason: 'test_valid_wal');

    expect(await _qaWalCount(await AppDb.database, 'valido'), 1);
    expect(AppRecoveryController.instance.state.active, isFalse);
    expect(await _autoRepairLog(docs!), contains('wal_checkpoint'));
  });
}

Future<void> _createWalTableAndRow(dynamic db, String value) async {
  await db.execute('PRAGMA journal_mode = WAL;');
  await db.execute('PRAGMA wal_autocheckpoint = 0;');
  await db.execute(
    'CREATE TABLE IF NOT EXISTS qa_wal (id INTEGER PRIMARY KEY, value TEXT)',
  );
  await db.insert('qa_wal', {'value': value});
}

Future<int> _qaWalCount(dynamic db, String value) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM qa_wal WHERE value = ?',
    [value],
  );
  return (rows.first['c'] as int?) ?? 0;
}

Future<String> _autoRepairLog(String docs) async {
  final log = File(p.join(docs, 'FULLPOS_LOGS', 'auto_repair.log'));
  expect(await log.exists(), isTrue);
  return log.readAsString();
}
