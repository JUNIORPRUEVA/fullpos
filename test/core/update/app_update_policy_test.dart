import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/update/app_update_policy.dart';
import 'package:fullpos/core/update/app_version.dart';

Map<String, dynamic> policyJson({
  bool mandatory = false,
  String minimumVersion = '1.0.1',
  int minimumBuild = 5,
  String url =
      'https://github.com/JUNIORPRUEVA/fullpos-releases/releases/download/v1.0.2/FullPOS-Setup.exe',
}) => {
  'projectCode': 'fullpos',
  'platform': 'windows',
  'latestVersion': '1.0.2',
  'latestBuild': 6,
  'minimumSupportedVersion': minimumVersion,
  'minimumSupportedBuild': minimumBuild,
  'mandatory': mandatory,
  'enabled': true,
  'installerUrl': url,
  'installerFilename': 'FullPOS-Setup.exe',
  'installerSizeBytes': 120,
  'sha256': List<String>.filled(64, 'a').join(),
  'releaseTitle': 'FullPOS v1.0.2',
  'releaseNotes': ['Mejoras.'],
  'publishedAt': '2026-06-12T22:00:00Z',
};

void main() {
  test('returns optional for a supported older installation', () {
    final policy = AppUpdatePolicy.fromJson(policyJson());
    expect(policy.decide(AppVersion.parse('1.0.1+5')), UpdateDecision.optional);
  });

  test('mandatory flag forces an available update', () {
    final policy = AppUpdatePolicy.fromJson(policyJson(mandatory: true));
    expect(
      policy.decide(AppVersion.parse('1.0.1+5')),
      UpdateDecision.mandatory,
    );
  });

  test('minimum supported version is authoritative', () {
    final policy = AppUpdatePolicy.fromJson(
      policyJson(minimumVersion: '1.0.1', minimumBuild: 5),
    );
    expect(
      policy.decide(AppVersion.parse('1.0.1+4')),
      UpdateDecision.mandatory,
    );
  });

  test('equal or newer installation needs no update', () {
    final policy = AppUpdatePolicy.fromJson(policyJson());
    expect(policy.decide(AppVersion.parse('1.0.2+6')), UpdateDecision.none);
    expect(policy.decide(AppVersion.parse('1.1.0+1')), UpdateDecision.none);
  });

  test('rejects malformed policy and unsafe URLs', () {
    expect(
      () => AppUpdatePolicy.fromJson(
        policyJson(url: 'http://github.com/FullPOS-Setup.exe'),
      ),
      throwsFormatException,
    );
    expect(
      () => AppUpdatePolicy.fromJson(
        policyJson(url: 'https://example.com/FullPOS-Setup.exe'),
      ),
      throwsFormatException,
    );
    expect(
      () => AppUpdatePolicy.fromJson({...policyJson(), 'latestVersion': 'bad'}),
      throwsFormatException,
    );
  });

  test('allows the official GitHub release asset redirect host', () {
    final redirect = Uri.parse(
      'https://release-assets.githubusercontent.com/'
      'github-production-release-asset/123/installer'
      '?response-content-disposition=attachment',
    );

    expect(
      () => AppUpdatePolicy.validateInstallerUri(redirect),
      returnsNormally,
    );
  });

  test('continues rejecting lookalike GitHub asset hosts', () {
    expect(
      () => AppUpdatePolicy.validateInstallerUri(
        Uri.parse(
          'https://release-assets.githubusercontent.com.evil.example/'
          'FullPOS-Setup.exe',
        ),
      ),
      throwsFormatException,
    );
  });
}
