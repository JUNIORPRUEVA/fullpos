import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/services/cloud_sync_service.dart';

void main() {
  test('cloud sync exposes only the required business targets', () {
    expect(CloudSyncService.visibleTargetKeys, {
      'products',
      'categories',
      'clients',
      'company_config',
      'users',
      'sales',
    });
  });
}
