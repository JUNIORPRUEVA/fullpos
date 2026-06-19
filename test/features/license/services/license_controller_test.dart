import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fullpos/features/license/license_config.dart';
import 'package:fullpos/features/license/services/license_api.dart';
import 'package:fullpos/features/license/services/license_controller.dart';
import 'package:fullpos/features/license/services/license_storage.dart';
import 'package:fullpos/features/registration/services/business_identity_storage.dart';

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

class _FakeLicenseApi extends LicenseApi {
  @override
  Future<Map<String, dynamic>> activate({
    required String baseUrl,
    required String licenseKey,
    required String deviceId,
    required String projectCode,
  }) async {
    return {
      'ok': true,
      'code': 'OK',
      'estado': 'ACTIVA',
      'tipo': 'FULL',
      'businessId': 'biz_remote_123',
      'fecha_inicio': DateTime.now().toUtc().toIso8601String(),
      'fecha_fin': DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> getPublicSigningKey({
    required String baseUrl,
  }) async {
    return {'ok': false};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'fullpos_license_controller_test_',
    );
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'activacion remota guarda businessId entrante como identidad local',
    () async {
      final storage = LicenseStorage();
      await storage.setLicenseKey('LIC-REMOTE-123');

      final controller = LicenseController(
        api: _FakeLicenseApi(),
        storage: storage,
      );
      addTearDown(controller.dispose);

      await controller.activate();

      final businessId = await BusinessIdentityStorage().getBusinessId();
      final info = await storage.getLastInfo();

      expect(businessId, 'biz_remote_123');
      expect(info?.businessId, 'biz_remote_123');
      expect(info?.projectCode, kFullposProjectCode);
      expect(info?.isActive, isTrue);
    },
  );
}
