import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/errors/app_exception.dart';
import 'package:fullpos/core/ui/app_error_dialog.dart';

void main() {
  const exception = AppException(
    type: AppErrorType.unknown,
    messageUser: 'No fue posible completar la operación.',
    messageDev: 'Error técnico de prueba.',
  );

  testWidgets('uses a compact presentation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppErrorDialog(exception: exception)),
      ),
    );

    final dialogSize = tester.getSize(
      find.byKey(const ValueKey('app-error-dialog-card')),
    );
    expect(dialogSize.width, lessThanOrEqualTo(340));
    expect(dialogSize.height, lessThan(180));
    expect(find.text('Ocurrió un problema'), findsOneWidget);
  });

  testWidgets('keeps technical details collapsed by default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppErrorDialog(exception: exception)),
      ),
    );

    expect(find.text('Error técnico de prueba.'), findsNothing);
    expect(find.text('Ver detalles'), findsOneWidget);
  });

  testWidgets('copies support details without requiring a scaffold context', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppErrorDialog(exception: exception)),
      ),
    );

    expect(find.text('Copiar soporte'), findsOneWidget);
    expect(find.text('Ignorar'), findsOneWidget);

    await tester.tap(find.text('Copiar soporte'));
    await tester.pump();

    expect(find.text('Copiado'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 1200));
  });
}
