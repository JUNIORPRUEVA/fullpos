import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/settings/data/user_model.dart';

void main() {
  group('Cash permissions migration compatibility', () {
    test('legacy can_open_cash/can_close_cash backfills shift and cashbox flags', () {
      final perms = UserPermissions.fromMap(
        const {
          'can_open_cash': true,
          'can_close_cash': true,
        },
      );

      expect(perms.canOpenCashbox, isTrue);
      expect(perms.canCloseCashbox, isTrue);
      expect(perms.canOpenShift, isTrue);
      expect(perms.canCloseShift, isTrue);
    });

    test('cashier defaults allow shift but not cashbox close', () {
      final perms = UserPermissions.cashier();
      expect(perms.canOpenShift, isTrue);
      expect(perms.canCloseShift, isTrue);
      expect(perms.canOpenCashbox, isFalse);
      expect(perms.canCloseCashbox, isFalse);
      expect(perms.canExitWithOpenShift, isFalse);
    });

    test('admin defaults allow exit with open shift', () {
      final perms = UserPermissions.admin();
      expect(perms.canExitWithOpenShift, isTrue);
    });
  });
}
