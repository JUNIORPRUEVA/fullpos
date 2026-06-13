import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/update/app_version.dart';

void main() {
  test('compares semantic versions numerically', () {
    expect(AppVersion.parse('1.0.0') < AppVersion.parse('1.0.1'), isTrue);
    expect(AppVersion.parse('1.0.9') < AppVersion.parse('1.0.10'), isTrue);
    expect(AppVersion.parse('1.9.0') < AppVersion.parse('1.10.0'), isTrue);
  });

  test('uses build number after semantic version', () {
    expect(AppVersion.parse('1.0.1+4') < AppVersion.parse('1.0.1+5'), isTrue);
  });

  test('handles equality, newer versions and leading v', () {
    expect(AppVersion.parse('1.0.1+5'), AppVersion.parse('  v1.0.1+5 '));
    expect(AppVersion.parse('2.0.0') > AppVersion.parse('1.99.99'), isTrue);
  });

  test('rejects malformed versions', () {
    expect(() => AppVersion.parse('1.0'), throwsFormatException);
    expect(() => AppVersion.parse('latest'), throwsFormatException);
  });
}
