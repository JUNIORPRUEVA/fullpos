import 'package:intl/intl.dart';

import '../../../core/printing/models/company_info.dart';
import '../../../core/printing/models/receipt_text_utils.dart';
import '../../../core/printing/models/ticket_layout_config.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../settings/data/printer_settings_repository.dart';
import 'cash_movement_model.dart';
import 'cash_repository.dart';
import 'cashbox_daily_model.dart';
import 'operation_flow_service.dart';

class DailyCashCloseTicketPrinter {
  DailyCashCloseTicketPrinter._();

  static Future<PrintTicketResult> printDailyCloseTicket({
    required int cashboxDailyId,
    required String businessDate,
    String? note,
  }) async {
    final cashbox = await OperationFlowService.getDailyCashbox(businessDate);
    if (cashbox == null || cashbox.id == null) {
      return PrintTicketResult(
        success: false,
        message: 'No hay caja diaria para $businessDate',
        ticketNumber: 'DAILY-$businessDate',
      );
    }

    final summary = await CashRepository.buildDailySummary(
      cashboxDailyId: cashboxDailyId,
      businessDate: businessDate,
    );

    final movements = await CashRepository.listMovementsForDailyCashbox(
      cashboxDailyId: cashboxDailyId,
      businessDate: businessDate,
    );

    final settings = await PrinterSettingsRepository.getOrCreate();
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);
    final company = await CompanyInfoRepository.getCurrentCompanyInfo();

    final lines = _buildDailyCloseLines(
      layout: layout,
      companyName: company.name,
      companyRnc: company.rnc,
      companyPhone: company.primaryPhone,
      cashbox: cashbox,
      businessDate: businessDate,
      openingAmount: cashbox.initialAmount,
      expectedCash: summary.expectedCash,
      salesCashTotal: summary.salesCashTotal,
      salesCardTotal: summary.salesCardTotal,
      salesTransferTotal: summary.salesTransferTotal,
      salesCreditTotal: summary.salesCreditTotal,
      refundsCash: summary.refundsCash,
      cashInManual: summary.cashInManual,
      cashOutManual: summary.cashOutManual,
      creditAbonos: summary.creditAbonos,
      layawayAbonos: summary.layawayAbonos,
      totalTickets: summary.totalTickets,
      movements: movements,
      note: note,
    );

    return UnifiedTicketPrinter.printCustomLines(
      lines: lines,
      ticketNumber: 'DAILY-${cashbox.id}-$businessDate',
      includeLogo: true,
      overrideCopies: settings.copies,
      layoutOverride: layout,
    );
  }

  static List<String> _buildDailyCloseLines({
    required TicketLayoutConfig layout,
    required String companyName,
    required String? companyRnc,
    required String? companyPhone,
    required CashboxDailyModel cashbox,
    required String businessDate,
    required double openingAmount,
    required double expectedCash,
    required double salesCashTotal,
    required double salesCardTotal,
    required double salesTransferTotal,
    required double salesCreditTotal,
    required double refundsCash,
    required double cashInManual,
    required double cashOutManual,
    required double creditAbonos,
    required double layawayAbonos,
    required int totalTickets,
    required List<CashMovementModel> movements,
    required String? note,
  }) {
    final w = layout.maxCharsPerLine;
    final lines = <String>[];
    final fmt = DateFormat('dd/MM/yyyy hh:mm a');
    final dateFmt = DateFormat('dd/MM/yyyy');
    final totalSales =
        salesCashTotal +
        salesCardTotal +
        salesTransferTotal +
        salesCreditTotal;
    final totalExpenses = refundsCash + cashOutManual;
    final finalCash = cashbox.currentAmount;
    final difference = finalCash - expectedCash;

    String sanitize(String text) => _sanitizeTicketText(text);
    String fit(String text) => ReceiptText.fitText(text, w);
    String line() => ReceiptText.line(width: w);

    String center(String text) {
      final cleaned = sanitize(text).toUpperCase();
      return ReceiptText.alignColumns(
        values: [cleaned],
        widths: [w],
        aligns: const [TextAlignMode.center],
      );
    }

    String pair(String left, String right) {
      return ReceiptText.formatLine(sanitize(left), sanitize(right), w);
    }

    void addPair(String left, String right) => lines.add(pair(left, right));

    String money(double value) => ReceiptText.formatMoney(value);

    DateTime? msToLocal(int? ms) =>
        ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms).toLocal();

    final openedAt = msToLocal(cashbox.openedAtMs);
    final closedAt = msToLocal(cashbox.closedAtMs);

    if (companyName.trim().isNotEmpty) {
      lines.add(center(companyName));
    }

    if ((companyRnc ?? '').trim().isNotEmpty) {
      lines.add(center('RNC: ${companyRnc!.trim()}'));
    }
    if ((companyPhone ?? '').trim().isNotEmpty) {
      lines.add(center('TEL: ${companyPhone!.trim()}'));
    }

    lines.add(line());
    lines.add('<H2C>CORTE DE TURNO');
    lines.add(line());

    final parsedBizDate = DateTime.tryParse(businessDate)?.toLocal();
    final bizLabel = parsedBizDate == null
        ? businessDate
        : dateFmt.format(parsedBizDate);

    addPair('CAJA:', '#${cashbox.id ?? ''}');
    addPair('CAJERO:', 'USER #${cashbox.openedByUserId}');
    addPair('FECHA:', bizLabel);
    if (openedAt != null) {
      addPair('APERTURA:', fmt.format(openedAt));
    }
    if (closedAt != null) {
      addPair('CIERRE:', fmt.format(closedAt));
    }
    lines.add(line());

    addPair('FONDO INICIAL:', money(openingAmount));
    addPair('VENTAS:', money(totalSales));
    addPair('GASTOS:', money(totalExpenses));
    addPair('EFECTIVO FINAL:', money(finalCash));
    addPair('DIFERENCIA:', money(difference));
    addPair('TICKETS:', totalTickets.toString());
    lines.add(line());

    if (salesCardTotal > 0) addPair('TARJETA:', money(salesCardTotal));
    if (salesTransferTotal > 0) addPair('TRANSFERENCIA:', money(salesTransferTotal));
    if (salesCreditTotal > 0) addPair('CREDITO:', money(salesCreditTotal));
    if (creditAbonos > 0) addPair('ABONOS CREDITO:', money(creditAbonos));
    if (layawayAbonos > 0) addPair('ABONOS APARTADO:', money(layawayAbonos));
    if (cashInManual > 0) addPair('ENTRADAS:', money(cashInManual));
    if (cashOutManual > 0) addPair('SALIDAS:', money(cashOutManual));

    if ((note ?? '').trim().isNotEmpty) {
      lines.add(line());
      lines.add(fit('NOTA:'));
      for (final lineText in ReceiptText.wrapText(sanitize(note!.trim()), w)) {
        lines.add(fit(lineText));
      }
    }

    if (movements.isNotEmpty) {
      lines.add(line());
      lines.add('<H2C>MOVIMIENTOS');
      lines.add(line());
      final timeFmt = DateFormat('hh:mm a');
      for (final movement in movements.take(8)) {
        final label = '${timeFmt.format(movement.createdAt)} ${movement.reason}';
        final amount = '${movement.isIn ? '+' : '-'}${money(movement.amount)}';
        addPair(label, amount);
      }
      if (movements.length > 8) {
        addPair('MOVIMIENTOS ADICIONALES:', '${movements.length - 8}');
      }
    }

    if (layout.autoCut) {
      lines.add('');
      lines.add('');
      lines.add('');
    }

    return lines;
  }

  static String _sanitizeTicketText(String input) {
    final s = input
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('ñ', 'n')
        .replaceAll('Ñ', 'N')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'U')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'C');

    final filtered = s.replaceAll(
      RegExp(r'''[^A-Za-z0-9\s\-_/.:,()#%+*&@'"'>$<]+'''),
      '',
    );
    return filtered.trim();
  }
}
