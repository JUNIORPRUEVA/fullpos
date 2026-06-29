import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/identity/identity_recovery_bundle.dart';
import 'package:fullpos/core/identity/license_reactivation_marker.dart';
import 'package:fullpos/core/identity/terminal_id_log_recovery_service.dart';
import 'package:fullpos/core/recovery/app_recovery.dart';
import 'package:fullpos/core/session/session_manager.dart';
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
    tempDir = await Directory.systemTemp.createTemp(
      'fullpos_terminal_log_recovery_',
    );
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

  test('recupera terminalId desde log válido', () async {
    await _seedIdentityWithoutTerminal();
    await _writeLog(
      businessId: 'biz-123',
      licenseKey: 'FULL-AAAAA-BBBBB-QWZDS',
      terminalId: 'terminal-7UEFBU',
      deviceId: 'terminal-7UEFBU',
    );

    final result = await const TerminalIdLogRecoveryService().recover(
      reason: 'test_valid_log',
    );

    expect(result.recovered, isTrue);
    expect(result.terminalId, 'terminal-7UEFBU');
  });

  test('rechaza terminalId si businessId no coincide', () async {
    await _seedIdentityWithoutTerminal();
    await _writeLog(
      businessId: 'biz-other',
      licenseKey: 'FULL-AAAAA-BBBBB-QWZDS',
      terminalId: 'terminal-7UEFBU',
      deviceId: 'terminal-7UEFBU',
    );

    final result = await const TerminalIdLogRecoveryService().recover(
      reason: 'test_business_mismatch',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(result.recovered, isFalse);
    expect(prefs.getString(IdentityRecoveryBundle.terminalIdKey), isNull);
  });

  test('rechaza terminalId si licenseKey no coincide', () async {
    await _seedIdentityWithoutTerminal();
    await _writeLog(
      businessId: 'biz-123',
      licenseKey: 'FULL-AAAAA-BBBBB-NOMATC',
      terminalId: 'terminal-7UEFBU',
      deviceId: 'terminal-7UEFBU',
    );

    final result = await const TerminalIdLogRecoveryService().recover(
      reason: 'test_license_mismatch',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(result.recovered, isFalse);
    expect(prefs.getString(IdentityRecoveryBundle.terminalIdKey), isNull);
  });

  test('rechaza terminalId null', () async {
    await _seedIdentityWithoutTerminal();
    await _writeRawLog(
      '{"businessId":"biz-123","licenseKey":"FULL-AAAAA-BBBBB-QWZDS",'
      '"deviceId":"terminal-7UEFBU","terminalId":null}',
    );

    final result = await const TerminalIdLogRecoveryService().recover(
      reason: 'test_null_terminal',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(result.recovered, isFalse);
    expect(prefs.getString(IdentityRecoveryBundle.terminalIdKey), isNull);
  });

  test(
    'genera terminal nuevo y exige reactivación si no hay candidato',
    () async {
      await _seedIdentityWithoutTerminal();
      await _writeLog(
        businessId: 'biz-123',
        licenseKey: 'FULL-AAAAA-BBBBB-NOMATC',
        terminalId: 'terminal-7UEFBU',
        deviceId: 'terminal-7UEFBU',
      );

      final terminalId = await SessionManager.ensureTerminalId();

      final prefs = await SharedPreferences.getInstance();
      expect(terminalId, startsWith('terminal-'));
      expect(prefs.getString(IdentityRecoveryBundle.terminalIdKey), terminalId);
      expect(prefs.getString(IdentityRecoveryBundle.businessIdKey), 'biz-123');
      expect(
        prefs.getString(IdentityRecoveryBundle.licenseKeyKey),
        'FULL-AAAAA-BBBBB-QWZDS',
      );
      expect(await const LicenseReactivationMarker().isRequired(), isTrue);
      expect(AppRecoveryController.instance.state.active, isFalse);
    },
  );

  test('sincroniza prefs, bundle y SQLite', () async {
    await _seedIdentityWithoutTerminal();
    await IdentityRecoveryBundle.instance.saveFromCurrentState(
      'test_preexisting_bundle_without_terminal',
    );
    await _writeLog(
      businessId: 'biz-123',
      licenseKey: 'FULL-AAAAA-BBBBB-QWZDS',
      terminalId: 'terminal-7UEFBU',
      deviceId: 'terminal-7UEFBU',
    );

    final result = await const TerminalIdLogRecoveryService().recover(
      reason: 'test_sync_all',
    );

    final prefs = await SharedPreferences.getInstance();
    final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();
    final backup = await IdentityRecoveryBundle.instance.loadFromFile(
      await IdentityRecoveryBundle.instance.backupFile(),
    );
    final db = await AppDb.database;
    final rows = await db.query('app_identity', where: 'id = 1');

    expect(result.recovered, isTrue);
    expect(
      prefs.getString(IdentityRecoveryBundle.terminalIdKey),
      'terminal-7UEFBU',
    );
    expect(bundle?.terminalId, 'terminal-7UEFBU');
    expect(backup?.terminalId, 'terminal-7UEFBU');
    expect(rows.first['terminal_id'], 'terminal-7UEFBU');
    expect(rows.first['business_id'], 'biz-123');
    expect(rows.first['license_key'], 'FULL-AAAAA-BBBBB-QWZDS');
    expect(AppRecoveryController.instance.state.active, isFalse);
  });
}

Future<void> _seedIdentityWithoutTerminal() async {
  final db = await AppDb.database;
  await AppDb.ensureIdentitySchema(db);

  SharedPreferences.setMockInitialValues({
    'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz-123',
    'flutter.${IdentityRecoveryBundle.licenseKeyKey}': 'FULL-AAAAA-BBBBB-QWZDS',
    'flutter.${IdentityRecoveryBundle.licenseLastInfoKey}': jsonEncode({
      'businessId': 'biz-123',
      'licenseKey': 'FULL-AAAAA-BBBBB-QWZDS',
      'projectCode': 'FULLPOS',
    }),
  });
  await db.update('app_identity', {
    'business_id': 'biz-123',
    'license_key': 'FULL-AAAAA-BBBBB-QWZDS',
    'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
  }, where: 'id = 1');
}

Future<void> _writeLog({
  required String businessId,
  required String licenseKey,
  required String terminalId,
  required String deviceId,
}) {
  return _writeRawLog(
    'body={\\"businessId\\":\\"$businessId\\",'
    '\\"licenseKey\\":\\"$licenseKey\\",'
    '\\"deviceId\\":\\"$deviceId\\",'
    '\\"terminalId\\":\\"$terminalId\\",'
    '\\"companyName\\":\\"FULLPOS\\"}',
  );
}

Future<void> _writeRawLog(String line) async {
  final support = await PathProviderPlatform.instance
      .getApplicationSupportPath();
  final dir = Directory(p.join(support!, 'logs'));
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, 'app_2026-06-24.log'));
  await file.writeAsString('$line\n', flush: true);
}
