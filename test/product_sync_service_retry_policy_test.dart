import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/sync/product_sync_service.dart';

void main() {
  test('treats HTTP 400 as terminal for product sync retries', () {
    expect(isTerminalProductSyncStatus(400), isTrue);
    expect(isTerminalProductSyncStatus(409), isFalse);
    expect(isTerminalProductSyncStatus(500), isFalse);
    expect(isTerminalProductSyncStatus(null), isFalse);
  });
}
