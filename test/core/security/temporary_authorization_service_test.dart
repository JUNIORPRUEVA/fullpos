import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/security/temporary_authorization_service.dart';

void main() {
  tearDown(() {
    TemporaryAuthorizationService.clearAll();
    TemporaryAuthorizationService.debugResetClock();
  });

  test('authorization lasts at least two minutes', () {
    final start = DateTime(2026, 1, 1, 12);
    var now = start;
    TemporaryAuthorizationService.debugSetClock(() => now);

    TemporaryAuthorizationService.authorize(
      scope: 'inventory.add_stock',
      duration: const Duration(minutes: 2),
      approvedByUserId: '1',
    );

    now = start.add(const Duration(minutes: 1, seconds: 59));
    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.add_stock'),
      isTrue,
    );

    now = start.add(const Duration(minutes: 2));
    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.add_stock'),
      isFalse,
    );
  });

  test('authorization is scoped and survives repeated checks until expiry', () {
    final start = DateTime(2026, 1, 1, 12);
    var now = start;
    TemporaryAuthorizationService.debugSetClock(() => now);

    TemporaryAuthorizationService.authorize(
      scope: 'inventory.adjust',
      approvedByUserId: '2',
    );

    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.adjust'),
      isTrue,
    );
    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.add_stock'),
      isFalse,
    );
    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.remove_stock'),
      isFalse,
    );

    now = start.add(const Duration(minutes: 2, milliseconds: 1));
    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.adjust'),
      isFalse,
    );
  });

  test('clearAll removes session authorizations', () {
    TemporaryAuthorizationService.authorize(
      scope: 'cash.withdraw',
      approvedByUserId: '3',
    );

    expect(
      TemporaryAuthorizationService.isAuthorized('cash.manual_movement'),
      isTrue,
    );

    TemporaryAuthorizationService.clearAll();

    expect(
      TemporaryAuthorizationService.isAuthorized('cash.withdraw'),
      isFalse,
    );
  });

  test('clearAuthorization removes only one scope', () {
    TemporaryAuthorizationService.authorize(
      scope: 'inventory.add_stock',
      approvedByUserId: '1',
    );
    TemporaryAuthorizationService.authorize(
      scope: 'cash.withdraw',
      approvedByUserId: '1',
    );

    TemporaryAuthorizationService.clearAuthorization('inventory.add_stock');

    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.add_stock'),
      isFalse,
    );
    expect(
      TemporaryAuthorizationService.isAuthorized('cash.manual_movement'),
      isTrue,
    );
  });

  test('inventory.adjust_stock scope is specific and not aliased to other scopes', () {
    TemporaryAuthorizationService.authorize(
      scope: 'inventory.adjust_stock',
      approvedByUserId: '1',
    );

    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.adjust_stock'),
      isTrue,
    );
    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.add_stock'),
      isFalse,
    );
    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.remove_stock'),
      isFalse,
    );
    expect(
      TemporaryAuthorizationService.isAuthorized('inventory.adjust'),
      isFalse,
    );
  });
}
