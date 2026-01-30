import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/clients/data/client_model.dart';
import 'package:fullpos/features/clients/ui/client_form_dialog.dart';

void main() {
  testWidgets('ClientFormDialog crea cliente y retorna ClientModel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final resultNotifier = ValueNotifier<ClientModel?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  final result = await showDialog<ClientModel>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => ClientFormDialog(
                      getByPhone: (_) async => null,
                      saveClient: (client, _) async => client.copyWith(id: 1),
                    ),
                  );
                  resultNotifier.value = result;
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(5));

    await tester.enterText(fields.at(0), 'Juan Perez');
    await tester.enterText(fields.at(1), '8295887858');

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final created = resultNotifier.value;
    expect(created, isNotNull);
    expect(created!.id, 1);
    expect(created.nombre, 'Juan Perez');
    expect(created.telefono, '+18295887858');
  });
}

