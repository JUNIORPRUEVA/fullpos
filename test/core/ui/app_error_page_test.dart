import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/errors/app_exception.dart';
import 'package:fullpos/core/ui/app_error_page.dart';

void main() {
  testWidgets('does not expose technical details in fallback page', (
    tester,
  ) async {
    const exception = AppException(
      type: AppErrorType.unknown,
      messageUser: 'No se pudo completar la acción.',
      messageDev: 'FlutterErrorDetails: stack técnico interno',
    );

    await tester.pumpWidget(
      const MaterialApp(home: AppErrorPage(exception: exception)),
    );

    expect(find.text('No pudimos completar la acción'), findsOneWidget);
    expect(find.text('Ver detalles'), findsNothing);
    expect(find.textContaining('FlutterErrorDetails'), findsNothing);
  });
}
