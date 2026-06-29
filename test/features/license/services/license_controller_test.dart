import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fullpos/core/identity/license_reactivation_marker.dart';
import 'package:fullpos/features/license/license_config.dart';
import 'package:fullpos/features/license/data/license_models.dart';
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
    await _deleteTempDir(tempDir);
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

  test(
    'reactivación requerida bloquea cache activo y se limpia al activar',
    () async {
      final storage = LicenseStorage();
      await storage.setLicenseKey('LIC-REMOTE-123');
      await storage.setDeviceId('terminal-previo');
      await storage.setLastInfo(
        LicenseInfo(
          backendBaseUrl: kLicenseBackendBaseUrl,
          licenseKey: 'LIC-REMOTE-123',
          deviceId: 'terminal-previo',
          projectCode: kFullposProjectCode,
          businessId: 'biz_remote_123',
          ok: true,
          code: 'OK',
          estado: 'ACTIVA',
          fechaFin: DateTime.now().toUtc().add(const Duration(days: 30)),
        ),
      );
      await storage.markReactivationRequired(
        reason: 'test_missing_terminal',
        temporaryTerminalId: 'terminal-temp',
      );

      final controller = LicenseController(
        api: _FakeLicenseApi(),
        storage: storage,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.info?.isActive, isFalse);
      expect(controller.state.info?.code, 'REACTIVATION_REQUIRED');
      expect(await const LicenseReactivationMarker().isRequired(), isTrue);

      await controller.activate();

      expect(controller.state.info?.isActive, isTrue);
      expect(await const LicenseReactivationMarker().isRequired(), isFalse);
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
