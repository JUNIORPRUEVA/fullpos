import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fullpos/core/security/authz/permission.dart';
import 'package:fullpos/core/security/authz/permission_gate.dart';

void main() {
  testWidgets('PermissionGate keeps child visible and shows blocked overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PermissionGate(
            permission: Permissions.reportsView,
            autoPromptOnce: false,
            child: const Text('CHILD_CONTENT'),
          ),
        ),
      ),
    );

    expect(find.text('CHILD_CONTENT'), findsOneWidget);
    expect(find.text('Acción prohibida'), findsOneWidget);
    expect(find.text('Autorizar'), findsOneWidget);
  });
}

