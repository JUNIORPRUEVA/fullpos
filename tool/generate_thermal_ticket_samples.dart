import 'dart:io';

import 'package:fullpos/core/printing/models/company_info.dart';
import 'package:fullpos/core/printing/models/ticket_builder.dart';
import 'package:fullpos/core/printing/models/ticket_data.dart';
import 'package:fullpos/core/printing/models/ticket_layout_config.dart';
import 'package:fullpos/features/cash/data/cash_movement_model.dart';
import 'package:fullpos/features/cash/data/cash_session_model.dart';
import 'package:fullpos/features/cash/data/cash_summary_model.dart';
import 'package:fullpos/features/cash/data/session_close_ticket_composer.dart';
import 'package:fullpos/features/settings/data/printer_settings_model.dart';

Future<void> main() async {
  final outDir = Directory('artifacts/printing');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final company = const CompanyInfo(
    name: 'FULLTECH SRL',
    slogan: 'SISTEMAS Y TECNOLOGIA',
    rnc: '000-00000-0',
    phone: '829-534-4286',
    address: 'Higuey, La Altagracia',
  );

  for (final width in [58, 80]) {
    final settings = PrinterSettingsModel.defaults().copyWith(
      paperWidthMm: width,
      charsPerLine: width == 58 ? 32 : 48,
      footerMessage: 'Gracias por su compra. Conserve este comprobante.',
      warrantyPolicy: 'Garantía según condiciones de la empresa.',
      showLogo: 0,
    );
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);
    final builder = TicketBuilder(layout: layout, company: company);

    final salePdf = builder.buildPdf(_sampleSale());
    File(
      '${outDir.path}/ticket_factura_${width}mm.pdf',
    ).writeAsBytesSync(await salePdf.save());

    final closeLines = SessionCloseTicketComposer.buildLines(
      layout: layout,
      companyName: company.name,
      companyRnc: company.rnc,
      companyPhone: company.primaryPhone,
      session: _sampleSession(),
      summary: _sampleSummary(),
      closingAmount: 34500,
      note: 'Cierre de prueba con diferencia negativa.',
      movements: _sampleMovements(),
      cashboxInitialAmount: 5000,
    );
    final closePdf = builder.buildPdfFromLines(closeLines, includeLogo: false);
    File(
      '${outDir.path}/ticket_cierre_${width}mm.pdf',
    ).writeAsBytesSync(await closePdf.save());

    final stylePdf = builder.buildStyleDiagnosticsPdf();
    File(
      '${outDir.path}/ticket_estilos_${width}mm.pdf',
    ).writeAsBytesSync(await stylePdf.save());
  }

  stdout.writeln('PDF samples written to ${outDir.path}');
}

TicketData _sampleSale() {
  final now = DateTime(2026, 7, 17, 10, 30);
  return TicketData(
    ticketNumber: 'F00000125',
    dateTime: now,
    cashierName: 'Junior López',
    client: const ClientInfo(
      name: 'Consumidor Final',
      phone: '829-000-0000',
      rnc: '001-0000000-0',
    ),
    items: const [
      TicketItemData(
        name: 'Cámara Hikvision 2MP con nombre largo de prueba',
        quantity: 2,
        unitPrice: 2500,
        total: 5000,
      ),
      TicketItemData(
        name: 'Instalación y configuración técnica',
        quantity: 1,
        unitPrice: 1500,
        total: 1500,
      ),
    ],
    subtotal: 6500,
    discount: 250,
    itbis: 1125,
    itbisRate: 0.18,
    total: 7375,
    paymentMethod: 'Efectivo',
    paidAmount: 8000,
    changeAmount: 625,
    fiscalReceiptNumber: 'B0200000125',
    fiscalReceiptName: 'CONSUMO',
    fiscalReceiptCode: 'B02',
    fiscalReceiptExpirationDate: DateTime(2026, 12, 31),
    type: TicketType.sale,
  );
}

CashSessionModel _sampleSession() {
  final open = DateTime(2026, 7, 17, 9).millisecondsSinceEpoch;
  final close = DateTime(2026, 7, 17, 18).millisecondsSinceEpoch;
  return CashSessionModel(
    id: 125,
    userId: 1,
    userName: 'Junior López',
    openedAtMs: open,
    closedAtMs: close,
    openingAmount: 5000,
    closingAmount: 34500,
    expectedCash: 35000,
    difference: -500,
    businessDate: '2026-07-17',
    status: CashSessionStatus.closed,
  );
}

CashSummaryModel _sampleSummary() {
  return CashSummaryModel(
    openingAmount: 5000,
    totalSales: 48500,
    totalExpenses: 0,
    totalWithdrawals: 0,
    cashInManual: 0,
    cashOutManual: 500,
    creditAbonos: 0,
    layawayAbonos: 0,
    salesCashTotal: 30000,
    salesCardTotal: 10000,
    salesTransferTotal: 8500,
    salesCreditTotal: 0,
    refundsCash: 500,
    expectedCash: 35000,
    totalTickets: 35,
    totalRefunds: 1,
  );
}

List<CashMovementModel> _sampleMovements() {
  final now = DateTime(2026, 7, 17, 15).millisecondsSinceEpoch;
  return [
    CashMovementModel(
      sessionId: 125,
      type: CashMovementType.outcome,
      amount: 500,
      reason: 'Compra menor',
      createdAtMs: now,
      userId: 1,
    ),
  ];
}
