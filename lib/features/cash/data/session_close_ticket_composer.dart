import 'package:intl/intl.dart';

import '../../../core/printing/models/receipt_text_utils.dart';
import '../../../core/printing/models/ticket_layout_config.dart';
import '../../../core/utils/currency_display.dart';
import 'cash_repository.dart';
import 'cash_movement_model.dart';
import 'cash_session_model.dart';
import 'cash_summary_model.dart';

class SessionCloseTicketComposer {
  SessionCloseTicketComposer._();

  static List<String> buildLines({
    required TicketLayoutConfig layout,
    required String companyName,
    required String? companyRnc,
    required String? companyPhone,
    required CashSessionModel session,
    required CashSummaryModel summary,
    required double closingAmount,
    required String note,
    required List<CashMovementModel> movements,
    double? cashboxInitialAmount,
    List<CategoryCashSummary> categorySummary = const <CategoryCashSummary>[],
    List<SoldProductCashSummary> soldProducts =
        const <SoldProductCashSummary>[],
    List<RefundItemByCategory> refundItems = const <RefundItemByCategory>[],
  }) {
    final width = layout.maxCharsPerLine;
    final lines = <String>[];
    final dateTimeFormat = DateFormat('dd/MM/yyyy hh:mm a');
    final timeOnlyFormat = DateFormat('hh:mm a');
    final manualOnlyAmount =
        (summary.cashInManual - summary.creditAbonos - summary.layawayAbonos)
            .clamp(0.0, double.infinity);
    final difference = summary.calculateDifference(closingAmount);
    final sortedMovements = [...movements]
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));

    String sanitize(String text) => _sanitizeTicketText(text);
    String fit(String text) => ReceiptText.fitText(sanitize(text), width);
    String rule([String char = '-']) =>
        ReceiptText.line(char: char, width: width);
    String sectionRule() => rule('.');
    String strongRule() => rule('=');
    String money(double value) =>
        CurrencyDisplay.formatPlain(value, decimalDigits: 2);

    void addValueRow(String label, String value, {String prefix = ''}) {
      lines.add(
        '$prefix${ReceiptText.formatLine(sanitize(label), sanitize(value), width)}',
      );
    }

    void addStrongValueRow(String label, String value) {
      addValueRow(label, value, prefix: '<BR>');
    }

    void addWrappedBlock(String text, {String prefix = ''}) {
      for (final blockLine in ReceiptText.wrapText(sanitize(text), width)) {
        lines.add('$prefix${fit(blockLine)}');
      }
    }

    void addSectionTitle(String title, {String tag = 'H2C'}) {
      if (lines.isNotEmpty && lines.last.isNotEmpty) {
        lines.add('');
      }
      lines.add(sectionRule());
      lines.add('<$tag>${fit(title)}');
      lines.add(sectionRule());
    }

    void addMinorTitle(String title, {bool addSpacing = true}) {
      if (addSpacing && lines.isNotEmpty && lines.last.isNotEmpty) {
        lines.add('');
      }
      lines.add('<H2L>${fit(title)}');
    }

    String formatQty(double qty) {
      if ((qty - qty.roundToDouble()).abs() < 0.001) {
        return qty.round().toString();
      }
      return qty
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }

    void addLeftAmountLine(String label, double amount, {String prefix = ''}) {
      lines.add('$prefix${fit('${sanitize(label)}: ${money(amount)}')}');
    }

    void addInlineFacts(List<String> facts, {String prefix = ''}) {
      if (facts.isEmpty) return;
      addWrappedBlock(facts.join('  '), prefix: prefix);
    }

    String formatDuration(Duration duration) {
      final totalMinutes = duration.inMinutes;
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (hours <= 0) return '${minutes}m';
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }

    if (companyName.trim().isNotEmpty) {
      for (final nameLine in ReceiptText.wrapText(
        sanitize(companyName),
        width,
      )) {
        lines.add('<H2L>${fit(nameLine)}');
      }
    }
    if ((companyRnc ?? '').trim().isNotEmpty) {
      lines.add(fit('RNC: ${companyRnc!.trim()}'));
    }
    if ((companyPhone ?? '').trim().isNotEmpty) {
      lines.add(fit('TEL: ${companyPhone!.trim()}'));
    }

    if (lines.isNotEmpty) {
      lines.add('');
    }
    lines.add('<H2C>CORTE DE TURNO');
    lines.add('<H2L>${fit('CAJERO: ${session.userName}')}');
    lines.add(sectionRule());
    addValueRow('SESION', '#${session.id ?? ''}');
    addValueRow('APERTURA', dateTimeFormat.format(session.openedAt));
    if (session.closedAt != null) {
      addValueRow('CIERRE', dateTimeFormat.format(session.closedAt!));
      final duration = session.closedAt!.difference(session.openedAt);
      if (duration.inMinutes >= 1) {
        addValueRow('DURACION', formatDuration(duration));
      }
    }
    if ((session.businessDate ?? '').trim().isNotEmpty) {
      addValueRow('FECHA OPER.', session.businessDate!.trim());
    }

    addSectionTitle('RESUMEN DE VENTAS');
    addValueRow('TICKETS', summary.totalTickets.toString());
    if (summary.totalRefunds > 0) {
      addValueRow('DEVOLUCIONES', summary.totalRefunds.toString());
    }
    addStrongValueRow('TOTAL VENDIDO', money(summary.totalSold));
    addStrongValueRow('EFECTIVO', money(summary.salesCashTotal));
    addValueRow('TARJETA', money(summary.salesCardTotal));
    addValueRow('TRANSFERENCIA', money(summary.salesTransferTotal));
    addValueRow('CREDITO', money(summary.salesCreditTotal));
    if (summary.refundsCash > 0) {
      addValueRow('MONTO DEVUELTO', money(summary.refundsCash));
    }

    if (categorySummary.isNotEmpty) {
      addSectionTitle('VENTAS POR CATEGORIA');
      for (final entry in categorySummary) {
        addMinorTitle(entry.category.toUpperCase(), addSpacing: false);
        addLeftAmountLine('TOTAL', entry.salesTotal, prefix: '');
        addInlineFacts([
          'ITEMS: ${formatQty(entry.itemsSold)}',
          if (entry.cashSalesTotal > 0) 'EFE: ${money(entry.cashSalesTotal)}',
          if (entry.cardSalesTotal > 0) 'TAR: ${money(entry.cardSalesTotal)}',
          if (entry.transferSalesTotal > 0)
            'TRF: ${money(entry.transferSalesTotal)}',
          if (entry.creditSalesTotal > 0)
            'CRE: ${money(entry.creditSalesTotal)}',
        ]);
        if (entry.refundTotal > 0) {
          addInlineFacts([
            'DEV: ${money(entry.refundTotal)}',
            'NETO: ${money(entry.netTotal)}',
          ]);
        }
        lines.add(sectionRule());
        lines.add('');
      }
      while (lines.isNotEmpty && lines.last.isEmpty) {
        lines.removeLast();
      }
    }

    addSectionTitle('CUADRE DE CAJA');
    if (cashboxInitialAmount != null) {
      addValueRow('BASE CAJA DIARIA', money(cashboxInitialAmount));
    }
    addValueRow('BASE DE SESION', money(summary.openingAmount));
    addStrongValueRow('EFECTIVO VENTAS', money(summary.salesCashTotal));
    if (summary.refundsCash > 0) {
      addValueRow('DEVOLUCIONES EFECTIVO', money(summary.refundsCash));
    }
    if (manualOnlyAmount > 0) {
      addValueRow('ENTRADAS MANUALES', money(manualOnlyAmount));
    }
    if (summary.cashOutManual > 0) {
      addValueRow('SALIDAS DE CAJA', money(summary.cashOutManual));
    }
    if (summary.creditAbonos > 0) {
      addValueRow('ABONOS CREDITO', money(summary.creditAbonos));
    }
    if (summary.layawayAbonos > 0) {
      addValueRow('ABONOS APARTADO', money(summary.layawayAbonos));
    }

    if (soldProducts.isNotEmpty) {
      addSectionTitle('PRODUCTOS VENDIDOS');
      String? currentCategory;
      for (final product in soldProducts) {
        if (currentCategory != product.category) {
          if (currentCategory != null) {
            lines.add('');
          }
          currentCategory = product.category;
          addMinorTitle(currentCategory.toUpperCase(), addSpacing: false);
        }
        addWrappedBlock(product.productName, prefix: '');
        addInlineFacts([
          'CANT: ${formatQty(product.qty)}',
          'TOTAL: ${money(product.total)}',
        ]);
      }
    }

    if (refundItems.isNotEmpty) {
      addSectionTitle('PRODUCTOS DEVUELTOS');
      String? currentCategory;
      for (final item in refundItems) {
        if (currentCategory != item.category) {
          if (currentCategory != null) {
            lines.add('');
          }
          currentCategory = item.category;
          addMinorTitle(currentCategory.toUpperCase(), addSpacing: false);
        }
        addWrappedBlock(item.productName, prefix: '');
        addInlineFacts([
          'CANT: ${formatQty(item.qty)}',
          'TOTAL: ${money(item.total)}',
        ]);
      }
    }

    if (note.trim().isNotEmpty) {
      addSectionTitle('NOTA DE CIERRE');
      addWrappedBlock(note.trim());
    }

    if (sortedMovements.isNotEmpty) {
      addSectionTitle('MOVIMIENTOS MANUALES');
      final preview = sortedMovements.length > 5
          ? sortedMovements.sublist(sortedMovements.length - 5)
          : sortedMovements;
      for (final movement in preview) {
        final amount = '${movement.isIn ? '+' : '-'}${money(movement.amount)}';
        addValueRow(
          '${timeOnlyFormat.format(movement.createdAt)} ${movement.reason}',
          amount,
          prefix: '',
        );
      }
      if (sortedMovements.length > preview.length) {
        addValueRow(
          'MOVIMIENTOS ANTERIORES',
          '${sortedMovements.length - preview.length}',
          prefix: '',
        );
      }
    }

    if (lines.isNotEmpty && lines.last.isNotEmpty) {
      lines.add('');
    }
    lines.add(strongRule());
    lines.add('<H2C>${fit('TOTALES DEL CIERRE')}');
    lines.add(strongRule());
    lines.add('<BR>${fit('TOTAL VENDIDO: ${money(summary.totalSold)}')}');
    lines.add(fit('TOTAL TICKETS: ${summary.totalTickets}'));
    if (summary.totalRefunds > 0) {
      addLeftAmountLine('DEVOLUCIONES', summary.refundsCash, prefix: '');
    }
    if (manualOnlyAmount > 0) {
      addLeftAmountLine('ENTRADAS MANUALES', manualOnlyAmount, prefix: '');
    }
    if (summary.cashOutManual > 0) {
      addLeftAmountLine('SALIDAS DE CAJA', summary.cashOutManual, prefix: '');
    }
    lines.add(sectionRule());
    lines.add(
      '<BR>${fit('EFECTIVO ESPERADO: ${money(summary.expectedCash)}')}',
    );
    lines.add('<H1L>${fit('EFECTIVO CONTADO: ${money(closingAmount)}')}');
    lines.add('<H1L>${fit('DIFERENCIA: ${money(difference)}')}');
    lines.add(strongRule());

    if (layout.autoCut) {
      lines.add('');
      lines.add('');
      lines.add('');
    }

    return lines;
  }

  static String _sanitizeTicketText(String input) {
    final normalized = input
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

    return normalized
        .replaceAll(RegExp(r'''[^A-Za-z0-9\s\-_/.:,()#%+*&@'">$<]+'''), '')
        .trim();
  }
}
