import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/recovery/app_recovery.dart';
import 'package:fullpos/core/security/authz/authz_service.dart';
import 'package:fullpos/core/identity/identity_recovery_bundle.dart';
import 'package:fullpos/core/identity/license_reactivation_marker.dart';
import 'package:fullpos/core/session/session_manager.dart';

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
    tempDir = await Directory.systemTemp.createTemp('fullpos_identity_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues({});
    await AppDb.resetForTests();
    AppRecoveryController.instance.clearForTests();
  });

  tearDown(() async {
    await AppDb.resetForTests();
    await _deleteTempDir(tempDir);
  });

  test(
    'crea bundle desde preferencias sanas y recupera claves criticas',
    () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz_123',
        'flutter.${IdentityRecoveryBundle.licenseKeyKey}': 'LIC-123456',
        'flutter.${IdentityRecoveryBundle.licenseDeviceIdKey}': 'terminal-OLD',
        'flutter.${IdentityRecoveryBundle.terminalIdKey}': 'terminal-OLD',
        'flutter.${IdentityRecoveryBundle.licenseLastInfoKey}':
            '{"businessId":"biz_123","licenseKey":"LIC-123456","deviceId":"terminal-OLD","projectCode":"FULLPOS","ok":true}',
      });

      final saved = await IdentityRecoveryBundle.instance.saveFromCurrentState(
        'test_existing_installation',
      );
      expect(saved, isTrue);
      expect(
        await (await IdentityRecoveryBundle.instance.primaryFile()).exists(),
        isTrue,
      );

      SharedPreferences.setMockInitialValues({});
      final recovered = await IdentityRecoveryBundle.instance
          .recoverToSharedPreferences('test_recover');
      expect(recovered, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(IdentityRecoveryBundle.businessIdKey), 'biz_123');
      expect(
        prefs.getString(IdentityRecoveryBundle.licenseDeviceIdKey),
        'terminal-OLD',
      );
      expect(
        prefs.getString(IdentityRecoveryBundle.terminalIdKey),
        'terminal-OLD',
      );
    },
  );

  test('bloquea restauracion si business_id local es diferente', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz_A',
      'flutter.${IdentityRecoveryBundle.terminalIdKey}': 'terminal-A',
    });
    expect(
      await IdentityRecoveryBundle.instance.saveFromCurrentState('test_A'),
      isTrue,
    );
    final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();
    expect(bundle, isNotNull);

    SharedPreferences.setMockInitialValues({
      'flutter.${IdentityRecoveryBundle.businessIdKey}': 'biz_B',
    });
    final restored = await IdentityRecoveryBundle.instance
        .restoreBundleToSharedPreferences(bundle!, reason: 'conflict_test');
    expect(restored, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(IdentityRecoveryBundle.businessIdKey), 'biz_B');
    expect(prefs.getBool(IdentityRecoveryBundle.recoveryRequiredKey), isTrue);
  });

  test('prefs corrupto genera terminal nuevo y exige reactivación', () async {
    final support = await PathProviderPlatform.instance
        .getApplicationSupportPath();
    final corrupt = File(
      p.join(support!, 'shared_preferences.json.corrupt_2026-06-17T10-00-00'),
    );
    await corrupt.create(recursive: true);

    SharedPreferences.setMockInitialValues({});

    final terminalId = await SessionManager.ensureTerminalId();

    final prefs = await SharedPreferences.getInstance();
    expect(terminalId, startsWith('terminal-'));
    expect(prefs.getString(IdentityRecoveryBundle.terminalIdKey), terminalId);
    expect(await const LicenseReactivationMarker().isRequired(), isTrue);
  });

  test(
    'DB previa sin terminal_id genera terminal nuevo y exige reactivación',
    () async {
      final docs = await PathProviderPlatform.instance
          .getApplicationDocumentsPath();
      final db = File(p.join(docs!, 'fullpos.db'));
      await db.create(recursive: true);

      SharedPreferences.setMockInitialValues({});

      final terminalId = await SessionManager.ensureTerminalId();

      final prefs = await SharedPreferences.getInstance();
      expect(terminalId, startsWith('terminal-'));
      expect(prefs.getString(IdentityRecoveryBundle.terminalIdKey), terminalId);
      expect(await const LicenseReactivationMarker().isRequired(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(AppRecoveryController.instance.state.active, isFalse);
    },
  );

  test(
    'AuthzService.currentUser usa terminal nuevo y marca reactivación',
    () async {
      final docs = await PathProviderPlatform.instance
          .getApplicationDocumentsPath();
      final db = File(p.join(docs!, 'fullpos.db'));
      await db.create(recursive: true);

      SharedPreferences.setMockInitialValues({
        'flutter.logged_in': true,
        'flutter.logged_user_id': 77,
        'flutter.logged_user': 'admin',
        'flutter.logged_display_name': 'Admin',
        'flutter.logged_role': 'admin',
        'flutter.logged_company_id': 1,
      });

      final user = await AuthzService.currentUser();

      expect(user, isNotNull);
      expect(user?.terminalId, startsWith('terminal-'));
      expect(await const LicenseReactivationMarker().isRequired(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(AppRecoveryController.instance.state.active, isFalse);
    },
  );

  test('instalacion nueva sin bundle no marca recovery_required', () async {
    SharedPreferences.setMockInitialValues({});

    final recovered = await IdentityRecoveryBundle.instance
        .recoverToSharedPreferences('clean_install_probe');

    final prefs = await SharedPreferences.getInstance();
    expect(recovered, isFalse);
    expect(
      prefs.getBool(IdentityRecoveryBundle.recoveryRequiredKey),
      isNot(true),
    );
  });

  test(
    'licenseKey sola no bloquea generacion inicial de terminal_id',
    () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${IdentityRecoveryBundle.licenseKeyKey}': 'LIC-PENDING',
      });

      await IdentityRecoveryBundle.instance.saveFromCurrentState(
        'test_license_key_only',
      );
      SharedPreferences.setMockInitialValues({
        'flutter.${IdentityRecoveryBundle.licenseKeyKey}': 'LIC-PENDING',
      });

      final terminalId = await SessionManager.ensureTerminalId();

      expect(terminalId, startsWith('terminal-'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(IdentityRecoveryBundle.terminalIdKey), terminalId);
      expect(
        prefs.getBool(IdentityRecoveryBundle.recoveryRequiredKey),
        isNot(true),
      );
    },
  );
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
