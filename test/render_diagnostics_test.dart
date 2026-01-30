import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:fullpos/core/debug/app_logger.dart';
import 'package:fullpos/core/debug/render_diagnostics.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.basePath);

  final String basePath;

  @override
  Future<String?> getTemporaryPath() async => basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;

  @override
  Future<String?> getLibraryPath() async => basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;

  @override
  Future<String?> getExternalStoragePath() async => basePath;

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async {
    return [basePath];
  }

  @override
  Future<List<String>?> getExternalCachePaths() async => [basePath];

  @override
  Future<String?> getDownloadsPath() async => basePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('render_diag_test');
    PathProviderPlatform.instance =
        _FakePathProviderPlatform(tempDir.path);
    DebugAppLogger.instance.resetForTesting();
    RenderDiagnostics.instance.resetTimings();
  });

  tearDown(() async {
    await DebugAppLogger.instance.drainQueue();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('DebugAppLogger writes to app.log', () async {
    final logger = DebugAppLogger.instance;
    await logger.init();
    await logger.info('hello', data: {'test': true});
    final path = logger.logFilePath!;
    final content = await File(path).readAsString();
    expect(content.contains('hello'), isTrue);
  });

  test('RenderWatchdog triggers after timeout', () async {
    final watchdog = RenderDiagnostics.instance.createWatchdog(
      timeout: const Duration(milliseconds: 40),
    );
    var fired = false;
    watchdog.start(() => fired = true);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fired, isTrue);
    watchdog.dispose();
  });

  test('RenderDiagnostics computes time-to-first-frame', () async {
    final diagnostics = RenderDiagnostics.instance;
    diagnostics.markRunAppStart();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    diagnostics.markFirstFramePainted(source: 'test');
    expect(diagnostics.timeToFirstFrame, isNotNull);
  });
}
