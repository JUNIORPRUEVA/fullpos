import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/clients/data/client_model.dart';
import 'package:fullpos/features/sales/ui/dialogs/payment_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    String? initialChargeOutputMode,
    bool allowInvoicePdfDownload = true,
    bool initialPrintTicket = true,
    PaymentDocumentType initialDocumentType =
        PaymentDocumentType.consumidorFinal,
    bool allowElectronicInvoiceOption = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentDialog(
            total: 150,
            initialPrintTicket: initialPrintTicket,
            allowInvoicePdfDownload: allowInvoicePdfDownload,
            initialChargeOutputMode: initialChargeOutputMode,
            initialDocumentType: initialDocumentType,
            allowElectronicInvoiceOption: allowElectronicInvoiceOption,
            onDocumentTypeChanged: (type) async => type,
            onSelectClient: () async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('usa ticket cuando Negocio configura ticket', (tester) async {
    await pumpDialog(tester, initialChargeOutputMode: 'ticket');

    expect(find.text('COBRAR E IMPRIMIR'), findsOneWidget);
  });

  testWidgets(
    'usa PDF cuando Negocio configura pdf y la descarga esta permitida',
    (tester) async {
      await pumpDialog(tester, initialChargeOutputMode: 'pdf');

      expect(find.text('COBRAR Y DESCARGAR'), findsOneWidget);
    },
  );

  testWidgets('usa sin imprimir cuando Negocio configura none', (tester) async {
    await pumpDialog(tester, initialChargeOutputMode: 'none');

    expect(find.text('COBRAR SIN IMPRIMIR'), findsOneWidget);
  });

  testWidgets('oculta el texto indicativo superior en modo cobro', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.text('SELECCIONE EL MÉTODO DE PAGO'), findsNothing);
  });

  testWidgets(
    'cae a ticket si pdf no esta permitido aunque venga configurado',
    (tester) async {
      await pumpDialog(
        tester,
        initialChargeOutputMode: 'pdf',
        allowInvoicePdfDownload: false,
        initialPrintTicket: true,
      );

      expect(find.text('COBRAR E IMPRIMIR'), findsOneWidget);
    },
  );

  testWidgets('muestra selector de comprobante al inicio del dialogo', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      initialDocumentType: PaymentDocumentType.creditoFiscal,
    );

    expect(find.text('Tipo de comprobante'), findsOneWidget);
    expect(find.text('Venta normal'), findsOneWidget);
    expect(find.text('Factura electrónica'), findsOneWidget);
    expect(find.text('Cotización'), findsOneWidget);
    expect(find.text('Tipo de cliente'), findsOneWidget);
    expect(find.text('Empresa / negocio'), findsOneWidget);
  });

  testWidgets('ubica tipo de comprobante entre total y metodo de pago', (
    tester,
  ) async {
    await pumpDialog(tester);

    final totalLabel = find.text('TOTAL A PAGAR:');
    final documentLabel = find.text('Tipo de comprobante');
    final paymentMethodLabel = find.text('MÉTODO DE PAGO');

    final totalBottom = tester.getBottomLeft(totalLabel).dy;
    final documentTop = tester.getTopLeft(documentLabel).dy;
    final documentBottom = tester.getBottomLeft(documentLabel).dy;
    final paymentMethodTop = tester.getTopLeft(paymentMethodLabel).dy;

    expect(documentTop, greaterThan(totalBottom));
    expect(paymentMethodTop, greaterThan(documentBottom));
  });

  testWidgets(
    'mantiene consumidor final y cotizacion cuando facturacion esta desactivada',
    (tester) async {
      await pumpDialog(tester, allowElectronicInvoiceOption: false);

      expect(find.text('Tipo de comprobante'), findsOneWidget);
      expect(find.text('Venta normal'), findsOneWidget);
      expect(find.text('Cotización'), findsOneWidget);
      expect(find.text('Factura electrónica'), findsNothing);
    },
  );

  testWidgets(
    'normaliza a consumidor final si credito fiscal llega deshabilitado',
    (tester) async {
      await pumpDialog(
        tester,
        allowElectronicInvoiceOption: false,
        initialDocumentType: PaymentDocumentType.creditoFiscal,
      );

      expect(find.text('Venta normal'), findsOneWidget);
      expect(find.text('Factura electrónica'), findsNothing);
    },
  );

  testWidgets('muestra las tarjetas del selector de comprobante', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.text('Venta normal'), findsOneWidget);
    expect(find.text('Factura electrónica'), findsOneWidget);
    expect(find.text('Cotización'), findsOneWidget);
  });

  testWidgets(
    'muestra las opciones de salida en una sola fila y con modal mas ancho',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpDialog(tester);

      final dialogWidth = tester.getSize(find.byType(Dialog)).width;
      final ticketY = tester.getTopLeft(find.text('TICKET')).dy;
      final pdfY = tester.getTopLeft(find.text('PDF')).dy;
      final noneY = tester.getTopLeft(find.text('SIN IMPRIMIR')).dy;

      expect(dialogWidth, greaterThanOrEqualTo(700));
      expect((ticketY - pdfY).abs(), lessThan(6));
      expect((ticketY - noneY).abs(), lessThan(6));
    },
  );

  testWidgets('adapta el dialogo a modo cotizacion', (tester) async {
    await pumpDialog(
      tester,
      initialDocumentType: PaymentDocumentType.cotizacion,
    );

    expect(find.text('GENERAR COTIZACIÓN'), findsOneWidget);
    expect(find.text('TOTAL COTIZADO:'), findsOneWidget);
    expect(find.text('CLIENTE DE LA COTIZACIÓN'), findsOneWidget);
    expect(find.text('GUARDAR COTIZACIÓN'), findsOneWidget);
    expect(find.text('MÉTODO DE PAGO'), findsNothing);
  });

  testWidgets('se adapta en ancho reducido sin errores de render', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpDialog(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Tipo de comprobante'), findsOneWidget);
    expect(find.text('TOTAL A PAGAR:'), findsOneWidget);
  });

  testWidgets('permite seleccionar consumidor final para E32 sin pedir RNC', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      initialDocumentType: PaymentDocumentType.creditoFiscal,
    );

    await tester.ensureVisible(
      find.byType(Radio<PaymentElectronicCustomerType>).first,
    );
    await tester.tap(find.byType(Radio<PaymentElectronicCustomerType>).first);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Se generará un comprobante E32'),
      findsOneWidget,
    );
    expect(find.text('RNC *'), findsNothing);
  });

  testWidgets('retorna cotizacion real al cambiar de modo dentro del dialogo', (
    tester,
  ) async {
    Map<String, dynamic>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showDialog<Map<String, dynamic>>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => PaymentDialog(
                      total: 150,
                      selectedClient: ClientModel(
                        id: 1,
                        nombre: 'Cliente Cotizacion',
                        telefono: '+18295551234',
                        direccion: 'Calle 1',
                        rnc: null,
                        cedula: '00112345678',
                        createdAtMs: 1,
                        updatedAtMs: 1,
                      ),
                      onDocumentTypeChanged: (type) async => type,
                      onSelectClient: () async => null,
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

    await tester.tap(find.text('Cotización'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GUARDAR COTIZACIÓN'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!['documentType'], PaymentDocumentType.cotizacion);
    expect(result!['selectedClient'], isA<ClientModel>());
  });

  testWidgets('retorna resultado empresarial E31 con PDF sin romper el flujo', (
    tester,
  ) async {
    Map<String, dynamic>? result;
    final selectedClient = ClientModel(
      id: 7,
      nombre: 'Empresa Demo',
      telefono: '+18295550000',
      direccion: 'Calle Fiscal',
      rnc: '131246796',
      cedula: null,
      createdAtMs: 1,
      updatedAtMs: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showDialog<Map<String, dynamic>>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => PaymentDialog(
                      total: 150,
                      initialChargeOutputMode: 'pdf',
                      initialDocumentType: PaymentDocumentType.creditoFiscal,
                      selectedClient: selectedClient,
                      onDocumentTypeChanged: (type) async => type,
                      onSelectClient: () async => null,
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

    await tester.ensureVisible(find.text('COBRAR Y DESCARGAR'));
    await tester.tap(find.text('COBRAR Y DESCARGAR'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar factura electrónica'), findsOneWidget);
    await tester.tap(find.text('Generar factura'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!['documentType'], PaymentDocumentType.creditoFiscal);
    expect(result!['downloadInvoicePdf'], isTrue);
    expect(result!['selectedClient'], isA<ClientModel>());
    expect((result!['selectedClient'] as ClientModel).rnc, '131246796');
  });
}
