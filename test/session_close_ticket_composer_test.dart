import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/printing/models/ticket_layout_config.dart';
import 'package:fullpos/features/cash/data/cash_movement_model.dart';
import 'package:fullpos/features/cash/data/cash_repository.dart';
import 'package:fullpos/features/cash/data/cash_session_model.dart';
import 'package:fullpos/features/cash/data/cash_summary_model.dart';
import 'package:fullpos/features/cash/data/session_close_ticket_composer.dart';

String _visibleLine(String line) {
  if (line.startsWith('<')) {
    final tagEnd = line.indexOf('>');
    if (tagEnd > 0) {
      return line.substring(tagEnd + 1);
    }
  }
  return line;
}

TicketLayoutConfig _layout(int width) {
  return TicketLayoutConfig(
    maxCharsPerLine: width,
    autoCut: false,
    showCompanyInfo: true,
    showClientInfo: true,
    showPaymentInfo: true,
    showFooterMessage: false,
    footerMessage: '',
    showElectronicInvoiceReference: true,
    showItbis: true,
    showCashier: true,
    showTotalsBreakdown: true,
    headerAlignment: 'center',
    detailsAlignment: 'left',
    totalsAlignment: 'right',
  );
}

void main() {
  test('Session close ticket stays compact and within width', () {
    final lines = SessionCloseTicketComposer.buildLines(
      layout: _layout(42),
      companyName: 'FULLPOS DEMO',
      companyRnc: '123456789',
      companyPhone: '809-555-0101',
      session: CashSessionModel(
        id: 18,
        userId: 7,
        userName: 'CAJA 1',
        openedAtMs: DateTime(2026, 4, 13, 8, 0).millisecondsSinceEpoch,
        openingAmount: 1500,
        businessDate: '2026-04-13',
        closedAtMs: DateTime(2026, 4, 13, 18, 30).millisecondsSinceEpoch,
        status: CashSessionStatus.closed,
      ),
      summary: CashSummaryModel(
        openingAmount: 1500,
        cashInManual: 500,
        cashOutManual: 200,
        creditAbonos: 50,
        layawayAbonos: 25,
        salesCashTotal: 4200,
        salesCardTotal: 1800,
        salesTransferTotal: 950,
        salesCreditTotal: 300,
        refundsCash: 125,
        expectedCash: 6875,
        totalTickets: 32,
        totalRefunds: 2,
      ),
      closingAmount: 6900,
      note: 'Cierre sin novedad y caja verificada.',
      movements: [
        CashMovementModel(
          sessionId: 18,
          type: CashMovementType.income,
          amount: 200,
          reason: 'Cambio inicial',
          createdAtMs: DateTime(2026, 4, 13, 8, 15).millisecondsSinceEpoch,
          userId: 7,
        ),
        CashMovementModel(
          sessionId: 18,
          type: CashMovementType.outcome,
          amount: 75,
          reason: 'Compra de funda',
          createdAtMs: DateTime(2026, 4, 13, 12, 40).millisecondsSinceEpoch,
          userId: 7,
        ),
      ],
      cashboxInitialAmount: 2500,
      categorySummary: [
        CategoryCashSummary(
          category: 'Ferreteria',
          salesTotal: 4200,
          cashSalesTotal: 2500,
          cardSalesTotal: 1200,
          transferSalesTotal: 500,
          creditSalesTotal: 0,
          refundTotal: 125,
          itemsSold: 8,
          itemsRefunded: 1,
        ),
      ],
      soldProducts: [
        SoldProductCashSummary(
          category: 'Ferreteria',
          productName: 'Taladro industrial 1/2',
          qty: 2,
          total: 3200,
        ),
        SoldProductCashSummary(
          category: 'Ferreteria',
          productName: 'Caja de tornillos',
          qty: 6,
          total: 1000,
        ),
      ],
      refundItems: [
        RefundItemByCategory(
          category: 'Ferreteria',
          productName: 'Caja de tornillos',
          qty: 1,
          total: 125,
        ),
      ],
    );

    for (final line in lines) {
      expect(_visibleLine(line).length, lessThanOrEqualTo(42));
    }

    expect(
      lines.where((line) => line.contains('Corte de turno')).isEmpty,
      isTrue,
    );
    expect(lines.any((line) => line.contains('CORTE DE TURNO')), isTrue);
    expect(lines.any((line) => line.contains('RESUMEN DE VENTAS')), isTrue);
    expect(lines.any((line) => line.contains('VENTAS POR CATEGORIA')), isTrue);
    expect(lines.any((line) => line.contains('CUADRE DE CAJA')), isTrue);
    expect(lines.any((line) => line.contains('PRODUCTOS VENDIDOS')), isTrue);
    expect(lines.any((line) => line.contains('PRODUCTOS DEVUELTOS')), isTrue);
    expect(lines.any((line) => line.contains('TOTALES DEL CIERRE')), isTrue);
    expect(lines.any((line) => line.contains('EFECTIVO ESPERADO')), isTrue);
    expect(lines.any((line) => line.contains('MOVIMIENTOS MANUALES')), isTrue);
    expect(lines.any((line) => line.contains('CAJERO: CAJA 1')), isTrue);
    expect(
      lines.any((line) => line.contains('Taladro industrial 1/2')),
      isTrue,
    );
    expect(lines.any((line) => line.contains('FIRMA CAJERO')), isFalse);
    expect(lines.any((line) => line.contains('6,875.00')), isTrue);
    expect(lines.any((line) => line.contains('6,900.00')), isTrue);
    expect(lines.any((line) => line.contains('VENTAS DE LA SESION')), isFalse);
    expect(lines.any((line) => line.contains('CIERRE POR CATEGORIA')), isFalse);
  });
}
