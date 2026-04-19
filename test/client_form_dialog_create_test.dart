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

  testWidgets('ClientFormDialog muestra duplicado existente y no guarda', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final existingClient = ClientModel(
      id: 9,
      nombre: 'Cliente Existente',
      telefono: '+18295887858',
      direccion: 'Calle A',
      rnc: null,
      cedula: '00112345678',
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    var saveCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await showDialog<ClientModel>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => ClientFormDialog(
                      getByPhone: (_) async => existingClient,
                      saveClient: (client, _) async {
                        saveCalled = true;
                        return client.copyWith(id: 1);
                      },
                    ),
                  );
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
    await tester.enterText(fields.at(0), 'Juan Perez');
    await tester.enterText(fields.at(1), '8295887858');

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Cliente ya registrado'), findsOneWidget);
    expect(
      find.text('Ya existe un cliente con este teléfono:'),
      findsOneWidget,
    );
    expect(find.text('Nombre: Cliente Existente'), findsOneWidget);
    expect(saveCalled, isFalse);

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    expect(find.text('Guardar'), findsOneWidget);
    expect(saveCalled, isFalse);
  });
}
