import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/sales/ui/dialogs/quick_item_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: QuickItemDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder priceField() => find.byType(TextFormField).at(2);

  TextEditingController fieldController(WidgetTester tester, Finder finder) {
    final field = tester.widget<TextFormField>(finder);
    return field.controller!;
  }

  String fieldText(WidgetTester tester, Finder finder) {
    return fieldController(tester, finder).text;
  }

  Future<void> tapCalculatorKey(WidgetTester tester, String key) async {
    await tester.tap(find.text(key).last);
    await tester.pump();
  }

  group('QuickItemDialog calculator amount entry', () {
    testWidgets('keeps price equal to the calculator amount from keypad taps', (
      tester,
    ) async {
      await pumpDialog(tester);

      for (final key in ['2', '2', '0', '2', '0', '2', '0']) {
        await tapCalculatorKey(tester, key);
      }

      expect(fieldText(tester, priceField()), '2202020');
      expect(find.text('2202020'), findsNWidgets(2));
    });

    testWidgets('continues from a manually typed price without changing it', (
      tester,
    ) async {
      await pumpDialog(tester);

      await tester.tap(priceField());
      await tester.pump();
      await tester.enterText(priceField(), '2202020');
      await tester.pump();

      await tapCalculatorKey(tester, '0');

      expect(fieldText(tester, priceField()), '22020200');
      expect(find.text('22020200'), findsNWidgets(2));
    });

    testWidgets('deletes the selected price with the Delete key', (
      tester,
    ) async {
      await pumpDialog(tester);

      await tester.tap(priceField());
      await tester.pump();
      await tester.enterText(priceField(), '2202020');
      await tester.pump();

      final controller = fieldController(tester, priceField());
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(fieldText(tester, priceField()), isEmpty);
    });

    testWidgets('deletes the selected price with the on-screen DEL key', (
      tester,
    ) async {
      await pumpDialog(tester);

      await tester.tap(priceField());
      await tester.pump();
      await tester.enterText(priceField(), '2202020');
      await tester.pump();

      final controller = fieldController(tester, priceField());
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.pump();

      await tapCalculatorKey(tester, 'DEL');

      expect(fieldText(tester, priceField()), isEmpty);
    });
  });
}
