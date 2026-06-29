import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/recovery/app_recovery.dart';
import 'package:fullpos/core/recovery/recovery_lock.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fullpos_recovery_lock_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await RecoveryLock.release();
  });

  tearDown(() async {
    await RecoveryLock.release();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('recovery.lock evita doble reparación', () async {
    await RecoveryLock.acquire('first');

    expect(
      () => RecoveryLock.acquire('second'),
      throwsA(isA<AppRecoveryRequiredException>()),
    );
  });
}
