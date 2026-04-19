import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/printing/models/company_info.dart';
import 'package:fullpos/core/printing/models/ticket_data.dart';
import 'package:fullpos/core/printing/unified_ticket_preview_widget.dart';
import 'package:fullpos/features/settings/data/printer_settings_model.dart';

PrinterSettingsModel _defaultPrinterSettings({int paperWidthMm = 80}) {
  final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
  return PrinterSettingsModel(
    paperWidthMm: paperWidthMm,
    createdAtMs: now,
    updatedAtMs: now,
  );
}

CompanyInfo _sampleCompany() {
  return const CompanyInfo(
    name: 'FERRETERIA DEMO SRL',
    address: 'CARRETERA HIGUEY KM 5',
    rnc: '123456789',
    phone: '(809) 555-1234',
  );
}

TicketData _sampleSaleData() {
  return TicketData(
    ticketNumber: '003740',
    dateTime: DateTime(2026, 1, 12, 16, 5),
    cashierName: 'CAJA3',
    client: const ClientInfo(
      name: 'EMPRESA FISCAL DEMO SRL',
      rnc: '131246796',
      phone: '(809) 222-3344',
    ),
    items: const [
      TicketItemData(
        name: 'DESTORNILLADOR',
        quantity: 1,
        unitPrice: 55.00,
        total: 55.00,
      ),
    ],
    subtotal: 55.00,
    itbis: 9.90,
    itbisRate: 0.18,
    total: 64.90,
    paymentMethod: 'EFECTIVO',
    paidAmount: 100.00,
    changeAmount: 35.10,
    electronicInvoiceCode: 'B020000000000058',
    electronicDocumentType: '31',
    electronicDgiiStatus: 'aceptada',
    electronicTrackId: 'DGII-TRK-2026-000058',
    electronicDgiiCode: '100',
    electronicDgiiMessage: 'Comprobante aceptado por DGII',
    electronicEnvironment: 'production',
    type: TicketType.sale,
  );
}

void main() {
  testWidgets('Preview muestra bloque fiscal electronico completo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: UnifiedTicketPreviewWidget(
                settings: _defaultPrinterSettings(),
                company: _sampleCompany(),
                data: _sampleSaleData(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('DOC. FE:'), findsOneWidget);
    expect(find.text('31 CREDITO FISCAL'), findsOneWidget);
    expect(find.text('E-CF:'), findsOneWidget);
    expect(find.text('B020000000000058'), findsOneWidget);
    expect(find.text('ESTADO DGII:'), findsOneWidget);
    expect(find.text('ACEPTADA'), findsOneWidget);
    expect(find.text('TRACK ID:'), findsOneWidget);
    expect(find.text('DGII-TRK-2026-000058'), findsOneWidget);
    expect(find.text('AMBIENTE:'), findsOneWidget);
    expect(find.text('PRODUCCION'), findsOneWidget);
    expect(find.text('CODIGO DGII:'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('MENSAJE DGII:'), findsOneWidget);
    expect(find.text('Comprobante aceptado por DGII'), findsOneWidget);
  });

  testWidgets('Preview E31 muestra empresa y RNC del cliente', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: UnifiedTicketPreviewWidget(
                settings: _defaultPrinterSettings(),
                company: _sampleCompany(),
                data: _sampleSaleData(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('DATOS FISCALES DEL CLIENTE:'), findsOneWidget);
    expect(find.text('Empresa: EMPRESA FISCAL DEMO SRL'), findsOneWidget);
    expect(find.text('RNC: 131246796'), findsOneWidget);
  });
}
