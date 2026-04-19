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
    final companyAddress = (company.address ?? '').trim();
    final ticketNumber = _sanitizeTicketText(data.ticketNumber).toUpperCase();
    final clientName = (data.client?.name ?? '').trim();
    final clientRnc = (data.client?.rnc ?? '').trim();
    final clientPhone = (data.client?.phone ?? '').trim();
    final clientDisplay = clientName.isEmpty
        ? 'GENERAL'
        : _sanitizeTicketText(clientName).toUpperCase();
    final cashierName = (data.cashierName ?? '').trim();
    final cashierDisplay = cashierName.isEmpty
        ? 'N/A'
        : _sanitizeTicketText(cashierName).toUpperCase();
    final ecfCode = _sanitizeTicketText(
      (data.electronicInvoiceCode ?? '').trim(),
    ).toUpperCase();
    final electronicTypeCode = _sanitizeTicketText(
      (data.electronicDocumentType ?? '').trim(),
    ).toUpperCase();
    final electronicTrackId = _sanitizeTicketText(
      (data.electronicTrackId ?? '').trim(),
    ).toUpperCase();
    final electronicStatus = _electronicStatusLabel(data);
    final electronicEnvironment = _electronicEnvironmentLabel(data);
    final electronicDgiiCode = _sanitizeTicketText(
      (data.electronicDgiiCode ?? '').trim(),
    ).toUpperCase();
    final electronicDgiiMessage = _sanitizeTicketText(
      (data.electronicDgiiMessage ?? '').trim(),
    ).toUpperCase();

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

      if (companyAddress.isNotEmpty) {
        final wrappedAddress = ReceiptText.wrapText(
          _sanitizeTicketText(companyAddress).toUpperCase(),
          width,
        );
        for (final addressLine in wrappedAddress) {
          addCentered(addressLine);
        }
      }

      addRule();
    }

    addCentered(documentType);
    if (data.isCopy) addCentered('COPIA');
    if ((data.extraLegend ?? '').trim().isNotEmpty) {
      addCentered(data.extraLegend!.trim().toUpperCase());
    }
    addRule();

    if (config.showDateTime) {
      addPair('FECHA: $dateLabel', 'HORA: $timeLabel');
    }
    if (config.showTicketCode || config.showCashier) {
      addPair(
        config.showTicketCode ? 'DOC: $ticketNumber' : '',
        config.showCashier ? 'CAJA: $cashierDisplay' : '',
      );
    }
    if (config.showClientInfo) {
      if (_requiresFiscalClientBlock(data)) {
        add('CLIENTE FISCAL');
        addPair('EMPRESA:', clientDisplay);
        addPair(
          'RNC:',
          clientRnc.isEmpty
              ? 'PENDIENTE'
              : _sanitizeTicketText(clientRnc).toUpperCase(),
        );
        if (clientPhone.isNotEmpty) {
          addPair('TEL:', _sanitizeTicketText(clientPhone).toUpperCase());
        }
      } else {
        addPair('CLI: $clientDisplay', '');
      }
    }

    final hasElectronicBlock =
        ecfCode.isNotEmpty ||
        electronicTypeCode.isNotEmpty ||
        electronicStatus.isNotEmpty ||
        electronicTrackId.isNotEmpty ||
        electronicEnvironment.isNotEmpty ||
        electronicDgiiCode.isNotEmpty ||
        electronicDgiiMessage.isNotEmpty;
    if (hasElectronicBlock) {
      addPair('DOC. FE:', _electronicDocumentLabel(data));
      if (ecfCode.isNotEmpty) {
        addPair('E-CF:', ecfCode);
      }
      if (electronicStatus.isNotEmpty) {
        addPair('ESTADO DGII:', electronicStatus);
      }
      if (electronicTrackId.isNotEmpty) {
        addPair('TRACK ID:', electronicTrackId);
      }
      if (electronicEnvironment.isNotEmpty) {
        addPair('AMBIENTE:', electronicEnvironment);
      }
      if (electronicDgiiCode.isNotEmpty) {
        addPair('CODIGO DGII:', electronicDgiiCode);
      }
      if (electronicDgiiMessage.isNotEmpty) {
        add('MENSAJE DGII:');
        for (final line in ReceiptText.wrapText(
          electronicDgiiMessage,
          width - 2,
        )) {
          add(_fitLine(' $line', width));
        }
      }
    }

    addRule();

    add(
      ReceiptText.formatProductRow(
        qty: width >= 48 ? 'CANT.' : 'CANT',
        name: 'PRODUCTO',
        total: 'TOTAL',
        width: width,
      ),
    );
    addRule();

    for (final item in data.items) {
      add(
        ReceiptText.formatProductRow(
          qty: _formatQty(item.quantity),
          name: _sanitizeTicketText(item.name).toUpperCase(),
          total: ReceiptText.formatMoney(item.total),
          width: width,
        ),
      );
    }

    addRule();

    String compactMoney(num value) {
      return ReceiptText.money(value).replaceAll(RegExp(r'\.00$'), '');
    }

    if (config.showTotalsBreakdown) {
      addPair('SUBT.:', compactMoney(subtotal));
      if (discount > 0) {
        addPair('DESC.:', compactMoney(discount));
      }
      if (config.showItbis && itbis > 0) {
        final taxRate = (data.itbisRate * 100).toStringAsFixed(0);
        addPair('ITBIS $taxRate%:', compactMoney(itbis));
      }
    }
    addRule();
    addPair('TOTAL:', ReceiptText.formatMoney(total));
    addRule();

    if (config.showPaymentInfo) {
      if (data.isLayaway) {
        addPair('TIPO PAGO:', 'APARTADO');
        addPair('ESTADO:', (data.statusLabel ?? 'PENDIENTE').toUpperCase());
        if (data.lastPaymentAmount > 0) {
          addPair('ABONO:', ReceiptText.formatMoney(data.lastPaymentAmount));
        }
        if (data.paidAmount > 0) {
          addPair('PAGADO:', ReceiptText.formatMoney(data.paidAmount));
        }
        addPair('PEND.:', ReceiptText.formatMoney(pendingAmount));
      } else if (paymentLabel == 'CREDITO') {
        addPair('TIPO PAGO:', paymentLabel);
        if (data.lastPaymentAmount > 0) {
          addPair('ABONO:', ReceiptText.formatMoney(data.lastPaymentAmount));
        }
        if (data.paidAmount > 0) {
          addPair('PAGADO:', ReceiptText.formatMoney(data.paidAmount));
        }
        addPair('PEND.:', ReceiptText.formatMoney(pendingAmount));
      } else {
        final paidAmount = data.paidAmount <= 0 ? total : data.paidAmount;
        addPair('TIPO PAGO:', paymentLabel);
        addPair('RECIBIDO:', ReceiptText.formatMoney(paidAmount));
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
    add('');
    addCentered(footer.toUpperCase());

    final warranty = config.warrantyPolicy.trim();
    if (warranty.isNotEmpty) {
      addRule();
      add('POLITICA GARANTIA');
      addRule();
      final warrantyParagraph = warranty
          .split('\n')
          .map((rawLine) => _sanitizeTicketText(rawLine).trim())
          .where((line) => line.isNotEmpty)
          .join('. ');
      for (final wrapped in ReceiptText.wrapText(
        warrantyParagraph,
        width - 2,
      )) {
        add(_fitLine(wrapped.toUpperCase(), width));
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
    final normalized = input.replaceAll(RegExp(r'\s+'), ' ');
    final filtered = normalized.replaceAll(
      RegExp(r'''[^A-Za-z0-9À-ÿ\s\-_/.:,()#%+*&@'"'>$<]+'''),
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

  bool _requiresFiscalClientBlock(TicketData data) {
    return (data.electronicDocumentType ?? '').trim() == '31';
  }

  String _formatQty(double quantity) {
    final whole = quantity.truncateToDouble() == quantity;
    return whole ? quantity.toStringAsFixed(0) : quantity.toStringAsFixed(2);
  }

  String _electronicDocumentLabel(TicketData data) {
    switch ((data.electronicDocumentType ?? '').trim()) {
      case '31':
        return '31 CREDITO FISCAL';
      case '32':
        return '32 CONSUMO';
      case '33':
        return '33 DEBITO';
      case '34':
        return '34 NOTA CREDITO';
      case '41':
        return '41 COMPRAS';
      case '43':
        return '43 GASTOS MENORES';
      case '44':
        return '44 REGIMEN ESPECIAL';
      case '45':
        return '45 GUBERNAMENTAL';
      default:
        final raw = (data.electronicDocumentType ?? '').trim();
        return raw.isEmpty ? 'DOCUMENTO ELECTRONICO' : raw.toUpperCase();
    }
  }

  String _electronicStatusLabel(TicketData data) {
    switch ((data.electronicDgiiStatus ?? '').trim().toLowerCase()) {
      case 'aceptada':
        return 'ACEPTADA';
      case 'rechazada':
        return 'RECHAZADA';
      case 'pendiente_dgii':
        return 'PENDIENTE DGII';
      case 'pendiente_configuracion':
        return 'PENDIENTE CONFIG';
      case 'local':
        return 'LOCAL';
      case 'draft':
        return 'BORRADOR';
      case 'not_sent':
        return 'NO ENVIADA';
      default:
        return _sanitizeTicketText(
          (data.electronicDgiiStatus ?? '').trim(),
        ).toUpperCase();
    }
  }

  String _electronicEnvironmentLabel(TicketData data) {
    switch ((data.electronicEnvironment ?? '').trim().toLowerCase()) {
      case 'production':
      case 'produccion':
        return 'PRODUCCION';
      case 'precertification':
      case 'pruebas':
      case 'certificacion':
        return 'CERTIFICACION';
      default:
        return _sanitizeTicketText(
          (data.electronicEnvironment ?? '').trim(),
        ).toUpperCase();
    }
  }
}
