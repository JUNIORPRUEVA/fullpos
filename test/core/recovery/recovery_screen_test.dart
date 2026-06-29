import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/recovery/app_recovery.dart';
import 'package:fullpos/core/recovery/recovery_screen.dart';

void main() {
  testWidgets('RecoveryScreen renderiza contenido y evita pantalla blanca', (
    tester,
  ) async {
    const state = AppRecoveryState.active(
      kind: AppRecoveryKind.identity,
      reason: 'router_license_gate_recovery_required',
    );

    await tester.pumpWidget(
      const MaterialApp(home: RecoveryScreen(state: state)),
    );

    expect(find.text('Reactivar terminal'), findsOneWidget);
    expect(find.textContaining('Código técnico'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
