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

  testWidgets('oculta el texto indicativo superior en modo cobro', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.text('SELECCIONE EL MÉTODO DE PAGO'), findsNothing);
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

    expect(find.text('Tipo de documento'), findsOneWidget);
    expect(find.text('Crédito fiscal'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<PaymentDocumentType>));
    await tester.pumpAndSettle();

    expect(find.text('Factura cliente final'), findsWidgets);
    expect(find.text('Crédito fiscal'), findsWidgets);
    expect(find.text('Cotización'), findsWidgets);
  });

  testWidgets('ubica tipo de documento entre total y metodo de pago', (
    tester,
  ) async {
    await pumpDialog(tester);

    final totalLabel = find.text('TOTAL A PAGAR:');
    final documentLabel = find.text('Tipo de documento');
    final paymentMethodLabel = find.text('MÉTODO DE PAGO');

    final totalBottom = tester.getBottomLeft(totalLabel).dy;
    final documentTop = tester.getTopLeft(documentLabel).dy;
    final documentBottom = tester.getBottomLeft(documentLabel).dy;
    final paymentMethodTop = tester.getTopLeft(paymentMethodLabel).dy;

    expect(documentTop, greaterThan(totalBottom));
    expect(paymentMethodTop, greaterThan(documentBottom));
  });

  testWidgets('oculta selector de documento cuando facturacion esta desactivada', (
    tester,
  ) async {
    await pumpDialog(tester, allowElectronicInvoiceOption: false);

    expect(find.text('Tipo de documento'), findsNothing);
    expect(find.byType(DropdownButtonFormField<PaymentDocumentType>), findsNothing);
  });

  testWidgets('no deja espacio extra al ocultar tipo de documento', (
    tester,
  ) async {
    await pumpDialog(tester, allowElectronicInvoiceOption: false);

    final totalLabel = find.text('TOTAL A PAGAR:');
    final receivedLabel = find.text('CLIENTE PAGA CON:');

    final totalBottom = tester.getBottomLeft(totalLabel).dy;
    final receivedTop = tester.getTopLeft(receivedLabel).dy;

    expect(receivedTop - totalBottom, lessThan(120));
  });

  testWidgets('mantiene estilo compacto y minimalista del selector', (
    tester,
  ) async {
    await pumpDialog(tester);

    final sizedBox = tester.widget<SizedBox>(
      find.ancestor(
        of: find.byType(DropdownButtonFormField<PaymentDocumentType>),
        matching: find.byType(SizedBox),
      ).first,
    );
    final dropdown = tester.widget<DropdownButtonFormField<PaymentDocumentType>>(
      find.byType(DropdownButtonFormField<PaymentDocumentType>),
    );
    final decoration = dropdown.decoration;

    expect(sizedBox.height, 44);
    expect(decoration.filled, isTrue);
    expect(decoration.fillColor, isNotNull);
    expect((decoration.enabledBorder as OutlineInputBorder).borderSide,
        BorderSide.none);
  });

  testWidgets('muestra las opciones de salida en una sola fila y con modal mas ancho', (
    tester,
  ) async {
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
  });

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
    expect(find.text('Tipo de documento'), findsOneWidget);
    expect(find.text('TOTAL A PAGAR:'), findsOneWidget);
  });
}