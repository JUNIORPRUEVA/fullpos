import 'package:intl/intl.dart';
import 'ticket_layout_config.dart';
import 'ticket_data.dart';
import 'company_info.dart';
import 'receipt_text_utils.dart';

/// Renderer centralizado que genera líneas de ticket
/// FUENTE ÚNICA DE VERDAD para el layout del ticket
///
/// Utilizado por:
/// - Vista previa del ticket (widget)
/// - Impresión térmica (texto plano)
/// - Generación de PDF (convierte líneas a PDF)
class TicketRenderer {
  final TicketLayoutConfig config;
  final CompanyInfo company;

  TicketRenderer({required this.config, required this.company});

  String _fitLine(String text, int width) {
    if (width <= 0) return '';
    if (text.length > width) return text.substring(0, width);
    if (text.length < width) return text.padRight(width);
    return text;
  }

  /// Genera el ticket como una lista de líneas de texto
  /// Esta es la fuente única de verdad del layout.
  /// Todos los renderers (preview, PDF, thermal) usan este formato POS.
  List<String> buildLines(TicketData data) {
    final lines = <String>[];
    final width = config.maxCharsPerLine;
    final pendingAmount = data.pendingAmount < 0 ? 0.0 : data.pendingAmount;
    final computedSubtotal = data.items.fold<double>(
      0,
      (sum, item) => sum + item.total,
    );
    final subtotal = (data.subtotal <= 0 && computedSubtotal > 0)
        ? computedSubtotal
        : data.subtotal;
    final discount = data.discount;
    final itbis = data.itbis;
    final computedTotal = subtotal - discount + itbis;
    final total = (data.total <= 0 && computedTotal > 0)
        ? computedTotal
        : data.total;
    final paymentLabel = _paymentLabel(data.paymentMethod).toUpperCase();
    final documentType = _documentLabel(data);
    final dateLabel = DateFormat('dd/MM/yyyy').format(data.dateTime);
    final timeLabel = DateFormat('HH:mm').format(data.dateTime);

    void add(String text) => lines.add(_fitLine(text, width));
    void addCentered(String text) =>
        add(alignText(_sanitizeTicketText(text), width, 'center'));
    void addRule([String char = '-']) =>
        add(ReceiptText.line(char: char, width: width));
    void addPair(String left, String right) => add(
      ReceiptText.formatLine(
        _sanitizeTicketText(left),
        _sanitizeTicketText(right),
        width,
      ),
    );

    if (config.showCompanyInfo) {
      final companyName = _sanitizeTicketText(company.name).toUpperCase();
      if (companyName.isNotEmpty) addCentered(companyName);

      final rnc = (company.rnc ?? '').trim();
      if (rnc.isNotEmpty) addCentered('RNC: $rnc');

      final phone = (company.primaryPhone ?? '').trim();
      if (phone.isNotEmpty) addCentered('TEL: $phone');

      addRule();
    }

    addCentered(documentType);
    if (data.isCopy) addCentered('COPIA');
    if ((data.extraLegend ?? '').trim().isNotEmpty) {
      addCentered(data.extraLegend!.trim().toUpperCase());
    }
    addRule();

    addPair('FECHA: $dateLabel', timeLabel);
    if (config.showTicketCode) {
      addPair('DOC: ${_sanitizeTicketText(data.ticketNumber)}', '');
    }

    final clientName = (data.client?.name ?? '').trim();
    if (config.showClientInfo) {
      addPair('CLIENTE: ${clientName.isEmpty ? 'GENERAL' : clientName}', '');
    }

    if (config.showCashier) {
      final cashier = (data.cashierName ?? '').trim();
      addPair('CAJERO: ${cashier.isEmpty ? 'N/A' : cashier}', '');
    }

    if (config.showElectronicInvoiceReference &&
        (data.electronicInvoiceCode ?? '').trim().isNotEmpty) {
      addPair('E-CF: ${data.electronicInvoiceCode!.trim()}', '');
    }

    addRule();

    add(
      ReceiptText.formatProductRow(
        qty: 'CANT',
        name: 'DESCRIPCION',
        total: 'TOTAL',
        width: width,
      ),
    );
    addRule();

    for (final item in data.items) {
      add(
        ReceiptText.formatProductRow(
          qty: _formatQty(item.quantity),
          name: _sanitizeTicketText(item.name),
          total: ReceiptText.formatMoney(item.total),
          width: width,
        ),
      );
    }

    addRule();

    if (config.showTotalsBreakdown) {
      addPair('SUBTOTAL:', ReceiptText.formatMoney(subtotal));
      if (discount > 0) {
        addPair('DESCUENTO:', ReceiptText.formatMoney(discount));
      }
      if (config.showItbis && itbis > 0) {
        final taxRate = (data.itbisRate * 100).toStringAsFixed(0);
        addPair('ITBIS ($taxRate%):', ReceiptText.formatMoney(itbis));
      }
    }
    addPair('TOTAL:', ReceiptText.formatMoney(total));
    addRule();

    if (config.showPaymentInfo) {
      if (data.isLayaway) {
        addPair('APARTADO:', (data.statusLabel ?? 'PENDIENTE').toUpperCase());
        if (data.lastPaymentAmount > 0) {
          addPair('ABONO:', ReceiptText.formatMoney(data.lastPaymentAmount));
        }
        if (data.paidAmount > 0) {
          addPair('PAGADO:', ReceiptText.formatMoney(data.paidAmount));
        }
        addPair('PENDIENTE:', ReceiptText.formatMoney(pendingAmount));
      } else if (paymentLabel == 'CREDITO') {
        if (data.lastPaymentAmount > 0) {
          addPair('ABONO:', ReceiptText.formatMoney(data.lastPaymentAmount));
        }
        if (data.paidAmount > 0) {
          addPair('PAGADO:', ReceiptText.formatMoney(data.paidAmount));
        }
        addPair('PENDIENTE:', ReceiptText.formatMoney(pendingAmount));
      } else {
        final paidAmount = data.paidAmount <= 0 ? total : data.paidAmount;
        addPair('$paymentLabel:', ReceiptText.formatMoney(paidAmount));
        if (data.changeAmount > 0) {
          addPair('CAMBIO:', ReceiptText.formatMoney(data.changeAmount));
        }
      }
      addRule();
    }

    final footer =
        config.showFooterMessage && config.footerMessage.trim().isNotEmpty
        ? config.footerMessage.trim()
        : 'Gracias por su preferencia';
    addCentered(footer);

    final warranty = config.warrantyPolicy.trim();
    if (warranty.isNotEmpty) {
      addRule();
      addCentered('POLITICA DE GARANTIA');
      addRule();
      for (final rawLine in warranty.split('\n')) {
        final cleanLine = _sanitizeTicketText(rawLine).trim();
        if (cleanLine.isEmpty) continue;
        final wrappedLines = ReceiptText.wrapText(cleanLine, width - 2);
        if (wrappedLines.isEmpty) continue;
        add(_fitLine('- ${wrappedLines.first}', width));
        for (final wrapped in wrappedLines.skip(1)) {
          add(_fitLine('  $wrapped', width));
        }
      }
    }

    if (config.autoCut) {
      lines.add('');
      lines.add('');
      lines.add('');
    }

    return lines.map((line) => _fitLine(line, width)).toList(growable: false);
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Alinea texto genéricamente respetando maxCharsPerLine
  String alignText(String text, int width, String align) {
    if (text.length > width) {
      text = text.substring(0, width);
    }
    switch (align) {
      case 'right':
        return text.padLeft(width);
      case 'center':
        final left = ((width - text.length) / 2).floor();
        final right = width - text.length - left;
        return ' ' * left + text + ' ' * right;
      case 'left':
      default:
        return text.padRight(width);
    }
  }

  /// Crea una línea separadora del ancho especificado
  String sepLine(int width, [String char = '-']) {
    return List.filled(width, char).join('');
  }

  String _getDocumentType(TicketType type) {
    switch (type) {
      case TicketType.sale:
        return 'TICKET';
      case TicketType.quote:
        return 'COTIZACION';
      case TicketType.refund:
        return 'DEVOLUCION';
      case TicketType.credit:
        return 'NOTA DE CREDITO';
      case TicketType.copy:
        return 'COPIA';
    }
  }

  String _sanitizeTicketText(String input) {
    // Evita que aparezcan "cuadritos"/íconos por caracteres no soportados.
    // Normaliza a ASCII simple (sin tildes) y elimina caracteres raros.
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

    // Conservar solo caracteres comunes imprimibles.
    // Usar raw triple-quoted para permitir comillas simples y dobles sin escapes.
    final filtered = s.replaceAll(
      RegExp(r'''[^A-Za-z0-9\s\-_/.:,()#%+*&@'"'>$<]+'''),
      '',
    );
    return filtered.trim();
  }

  String _paymentLabel(String method) {
    final m = method.trim().toLowerCase();
    switch (m) {
      case 'cash':
      case 'efectivo':
        return 'EFECTIVO';
      case 'card':
      case 'tarjeta':
        return 'TARJETA';
      case 'transfer':
      case 'transferencia':
        return 'TRANSFERENCIA';
      case 'credit':
      case 'credito':
      case 'crédito':
        return 'CREDITO';
      case 'layaway':
      case 'apartado':
        return 'APARTADO';
      default:
        // No forzar mayúsculas en valores no reconocidos.
        return method.trim();
    }
  }

  String _documentLabel(TicketData data) {
    if (data.type == TicketType.sale) {
      final electronicCode = (data.electronicInvoiceCode ?? '').trim();
      final electronicType = (data.electronicDocumentType ?? '')
          .trim()
          .toLowerCase();
      final clientRnc = (data.client?.rnc ?? '').trim();

      if (electronicCode.isNotEmpty || electronicType == 'ecf') {
        return 'FACTURA ELECTRONICA';
      }

      if (electronicType.contains('credito') || clientRnc.isNotEmpty) {
        return 'FACTURA CREDITO FISCAL';
      }

      return 'FACTURA DE CONSUMO';
    }
    return _getDocumentType(data.type);
  }

  String _formatQty(double quantity) {
    final whole = quantity.truncateToDouble() == quantity;
    return whole ? quantity.toStringAsFixed(0) : quantity.toStringAsFixed(2);
  }
}
