import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
    tempDir = await Directory.systemTemp.createTemp('fullpos_recovery_state_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppRecoveryController.instance.clearResolved();
  });

  tearDown(() async {
    await AppRecoveryController.instance.clearResolved();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('recovery_state.json persiste y se carga al reiniciar', () async {
    await AppRecoveryController.instance.requireIdentityRecovery(
      'test_recovery',
      details: 'terminal missing',
      dbPath: 'C:/db/fullpos.db',
    );

    final file = await AppRecoveryController.recoveryStateFile();
    expect(await file.exists(), isTrue);

    AppRecoveryController.instance.clearForTests();
    expect(AppRecoveryController.instance.state.active, isFalse);

    await AppRecoveryController.instance.loadPersisted();
    expect(AppRecoveryController.instance.state.active, isTrue);
    expect(AppRecoveryController.instance.state.reason, 'test_recovery');
  });

  test('recovery_state.json se limpia al resolver', () async {
    await AppRecoveryController.instance.requireDatabaseRecovery(
      'test_database_recovery',
    );
    final file = await AppRecoveryController.recoveryStateFile();
    expect(await file.exists(), isTrue);

    await AppRecoveryController.instance.clearResolved();

    expect(await file.exists(), isFalse);
    expect(AppRecoveryController.instance.state.active, isFalse);
  });
}
