import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/ui/app_toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AppToast renders overlay message and dismisses it', (
    tester,
  ) async {
    late BuildContext buttonContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              buttonContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    AppToast.show(
      buttonContext,
      'Guardado correctamente',
      type: AppToastType.success,
      duration: const Duration(milliseconds: 150),
    );

    await tester.pump();

    expect(find.text('Operacion completada'), findsOneWidget);
    expect(find.text('Guardado correctamente'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Guardado correctamente'), findsNothing);
  });
}