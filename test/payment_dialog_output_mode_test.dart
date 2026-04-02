import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('usa PDF cuando Negocio configura pdf y la descarga esta permitida', (
    tester,
  ) async {
    await pumpDialog(tester, initialChargeOutputMode: 'pdf');

    expect(find.text('COBRAR Y DESCARGAR'), findsOneWidget);
  });

  testWidgets('usa sin imprimir cuando Negocio configura none', (tester) async {
    await pumpDialog(tester, initialChargeOutputMode: 'none');

    expect(find.text('COBRAR SIN IMPRIMIR'), findsOneWidget);
  });

  testWidgets('cae a ticket si pdf no esta permitido aunque venga configurado', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      initialChargeOutputMode: 'pdf',
      allowInvoicePdfDownload: false,
      initialPrintTicket: true,
    );

    expect(find.text('COBRAR E IMPRIMIR'), findsOneWidget);
  });

  testWidgets('muestra selector de documento al inicio del dialogo', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      initialDocumentType: PaymentDocumentType.creditoFiscal,
    );

    expect(find.text('TIPO DE DOCUMENTO'), findsOneWidget);
    expect(find.text('Crédito fiscal'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<PaymentDocumentType>));
    await tester.pumpAndSettle();

    expect(find.text('Factura cliente final'), findsWidgets);
    expect(find.text('Crédito fiscal'), findsWidgets);
    expect(find.text('Cotización'), findsWidgets);
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
    expect(find.text('TIPO DE DOCUMENTO'), findsOneWidget);
    expect(find.text('TOTAL A PAGAR:'), findsOneWidget);
  });
}