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
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final dateFmt = DateFormat('dd/MM/yyyy');

    String sanitize(String text) => _sanitizeTicketText(text);
    String fit(String text) => ReceiptText.fitText(sanitize(text), w);
    String line() => ReceiptText.line(width: w);

    String center(String text) {
      final cleaned = sanitize(text);
      if (cleaned.length >= w) return cleaned.substring(0, w);
      final left = ((w - cleaned.length) / 2).floor();
      final right = w - cleaned.length - left;
      return ' ' * left + cleaned + ' ' * right;
    }

    String twoCols(String left, String right) {
      final rightWidth = 14.clamp(6, w - 2);
      final leftWidth = (w - rightWidth - 1).clamp(0, w);
      final leftText = ReceiptText.padRight(sanitize(left), leftWidth);
      final rightText = ReceiptText.padLeft(sanitize(right), rightWidth);
      return ReceiptText.fitText('$leftText $rightText', w);
    }

    String money(double value) => 'RD\$ ${ReceiptText.money(value)}';

    DateTime? msToLocal(int? ms) =>
        ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms).toLocal();

    final openedAt = msToLocal(cashbox.openedAtMs);
    final closedAt = msToLocal(cashbox.closedAtMs);

    if (companyName.trim().isNotEmpty) {
      lines.add('<H2C>${sanitize(companyName.toUpperCase())}');
    }

    final headerParts = <String>[];
    if ((companyRnc ?? '').trim().isNotEmpty) {
      headerParts.add('RNC: ${companyRnc!.trim()}');
    }
    if ((companyPhone ?? '').trim().isNotEmpty) {
      headerParts.add('TEL: ${companyPhone!.trim()}');
    }
    if (headerParts.isNotEmpty) {
      lines.add(center(headerParts.join('  ')));
    }

    lines.add(line());
    lines.add('<H2C>CIERRE CAJA DEL DIA');
    lines.add(line());

    final parsedBizDate = DateTime.tryParse(businessDate)?.toLocal();
    final bizLabel = parsedBizDate == null
        ? businessDate
        : dateFmt.format(parsedBizDate);

    lines.add('<BL>${twoCols('Fecha', bizLabel)}');
    lines.add('<BL>${twoCols('Caja', '#${cashbox.id ?? ''}')}');
    if (openedAt != null) {
      lines.add('<BL>${twoCols('Apertura', fmt.format(openedAt))}');
    }
    if (closedAt != null) {
      lines.add('<BL>${twoCols('Cierre', fmt.format(closedAt))}');
    }
    lines.add(line());

    lines.add('<BL>${twoCols('Fondo inicial', money(openingAmount))}');
    lines.add('<BL>${twoCols('Tickets', totalTickets.toString())}');

    lines.add(line());
    lines.add('<H2C>VENTAS DEL DIA');
    lines.add(line());
    lines.add('<BL>${twoCols('Ventas efectivo', money(salesCashTotal))}');
    lines.add('<BL>${twoCols('Ventas tarjeta', money(salesCardTotal))}');
    lines.add(
      '<BL>${twoCols('Ventas transferencia', money(salesTransferTotal))}',
    );
    lines.add('<BL>${twoCols('Ventas credito', money(salesCreditTotal))}');
    if (refundsCash > 0) {
      lines.add('<BL>${twoCols('Devoluciones', money(refundsCash))}');
    }

    if (creditAbonos > 0) {
      lines.add('<BL>${twoCols('Abonos crédito', money(creditAbonos))}');
    }
    if (layawayAbonos > 0) {
      lines.add('<BL>${twoCols('Abonos apartado', money(layawayAbonos))}');
    }

    final manualNoAbonos = (cashInManual - creditAbonos - layawayAbonos).clamp(
      0.0,
      double.infinity,
    );
    lines.add('<BL>${twoCols('Entradas manuales', money(manualNoAbonos))}');
    lines.add('<BL>${twoCols('Retiros manuales', money(cashOutManual))}');

    lines.add(line());
    lines.add('<BL>${twoCols('Efectivo esperado', money(expectedCash))}');
    lines.add(line());

    if ((note ?? '').trim().isNotEmpty) {
      lines.add(fit('Nota:'));
      final wrapped = ReceiptText.wrapText(
        sanitize(note!.trim()),
        (w - 2).clamp(1, w),
      );
      for (final lineText in wrapped) {
        lines.add(fit('  $lineText'));
      }
      lines.add(line());
    }

    lines.add('<H2C>MOVIMIENTOS DEL DIA');
    lines.add(line());

    if (movements.isEmpty) {
      lines.add(center('Sin movimientos'));
    } else {
      final timeFmt = DateFormat('HH:mm');
      for (final m in movements) {
        final sign = m.isIn ? '+' : '-';
        final right = '$sign${money(m.amount)}';
        final left =
            '${timeFmt.format(m.createdAt)} (#${m.sessionId}) ${m.reason}';
        lines.add(twoCols(left, right));
      }
      lines.add(line());
      lines.add('<BL>${twoCols('Total entradas', money(cashInManual))}');
      lines.add('<BL>${twoCols('Total retiros', money(cashOutManual))}');
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
