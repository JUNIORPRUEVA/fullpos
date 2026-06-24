import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/errors/error_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
