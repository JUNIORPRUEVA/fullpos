import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/core/identity/license_reactivation_marker.dart';
import 'package:fullpos/core/identity/identity_recovery_bundle.dart';
import 'package:fullpos/core/recovery/app_recovery.dart';
import 'package:fullpos/core/recovery/recovery_lock.dart';
import 'package:fullpos/core/self_healing/self_healing_engine.dart';
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
  DbInit.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fullpos_self_healing_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppRecoveryController.instance.clearForTests();
    await AppDb.resetForTests();
  });

  tearDown(() async {
    await AppDb.resetForTests();
    AppRecoveryController.instance.clearForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    try {
      await RecoveryLock.release();
    } catch (_) {}
    await _deleteTempDir(tempDir);
  });

  test('DB oficial falta pero backup válido existe => restaura DB', () async {
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    final backupDir = Directory(p.join(docs!, 'FULLPOS_BACKUPS'));
    await backupDir.create(recursive: true);
    final backup = File(p.join(backupDir.path, 'fullpos_REPARADA_cliente.db'));
    await _createDb(backup.path, realData: true);

    final report = await const SelfHealingEngine().run(
      reason: 'test_db_restore',
    );
    final official = File(p.join(docs, AppDb.dbFileName));

    expect(report.needsRecovery, isFalse);
    expect(await official.exists(), isTrue);
    expect(
      report.results.any((r) => r.action == HealingAction.restoreDatabase),
      isTrue,
    );
  });

  test('DB oficial falta y solo hay demo => Recovery', () async {
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    final backupDir = Directory(p.join(docs!, 'FULLPOS_BACKUPS'));
    await backupDir.create(recursive: true);
    await _createDb(p.join(backupDir.path, 'fullpos_demo.db'), demoOnly: true);

    final report = await const SelfHealingEngine().run(
      reason: 'test_demo_only',
    );

    expect(report.needsRecovery, isTrue);
    expect(AppRecoveryController.instance.state.kind, AppRecoveryKind.database);
    expect(await File(p.join(docs, AppDb.dbFileName)).exists(), isFalse);
  });

  test('DB oficial existe => no tocar', () async {
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    final official = File(p.join(docs!, AppDb.dbFileName));
    await _createDb(official.path, realData: true);
    final before = await official.length();

    final evidence = await const SelfHealingEngine().collectEvidence();
    final result = await DatabaseHealer().repairIfNeeded(evidence);

    expect(result.action, HealingAction.none);
    expect(await official.length(), before);
  });

  test('terminalId null en bundle pero válido en log => restaura', () async {
    await _createOfficialDbWithIdentity(
      businessId: 'biz-123',
      licenseKey: 'FULL-AAAAA-BBBBB-QWZDS',
    );
    SharedPreferences.setMockInitialValues({
      'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz-123',
      'flutter.${IdentityRecoveryBundle.licenseKeyKey}':
          'FULL-AAAAA-BBBBB-QWZDS',
    });
    await _writeLog(
      businessId: 'biz-123',
      licenseKey: 'FULL-AAAAA-BBBBB-QWZDS',
      terminalId: 'terminal-7UEFBU',
    );

    final report = await const SelfHealingEngine().run(
      reason: 'test_terminal_log',
    );
    final prefs = await SharedPreferences.getInstance();

    expect(report.needsRecovery, isFalse);
    expect(
      prefs.getString(IdentityRecoveryBundle.terminalIdKey),
      'terminal-7UEFBU',
    );
  });

  test(
    'terminalId válido en bundle y null en prefs => restaura prefs',
    () async {
      await _createOfficialDbWithIdentity(
        businessId: 'biz-123',
        licenseKey: 'FULL-AAAAA-BBBBB-QWZDS',
      );
      SharedPreferences.setMockInitialValues({
        'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz-123',
        'flutter.${IdentityRecoveryBundle.licenseKeyKey}':
            'FULL-AAAAA-BBBBB-QWZDS',
      });
      await _writeBundle(
        businessId: 'biz-123',
        licenseKey: 'FULL-AAAAA-BBBBB-QWZDS',
        terminalId: 'terminal-bundle',
      );

      final report = await const SelfHealingEngine().run(
        reason: 'test_bundle_terminal',
      );
      final prefs = await SharedPreferences.getInstance();

      expect(report.needsRecovery, isFalse);
      expect(
        prefs.getString(IdentityRecoveryBundle.terminalIdKey),
        'terminal-bundle',
      );
    },
  );

  test('bundle válido no se degrada a terminalId null', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz-123',
    });
    await _writeBundle(
      businessId: 'biz-123',
      licenseKey: 'FULL-AAAAA-BBBBB-QWZDS',
      terminalId: 'terminal-safe',
    );

    await IdentityRecoveryBundle.instance.saveFromCurrentState(
      'test_partial_prefs',
    );
    final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();

    expect(bundle?.terminalId, 'terminal-safe');
  });

  test('businessId conflicto => Recovery', () async {
    await _createOfficialDbWithIdentity(
      businessId: 'biz-A',
      licenseKey: 'LIC-A',
    );
    SharedPreferences.setMockInitialValues({
      'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz-A',
      'flutter.${IdentityRecoveryBundle.licenseKeyKey}': 'LIC-A',
    });
    await _writeBundle(businessId: 'biz-B', licenseKey: 'LIC-A');

    final report = await const SelfHealingEngine().run(
      reason: 'test_biz_conflict',
    );

    expect(report.needsRecovery, isTrue);
    expect(AppRecoveryController.instance.state.kind, AppRecoveryKind.identity);
  });

  test('licenseKey conflicto => Recovery', () async {
    await _createOfficialDbWithIdentity(
      businessId: 'biz-A',
      licenseKey: 'LIC-A',
    );
    SharedPreferences.setMockInitialValues({
      'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz-A',
      'flutter.${IdentityRecoveryBundle.licenseKeyKey}': 'LIC-A',
    });
    await _writeBundle(businessId: 'biz-A', licenseKey: 'LIC-B');

    final report = await const SelfHealingEngine().run(
      reason: 'test_license_conflict',
    );

    expect(report.needsRecovery, isTrue);
    expect(AppRecoveryController.instance.state.kind, AppRecoveryKind.identity);
  });

  test('recovery_state viejo se limpia si problema resuelto', () async {
    await _createOfficialDbWithIdentity(
      businessId: 'biz-123',
      licenseKey: 'FULL-AAAAA-BBBBB-QWZDS',
      terminalId: 'terminal-ok',
    );
    SharedPreferences.setMockInitialValues({
      'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz-123',
      'flutter.${IdentityRecoveryBundle.licenseKeyKey}':
          'FULL-AAAAA-BBBBB-QWZDS',
      'flutter.${IdentityRecoveryBundle.terminalIdKey}': 'terminal-ok',
    });
    await AppRecoveryController.instance.requireIdentityRecovery('old_state');

    final report = await const SelfHealingEngine().run(
      reason: 'test_stale_recovery',
    );

    expect(report.needsRecovery, isFalse);
    expect(AppRecoveryController.instance.state.active, isFalse);
  });

  test('currentUserId inválido limpia sesión', () async {
    await _createOfficialDbWithIdentity();
    SharedPreferences.setMockInitialValues({
      'flutter.logged_in': true,
      'flutter.logged_user_id': 999,
      'flutter.logged_user': 'missing',
      'flutter.logged_display_name': 'Missing',
      'flutter.logged_role': 'admin',
      'flutter.logged_company_id': 1,
    });

    await SessionHealer().repairIfNeeded();
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getBool('logged_in'), isNull);
    expect(prefs.getInt('logged_user_id'), isNull);
  });

  test(
    'genera terminal nuevo y exige reactivación si falta terminal',
    () async {
      await _createOfficialDbWithIdentity(
        businessId: 'biz-previo',
        licenseKey: 'LIC-PREVIA',
      );
      SharedPreferences.setMockInitialValues({
        'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz-previo',
        'flutter.${IdentityRecoveryBundle.licenseKeyKey}': 'LIC-PREVIA',
      });

      final report = await const SelfHealingEngine().run(
        reason: 'test_no_terminal_gen',
      );
      final prefs = await SharedPreferences.getInstance();
      final terminalId = prefs.getString(IdentityRecoveryBundle.terminalIdKey);

      expect(report.needsRecovery, isFalse);
      expect(terminalId, startsWith('terminal-'));
      expect(
        prefs.getString(IdentityRecoveryBundle.businessIdKey),
        'biz-previo',
      );
      expect(
        prefs.getString(IdentityRecoveryBundle.licenseKeyKey),
        'LIC-PREVIA',
      );
      expect(await const LicenseReactivationMarker().isRequired(), isTrue);
      expect(AppRecoveryController.instance.state.active, isFalse);
    },
  );

  test('no crea DB demo con evidencia previa', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz-previo',
    });
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();

    await const SelfHealingEngine().run(reason: 'test_no_demo_db');

    expect(await File(p.join(docs!, AppDb.dbFileName)).exists(), isFalse);
  });

  test('no borra WAL/SHM antes de checkpoint', () async {
    final docs = await PathProviderPlatform.instance
        .getApplicationDocumentsPath();
    final backupDir = Directory(p.join(docs!, 'FULLPOS_BACKUPS'));
    await backupDir.create(recursive: true);
    final candidate = File(p.join(backupDir.path, 'fullpos_REPARADA.db'));
    await _createDb(candidate.path, realData: true);
    await File('${candidate.path}-wal').writeAsString('wal');
    await File('${candidate.path}-shm').writeAsString('shm');

    await const SelfHealingEngine().run(reason: 'test_wal_preserve');

    expect(await File('${candidate.path}-wal').exists(), isTrue);
    expect(await File('${candidate.path}-shm').exists(), isTrue);
  });

  test('recovery lock evita doble reparación', () async {
    await RecoveryLock.acquire('test_existing_lock');

    final report = await const SelfHealingEngine().run(reason: 'test_lock');

    expect(report.needsRecovery, isTrue);
    expect(report.issues.any((i) => i.code == 'recovery_lock_active'), isTrue);
  });
}

Future<void> _deleteTempDir(Directory dir) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    if (!await dir.exists()) return;
    try {
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

Future<void> _createOfficialDbWithIdentity({
  String? businessId,
  String? licenseKey,
  String? terminalId,
}) async {
  final docs = await PathProviderPlatform.instance
      .getApplicationDocumentsPath();
  final path = p.join(docs!, AppDb.dbFileName);
  await _createDb(path, realData: true);
  final db = await openDatabase(path);
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_identity (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        terminal_id TEXT NULL,
        business_id TEXT NULL,
        license_key TEXT NULL,
        license_device_id TEXT NULL,
        install_id TEXT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('app_identity', {
      'id': 1,
      'terminal_id': terminalId,
      'business_id': businessId,
      'license_key': licenseKey,
      'created_at_ms': now,
      'updated_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  } finally {
    await db.close();
  }
}

Future<void> _createDb(
  String path, {
  bool realData = false,
  bool demoOnly = false,
}) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final db = await openDatabase(path);
  try {
    await db.execute(
      'CREATE TABLE ${DbTables.users} (id INTEGER PRIMARY KEY, is_active INTEGER, deleted_at_ms INTEGER)',
    );
    await db.execute(
      'CREATE TABLE ${DbTables.products} ('
      'id INTEGER PRIMARY KEY, '
      'code TEXT, '
      'deleted_at_ms INTEGER'
      ')',
    );
    await db.execute('CREATE TABLE ${DbTables.sales} (id INTEGER PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE ${DbTables.clients} (id INTEGER PRIMARY KEY)',
    );
    await db.execute(
      'CREATE TABLE ${DbTables.cashboxDaily} (id INTEGER PRIMARY KEY)',
    );
    await db.execute(
      'CREATE TABLE ${DbTables.cashSessions} (id INTEGER PRIMARY KEY)',
    );
    await db.execute(
      'CREATE TABLE ${DbTables.cashMovements} (id INTEGER PRIMARY KEY)',
    );
    await db.insert(DbTables.users, {'id': 1, 'is_active': 1});
    if (realData) {
      await db.insert(DbTables.products, {'id': 1, 'code': 'REAL-001'});
      await db.insert(DbTables.clients, {'id': 1});
      await db.insert(DbTables.sales, {'id': 1});
    }
    if (demoOnly) {
      await db.insert(DbTables.products, {
        'id': 1,
        'code': '${AppDb.demoProductCodePrefix}001',
      });
    }
    await db.execute('PRAGMA user_version = ${AppDb.schemaVersion}');
  } finally {
    await db.close();
  }
}

Future<void> _writeLog({
  required String businessId,
  required String licenseKey,
  required String terminalId,
}) async {
  final support = await PathProviderPlatform.instance
      .getApplicationSupportPath();
  final dir = Directory(p.join(support!, 'logs'));
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'app_2026-06-24.log')).writeAsString(
    'body={\\"businessId\\":\\"$businessId\\",'
    '\\"licenseKey\\":\\"$licenseKey\\",'
    '\\"deviceId\\":\\"$terminalId\\",'
    '\\"terminalId\\":\\"$terminalId\\"}\n',
    flush: true,
  );
}

Future<void> _writeBundle({
  required String businessId,
  required String licenseKey,
  String? terminalId,
}) async {
  final now = DateTime.now().toUtc();
  final lastInfo = <String, Object?>{
    'businessId': businessId,
    'licenseKey': licenseKey,
  };
  if (terminalId != null) {
    lastInfo['deviceId'] = terminalId;
  }
  final data = IdentityRecoveryBundleData(
    businessId: businessId,
    licenseKey: licenseKey,
    licenseDeviceId: terminalId,
    terminalId: terminalId,
    licenseLastInfo: jsonEncode(lastInfo),
    createdAt: now,
    updatedAt: now,
    source: 'test',
    appVersion: 'test',
    checksum: '',
  );
  final checked = data.copyWith(
    checksum: IdentityRecoveryBundle.checksumForJson(
      data.toJson(includeChecksum: false),
    ),
  );
  await IdentityRecoveryBundle.instance.saveBundle(checked, reason: 'test');
}
