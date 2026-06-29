import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/errors/error_handler.dart';
import 'package:fullpos/core/logging/app_logger.dart';
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

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('fullpos_error_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await AppLogger.instance.init();
  });

  tearDownAll(() async {
    await AppLogger.instance.flush();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'suppresses Flutter inactive element assertion as transient UI noise',
    () {
      const message =
          "'package:flutter/src/widgets/framework.dart': Failed assertion: "
          "line 2168 pos 12: '_elements.contains(element)': is not true.\n"
          'InactiveElements.remove';

      expect(ErrorHandler.isTransientFlutterLayoutError(message), isTrue);
    },
  );

  test(
    'suppresses framework assertion variant without exact private symbol',
    () {
      const message =
          "'package:flutter/src/widgets/framework.dart': Failed assertion: "
          "line 2168 pos 12: 'elements.contains(element)': is not true.";

      expect(ErrorHandler.isTransientFlutterLayoutError(message), isTrue);
    },
  );

  test('platform error route accepts transient Flutter assertion', () {
    final handled = ErrorHandler.instance.reportPlatformError(
      AssertionError(
        "'package:flutter/src/widgets/framework.dart': Failed assertion: "
        "line 2168 pos 12: '_elements.contains(element)': is not true.",
      ),
      StackTrace.fromString(
        'InactiveElements.remove '
        '(package:flutter/src/widgets/framework.dart:2168:12)',
      ),
      module: 'platform',
    );

    expect(handled, isTrue);
  });
}
