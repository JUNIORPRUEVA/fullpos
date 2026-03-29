import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/sales/ui/dialogs/payment_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    String? initialChargeOutputMode,
    bool allowInvoicePdfDownload = true,
    bool initialPrintTicket = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentDialog(
            total: 150,
            initialPrintTicket: initialPrintTicket,
            allowInvoicePdfDownload: allowInvoicePdfDownload,
            initialChargeOutputMode: initialChargeOutputMode,
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
}