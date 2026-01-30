import 'package:flutter_test/flutter_test.dart';

import 'package:fullpos/core/security/app_actions.dart';
import 'package:fullpos/core/security/authz/authz_service.dart';
import 'package:fullpos/core/security/authz/authz_user.dart';
import 'package:fullpos/core/security/authz/permission.dart';
import 'package:fullpos/features/settings/data/user_model.dart';

void main() {
  test('AuthzService.can: admin always allowed', () {
    final user = AuthzUser(
      userId: 1,
      companyId: 1,
      role: 'admin',
      terminalId: 't1',
      modulePermissions: UserPermissions.none(),
      actionPermissions: const {},
    );

    expect(AuthzService.can(user, Permissions.reportsView), isTrue);
    expect(
      AuthzService.can(user, Permission.action(AppActions.processReturn)),
      isTrue,
    );
  });

  test('AuthzService.can: screen permission via legacy key', () {
    final user = AuthzUser(
      userId: 2,
      companyId: 1,
      role: 'cashier',
      terminalId: 't1',
      modulePermissions: const UserPermissions(canViewReports: false),
      actionPermissions: const {},
    );

    expect(AuthzService.can(user, Permissions.reportsView), isFalse);
  });

  test('AuthzService.can: action permission via actionPermissions cache', () {
    final code = AppActions.processReturn.code;
    final user = AuthzUser(
      userId: 2,
      companyId: 1,
      role: 'cashier',
      terminalId: 't1',
      modulePermissions: UserPermissions.none(),
      actionPermissions: {code: true},
    );

    expect(AuthzService.can(user, Permissions.processReturn), isTrue);
  });
}

