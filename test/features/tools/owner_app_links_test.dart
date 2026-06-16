import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/tools/data/owner_app_links.dart';

void main() {
  test('FullPOS Owner distribution points to the published repository asset', () {
    final uri = Uri.parse(OwnerAppDistribution.androidDownloadUrl);

    expect(uri.scheme, 'https');
    expect(uri.host, 'github.com');
    expect(
      uri.path,
      '/JUNIORPRUEVA/fullposOwner_release/releases/latest/download/app-debug.apk',
    );
    expect(OwnerAppDistribution.androidSha256, hasLength(64));
    expect(
      RegExp(r'^[0-9a-f]{64}$').hasMatch(OwnerAppDistribution.androidSha256),
      isTrue,
    );
  });
}
