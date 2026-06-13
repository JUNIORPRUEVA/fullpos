import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/update/app_update_policy.dart';
import 'package:fullpos/core/update/installer_verifier.dart';

AppUpdatePolicy makePolicy(List<int> bytes, {int? expectedSize}) {
  return AppUpdatePolicy.fromJson({
    'projectCode': 'fullpos',
    'platform': 'windows',
    'latestVersion': '1.0.2',
    'latestBuild': 6,
    'minimumSupportedVersion': '1.0.1',
    'minimumSupportedBuild': 5,
    'mandatory': false,
    'enabled': true,
    'installerUrl':
        'https://github.com/JUNIORPRUEVA/fullpos-releases/releases/download/v1.0.2/FullPOS-Setup.exe',
    'installerFilename': 'FullPOS-Setup.exe',
    'installerSizeBytes': expectedSize ?? bytes.length,
    'sha256': sha256.convert(bytes).toString(),
    'releaseTitle': 'FullPOS v1.0.2',
    'releaseNotes': ['Mejoras.'],
    'publishedAt': '2026-06-12T22:00:00Z',
  });
}

void main() {
  late Directory temp;
  late File installer;
  final verifier = InstallerVerifier();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fullpos_update_test_');
    installer = File('${temp.path}${Platform.pathSeparator}FullPOS-Setup.exe');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('accepts matching SHA-256, size and MZ header', () async {
    final bytes = <int>[0x4d, 0x5a, ...List<int>.filled(64, 7)];
    await installer.writeAsBytes(bytes);
    await verifier.verify(
      file: installer,
      approvedRoot: temp,
      policy: makePolicy(bytes),
    );
  });

  test('rejects SHA-256 mismatch', () async {
    final bytes = <int>[0x4d, 0x5a, ...List<int>.filled(32, 1)];
    await installer.writeAsBytes(bytes);
    final different = <int>[0x4d, 0x5a, ...List<int>.filled(32, 2)];
    expect(
      verifier.verify(
        file: installer,
        approvedRoot: temp,
        policy: makePolicy(different, expectedSize: bytes.length),
      ),
      throwsA(isA<InstallerVerificationException>()),
    );
  });

  test('rejects incorrect size and invalid PE header', () async {
    final bytes = <int>[0x4d, 0x5a, 1, 2, 3];
    await installer.writeAsBytes(bytes);
    expect(
      verifier.verify(
        file: installer,
        approvedRoot: temp,
        policy: makePolicy(bytes, expectedSize: bytes.length + 1),
      ),
      throwsA(isA<InstallerVerificationException>()),
    );

    final invalid = <int>[1, 2, 3, 4];
    await installer.writeAsBytes(invalid);
    expect(
      verifier.verify(
        file: installer,
        approvedRoot: temp,
        policy: makePolicy(invalid),
      ),
      throwsA(isA<InstallerVerificationException>()),
    );
  });

  test('rejects HTML saved as executable', () async {
    final bytes = <int>[
      0x4d,
      0x5a,
      ...'<html><body>Not found</body></html>'.codeUnits,
    ];
    await installer.writeAsBytes(bytes);
    expect(
      verifier.verify(
        file: installer,
        approvedRoot: temp,
        policy: makePolicy(bytes),
      ),
      throwsA(isA<InstallerVerificationException>()),
    );
  });
}
