import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fullpos/core/identity/identity_recovery_bundle.dart';
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
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
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

  test('no regenera terminal_id si hay evidencia de prefs corrupto', () async {
    final support = await PathProviderPlatform.instance
        .getApplicationSupportPath();
    final corrupt = File(
      p.join(support!, 'shared_preferences.json.corrupt_2026-06-17T10-00-00'),
    );
    await corrupt.create(recursive: true);

    SharedPreferences.setMockInitialValues({});

    expect(
      () => SessionManager.ensureTerminalId(),
      throwsA(isA<IdentityRecoveryException>()),
    );
  });

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
}
