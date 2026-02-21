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

  String _twoColsStrict(String left, String right, int width) {
    if (width <= 0) return '';

    final safeLeft = _sanitizeTicketText(left);
    final safeRight = _sanitizeTicketText(right);

    // Reservar un ancho mínimo para la columna derecha (hora), manteniendo 1 espacio.
    final minRight = 7; // ej: "04:05PM" (sin espacio) o "04:05 P"
    final rightWidth =
        (safeRight.length < minRight ? minRight : safeRight.length).clamp(
          1,
          width - 1,
        );
    final leftWidth = (width - 1 - rightWidth).clamp(0, width);

    final leftFit = _fitLine(safeLeft, leftWidth);
    final rightTrunc = safeRight.length > rightWidth
        ? safeRight.substring(safeRight.length - rightWidth)
        : safeRight;
    final rightFit = rightTrunc.padLeft(rightWidth);
    return _fitLine('$leftFit $rightFit', width);
  }

  List<String> _wrapTextHard(String text, int width) {
    if (width <= 0) return const [''];
    final cleaned = _sanitizeTicketText(
      text,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return const [''];

    final words = cleaned.split(' ');
    final out = <String>[];
    var current = '';

    for (final word in words) {
      if (word.length > width) {
        // Si hay una línea en construcción, cerrarla antes de partir la palabra.
        if (current.isNotEmpty) {
          out.add(current);
          current = '';
        }
        for (var i = 0; i < word.length; i += width) {
          final end = (i + width) > word.length ? word.length : (i + width);
          out.add(word.substring(i, end));
        }
        continue;
      }

      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= width) {
        current = '$current $word';
      } else {
        out.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) out.add(current);
    return out;
  }

  /// Genera el ticket como una lista de líneas de texto
  /// Estructura elegante y profesional según especificaciones
  /// Esta es la fuente única de verdad del layout.
  /// Todos los renderers (preview, PDF, thermal) usan esto.
  List<String> buildLines(TicketData data) {
    // Estilo "Factura clásica" como el ejemplo solicitado.
    // Solo aplica a facturas (ventas). Otros documentos conservan el estilo actual.
    if (data.type == TicketType.sale) {
      final lines = _buildClassicInvoiceLines(data);
      final w = config.maxCharsPerLine;
      return lines.map((l) => _fitLine(l, w)).toList(growable: false);
    }

    final lines = <String>[];
    final w = config.maxCharsPerLine;
    final bool isLayaway = data.isLayaway;
    final double pendingAmount = data.pendingAmount < 0
        ? 0
        : data.pendingAmount;
    final String layawayStatus =
        (data.statusLabel ?? (pendingAmount > 0 ? 'PENDIENTE' : 'PAGADO'));

    // ============================================================
    // 1. ENCABEZADO: EMPRESA (centrado)
    // ============================================================
    if (config.showCompanyInfo) {
      lines.add(
        alignText(
          _sanitizeTicketText(company.name).toUpperCase(),
          w,
          config.headerAlignment,
        ),
      );

      // RNC y Teléfono en la misma línea
      final rnc = company.rnc ?? '';
      final phone = company.primaryPhone ?? '';
      if (rnc.isNotEmpty || phone.isNotEmpty) {
        final rncPart = rnc.isNotEmpty ? 'RNC: $rnc' : '';
        final phonePart = phone.isNotEmpty ? 'Tel: $phone' : '';
        final separator = (rncPart.isNotEmpty && phonePart.isNotEmpty)
            ? ' | '
            : '';
        lines.add(
          alignText(
            _sanitizeTicketText('$rncPart$separator$phonePart'),
            w,
            config.headerAlignment,
          ),
        );
      }

      if (company.address != null && company.address!.isNotEmpty) {
        final addressLines = company.address!.split('\n');
        for (final line in addressLines) {
          lines.add(
            alignText(_sanitizeTicketText(line), w, config.headerAlignment),
          );
        }
      }
      lines.add(sepLine(w));
      _addSectionSpace(lines, 1);
    }

    // ============================================================
    // 2. BANDA DECORATIVA: FACTURA/TIPO DE DOCUMENTO
    // ============================================================
    final docType = _getDocumentType(data.type);
    lines.add(
      alignText(_sanitizeTicketText(docType), w, config.headerAlignment),
    );
    lines.add(sepLine(w));
    _addSectionSpace(lines, 1);

    // ============================================================
    // 3. FILA CAJERO + FECHA/TICKET (dos columnas)
    // ============================================================
    if (config.showCashier && data.cashierName != null) {
      final cajeroLabel = _sanitizeTicketText(
        'CAJERO: ${(data.cashierName ?? '')}',
      );
      final dateStr = 'FECHA: ${_formatDate(data.dateTime)}';
      final ticketStr = 'TICKET: ${data.ticketNumber}';

      // Línea 1: Cajero a la izquierda, Fecha a la derecha
      final spaces1 = w - cajeroLabel.length - dateStr.length;
      final padding1 = spaces1 > 0 ? ' ' * spaces1 : ' ';
      lines.add(cajeroLabel + padding1 + dateStr);

      // Línea 2: Ticket a la derecha
      lines.add(alignText(ticketStr, w, 'right'));
    } else {
      // Si no hay cajero, solo mostrar Fecha y Ticket centrados
      final dateStr = 'FECHA: ${_formatDate(data.dateTime)}';
      lines.add(alignText(dateStr, w, config.headerAlignment));
      lines.add(
        alignText('TICKET: ${data.ticketNumber}', w, config.headerAlignment),
      );
    }

    if (data.isCopy) {
      lines.add(alignText('*** COPIA ***', w, 'center'));
    }
    if (data.extraLegend != null) {
      lines.add(alignText(_sanitizeTicketText(data.extraLegend!), w, 'center'));
    }

    // NCF si existe
    if (config.showNcf && data.ncf != null && data.ncf!.isNotEmpty) {
      lines.add(
        alignText(
          _sanitizeTicketText('NCF: ${data.ncf}'),
          w,
          config.detailsAlignment,
        ),
      );
    }

    lines.add(sepLine(w));
    _addSectionSpace(lines, 1);

    // ============================================================
    // 4. DATOS DEL CLIENTE (limpio, izquierda)
    // ============================================================
    if (config.showClientInfo && data.client != null) {
      lines.add(alignText('DATOS DEL CLIENTE:', w, config.detailsAlignment));
      lines.add(
        alignText(
          _sanitizeTicketText('NOMBRE: ${data.client!.name}'),
          w,
          config.detailsAlignment,
        ),
      );
      if (data.client!.rnc != null && data.client!.rnc!.isNotEmpty) {
        lines.add(
          alignText(
            _sanitizeTicketText('RNC/CEDULA: ${data.client!.rnc!}'),
            w,
            config.detailsAlignment,
          ),
        );
      }
      if (data.client!.phone != null && data.client!.phone!.isNotEmpty) {
        lines.add(
          alignText(
            _sanitizeTicketText('TELEFONO: ${data.client!.phone}'),
            w,
            config.detailsAlignment,
          ),
        );
      }
      lines.add(sepLine(w));
      _addSectionSpace(lines, 1);
    }

    // ============================================================
    // 5. DETALLE DE VENTAS: CANT | PRODUCTO | PRECIO (solo 3 columnas)
    // ============================================================
    // Dimensiones de columnas optimizadas para lectura
    final int cantWidth = 5; // CANT.
    final int priceWidth = 11; // PRECIO (alineado derecha)
    final int productWidth =
        w - cantWidth - priceWidth - 3; // Resto para PRODUCTO

    // Encabezado de tabla ENCERRADO
    lines.add(sepLine(w, '='));
    final cantHeader = alignText('CANT', cantWidth, 'left');
    final prodHeader = alignText('PRODUCTO', productWidth, 'left');
    final priceHeader = alignText('PRECIO', priceWidth, 'right');
    lines.add('$cantHeader $prodHeader $priceHeader');
    lines.add(sepLine(w, '='));

    // Filas de productos
    for (final item in data.items) {
      final cant = alignText(
        item.quantity.toStringAsFixed(0),
        cantWidth,
        'right',
      );
      final prod = alignText(
        _sanitizeTicketText(item.name).toUpperCase(),
        productWidth,
        'left',
      );
      final price = alignText(
        'RD\$ ${_formatNumber(item.unitPrice)}',
        priceWidth,
        'right',
      );
      lines.add('$cant $prod $price');
    }

    lines.add(sepLine(w));
    _addSectionSpace(lines, 1);

    // ============================================================
    // 6. TOTALES (alineados a la derecha)
    // ============================================================
    if (config.showTotalsBreakdown) {
      lines.add(
        _totalsBlockLine(
          label: 'SUB-TOTAL',
          value: 'RD\$ ${_formatNumber(data.subtotal)}',
          width: w,
        ),
      );

      if (data.discount > 0) {
        lines.add(
          _totalsBlockLine(
            label: 'DESCUENTO',
            value: 'RD\$ ${_formatNumber(data.discount)}',
            width: w,
          ),
        );
      }

      if (config.showItbis && data.itbis > 0) {
        final itbisPercent = (data.itbisRate * 100).toStringAsFixed(0);
        lines.add(
          _totalsBlockLine(
            label: 'ITBIS ($itbisPercent%)',
            value: 'RD\$ ${_formatNumber(data.itbis)}',
            width: w,
          ),
        );
      }

      lines.add(sepLine(w));
    }

    // TOTAL (siempre visible, prominente)
    lines.add(
      _totalsBlockLine(
        label: 'TOTAL',
        value: 'RD\$ ${_formatNumber(data.total)}',
        width: w,
      ),
    );
    _addSectionSpace(lines, 1);

    // ============================================================
    // 7. FORMA DE PAGO / APARTADO / CRÉDITO (si está configurada)
    // ============================================================
    final methodLower = data.paymentMethod.toLowerCase();
    final bool isCredit =
        methodLower.contains('credit') ||
        methodLower.contains('crédito') ||
        methodLower.contains('credito');
    final double creditPending = isCredit ? pendingAmount : 0.0;

    if (config.showPaymentInfo &&
        (data.paymentMethod.isNotEmpty || isLayaway)) {
      lines.add(sepLine(w));

      if (isLayaway) {
        lines.add(alignText('APARTADO', w, 'center'));
        lines.add(
          _totalsBlockLine(label: 'Estado', value: layawayStatus, width: w),
        );

        if (data.lastPaymentAmount > 0) {
          lines.add(
            _totalsBlockLine(
              label: 'Abono',
              value: 'RD\$ ${_formatNumber(data.lastPaymentAmount)}',
              width: w,
            ),
          );
        }

        lines.add(
          _totalsBlockLine(
            label: 'Pagado',
            value: 'RD\$ ${_formatNumber(data.paidAmount)}',
            width: w,
          ),
        );

        lines.add(
          _totalsBlockLine(
            label: 'Pendiente',
            value: 'RD\$ ${_formatNumber(pendingAmount)}',
            width: w,
          ),
        );
      } else {
        lines.add(alignText('Pago: ${data.paymentMethod}', w, 'center'));

        if (isCredit) {
          if (data.lastPaymentAmount > 0) {
            lines.add(
              _totalsBlockLine(
                label: 'Abono',
                value: 'RD\$ ${_formatNumber(data.lastPaymentAmount)}',
                width: w,
              ),
            );
          }

          if (data.paidAmount > 0) {
            lines.add(
              _totalsBlockLine(
                label: 'Pagado',
                value: 'RD\$ ${_formatNumber(data.paidAmount)}',
                width: w,
              ),
            );
          }

          lines.add(
            _totalsBlockLine(
              label: 'Pendiente',
              value: 'RD\$ ${_formatNumber(creditPending)}',
              width: w,
            ),
          );
        } else {
          if (data.paidAmount > 0) {
            lines.add(
              _totalsBlockLine(
                label: 'Recibido',
                value: 'RD\$ ${_formatNumber(data.paidAmount)}',
                width: w,
              ),
            );
          }

          if (data.changeAmount > 0) {
            lines.add(
              _totalsBlockLine(
                label: 'Cambio',
                value: 'RD\$ ${_formatNumber(data.changeAmount)}',
                width: w,
              ),
            );
          }
        }
      }

      _addSectionSpace(lines, 1);
    }
    if (isCredit) {
      final interestRate = data.creditInterestRate;
      final interestAmount = data.total * (interestRate / 100);
      final totalDue = data.total + interestAmount;

      lines.add(sepLine(w));
      lines.add(alignText('CREDITO', w, 'center'));
      lines.add(
        _totalsBlockLine(
          label: 'Interes',
          value: '${interestRate.toStringAsFixed(2)}%',
          width: w,
        ),
      );
      lines.add(
        _totalsBlockLine(
          label: 'Total credito',
          value: 'RD\$ ${_formatNumber(totalDue)}',
          width: w,
        ),
      );
      if (data.creditTermDays != null && data.creditTermDays! > 0) {
        lines.add(
          _totalsBlockLine(
            label: 'Plazo (dias)',
            value: data.creditTermDays!.toString(),
            width: w,
          ),
        );
      }
      if (data.creditInstallments != null && data.creditInstallments! > 0) {
        final installmentAmount = totalDue / data.creditInstallments!;
        lines.add(
          _totalsBlockLine(
            label: 'Cuotas',
            value: data.creditInstallments!.toString(),
            width: w,
          ),
        );
        lines.add(
          _totalsBlockLine(
            label: 'Valor cuota',
            value: 'RD\$ ${_formatNumber(installmentAmount)}',
            width: w,
          ),
        );
      }
      if (data.creditDueDate != null) {
        lines.add(
          _totalsBlockLine(
            label: 'Vence',
            value: DateFormat('dd/MM/yyyy').format(data.creditDueDate!),
            width: w,
          ),
        );
      }
      if ((data.creditNote ?? '').isNotEmpty) {
        lines.add(alignText('Nota: ${data.creditNote}', w, 'left'));
      }
      _addSectionSpace(lines, 1);
    }

    // ============================================================
    // 8. FOOTER (centrado, profesional)
    // ============================================================
    lines.add(alignText('Gracias por su compra', w, 'center'));
    lines.add(alignText('No se aceptan devoluciones sin', w, 'center'));
    lines.add(alignText('presentar este ticket.', w, 'center'));

    if (config.showFooterMessage && config.footerMessage.isNotEmpty) {
      _addSectionSpace(lines, 1);
      lines.add(alignText(config.footerMessage, w, 'center'));
    }

    // Espacio para corte (ESC/POS)
    if (config.autoCut) {
      _addSectionSpace(lines, 3);
    }

    // Seguridad extra: garantizar que ninguna línea exceda el ancho.
    return lines.map((l) => _fitLine(l, w)).toList(growable: false);
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

  /// Alinea un total (label: value) alineado a la derecha
  String totalsLine(String label, String value, int width) {
    final text = '$label: $value';
    return alignText(text, width, 'right');
  }

  void _addSectionSpace(List<String> lines, [int count = 1]) {
    final extra = config.sectionSpacingLevel >= 8
        ? 2
        : (config.sectionSpacingLevel >= 6 ? 1 : 0);
    final int total = (count + extra).clamp(1, 4).toInt();

    for (int i = 0; i < total; i++) {
      lines.add('');
    }
  }

  String _getDocumentType(TicketType type) {
    switch (type) {
      case TicketType.sale:
        return 'FACTURA';
      case TicketType.quote:
        return 'COTIZACIÓN';
      case TicketType.refund:
        return 'DEVOLUCIÓN';
      case TicketType.credit:
        return 'NOTA DE CRÉDITO';
      case TicketType.copy:
        return 'COPIA';
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _formatNumber(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
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

  /// Renderiza una línea de totales como un bloque alineado (derecha/centro/izquierda)
  /// con dos columnas: etiqueta y valor (valor alineado a la derecha).
  String _totalsBlockLine({
    required String label,
    required String value,
    required int width,
  }) {
    final safeLabel = _sanitizeTicketText(label);
    final safeValue = _sanitizeTicketText(value);

    // Tamaño del bloque de totales (en chars). Para 48 chars suele verse bien en 24.
    final int blockWidth = (width >= 40) ? 24 : (width >= 32 ? 20 : width);
    final int valueWidth = (blockWidth >= 24) ? 10 : 9;
    final int labelWidth = (blockWidth - valueWidth - 1).clamp(8, blockWidth);

    final labelText = (safeLabel.length > labelWidth)
        ? safeLabel.substring(0, labelWidth)
        : safeLabel.padRight(labelWidth);

    final valueText = (safeValue.length > valueWidth)
        ? safeValue.substring(safeValue.length - valueWidth)
        : safeValue.padLeft(valueWidth);

    final block = '$labelText $valueText';
    return alignText(block, width, config.totalsAlignment);
  }

  // ============================================================
  // FACTURA CLÁSICA (como el ejemplo solicitado)
  // ============================================================

  String _formatInvoiceNumber(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return s;
    final isDigitsOnly = RegExp(r'^\d+$').hasMatch(s);
    if (!isDigitsOnly) return s;
    // En la mayoría de facturas tipo ticket se imprime con ceros a la izquierda.
    // 7 es un estándar común (ejemplo: 0039740). Si ya es >=7, no tocar.
    return s.length >= 7 ? s : s.padLeft(7, '0');
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

  List<String> _buildClassicInvoiceLines(TicketData data) {
    final lines = <String>[];
    final w = config.maxCharsPerLine;
    final bool isLayaway = data.isLayaway;
    final double pendingAmount = data.pendingAmount < 0
        ? 0
        : data.pendingAmount;
    final String layawayStatus =
        (data.statusLabel ?? (pendingAmount > 0 ? 'PENDIENTE' : 'PAGADO'));

    void addLine(String raw) => lines.add(_fitLine(raw, w));
    void addAlignedTextLine(String text, String align) =>
        addLine(alignText(_sanitizeTicketText(text), w, align));
    void addSectionGap() {
      final n = config.sectionEmptyLines;
      for (var i = 0; i < n; i++) {
        addLine('');
      }
    }

    // 1) Encabezado
    if (config.showCompanyInfo) {
      final companyName = company.name.trim().toUpperCase();
      if (companyName.isNotEmpty) {
        addAlignedTextLine(companyName, config.headerAlignment);
      }

      final address = (company.address ?? '').trim();
      if (address.isNotEmpty) {
        for (final line in address.split('\n')) {
          final t = line.trim();
          if (t.isNotEmpty) {
            addAlignedTextLine(t, config.headerAlignment);
          }
        }
      }

      final rnc = (company.rnc ?? '').trim();
      final phone = (company.primaryPhone ?? '').trim();

      // Línea compacta: RNC + TEL en una sola línea si cabe.
      final rncPart = rnc.isNotEmpty ? 'RNC: $rnc' : '';
      final telPart = phone.isNotEmpty ? 'TEL: $phone' : '';
      final combined = (rncPart.isNotEmpty && telPart.isNotEmpty)
          ? '$rncPart   $telPart'
          : (rncPart.isNotEmpty ? rncPart : telPart);
      if (combined.trim().isNotEmpty) {
        addAlignedTextLine(combined, config.headerAlignment);
      }
    }

    addLine(sepLine(w));
    addSectionGap();

    // 2) Título documento
    addAlignedTextLine('F A C T U R A', 'center');
    addLine(sepLine(w));
    addSectionGap();

    // 3) Fecha/Hora
    final dateStr = DateFormat('dd/MM/yyyy').format(data.dateTime);
    final timeStr = DateFormat('hh:mm a').format(data.dateTime);
    addLine(_twoColsStrict(dateStr, timeStr, w));
    addSectionGap();

    // 4) Datos generales
    addAlignedTextLine(
      'Numero Factura: ${_formatInvoiceNumber(data.ticketNumber)}',
      config.detailsAlignment,
    );

    final clientName = (data.client?.name ?? '').trim();
    final resolvedClient = clientName.isEmpty ? 'GENERAL' : clientName;
    addAlignedTextLine('CLIENTE: $resolvedClient', config.detailsAlignment);

    final clientRnc = (data.client?.rnc ?? '').trim();
    // En el ejemplo de referencia, la línea RNC aparece aunque esté vacía.
    addAlignedTextLine('RNC: $clientRnc', config.detailsAlignment);

    if (config.showCashier) {
      final cashier = (data.cashierName ?? '').trim();
      addAlignedTextLine(
        'CAJERO(A): ${(cashier.isEmpty ? 'N/A' : cashier)}',
        config.detailsAlignment,
      );
    }

    final ncf = (data.ncf ?? '').trim();
    if (config.showNcf && ncf.isNotEmpty) {
      addAlignedTextLine(
        'Tipo CF: ${_cfTypeLabelFromNcf(ncf)}',
        config.detailsAlignment,
      );
      addAlignedTextLine('NCF: $ncf', config.detailsAlignment);
    }

    addSectionGap();

    // 5) Items (TABLA 4 COLUMNAS, 1 LÍNEA POR ITEM)
    // Requisito: no romper la tabla. Si la descripción es larga: recortar.
    // mm80 normal: 48 chars. Fallback: 42 chars configurable.
    int qtyW;
    int priceW;
    int totalW;
    int descW;

    // Formato objetivo (48 chars): qty=6, desc=24, price=9, total=9
    // Formato objetivo (42 chars): qty=6, desc=18, price=9, total=9
    qtyW = 6;
    priceW = 9;
    totalW = 9;
    descW = w - qtyW - priceW - totalW;

    // Seguridad: garantizar desc mínima.
    const minDescW = 10;
    if (descW < minDescW) {
      // Reducir numéricas si el ancho es extremadamente bajo.
      priceW = 8;
      totalW = 8;
      descW = w - qtyW - priceW - totalW;
    }
    if (descW < minDescW) {
      priceW = 7;
      totalW = 7;
      descW = w - qtyW - priceW - totalW;
    }

    // Validación estricta: columnas deben sumar exactamente el ancho.
    assert(qtyW + descW + priceW + totalW == w);

    String fmtQty(double q) {
      final isInt = (q % 1) == 0;
      if (isInt) return q.toStringAsFixed(0);
      // 2 decimales para cantidades fraccionadas.
      return q.toStringAsFixed(2);
    }

    String fmtMoney(double v) => ReceiptText.money(v);

    // Header EXACTO (visual) del ejemplo.
    // Usamos 2 espacios dentro de la columna descripción para que no se vea pegado.
    final header =
        '${ReceiptText.padRight('CANT.', qtyW)}'
        '${ReceiptText.padRight('  DESCRIPCION', descW)}'
        '${ReceiptText.padLeft('PRECIO', priceW)}'
        '${ReceiptText.padLeft('TOTAL', totalW)}';

    addLine(ReceiptText.line(width: w));
    addLine(_fitLine(header, w));
    addLine(ReceiptText.line(width: w));

    String buildItemDesc(TicketItemData item) {
      // Requisito: NO imprimir código de producto en ningún ticket.
      return item.name.trim().toUpperCase();
    }

    String truncateDesc(String text, int width) {
      final cleaned = _sanitizeTicketText(
        text,
      ).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (width <= 0) return '';
      if (cleaned.length <= width) return cleaned;
      if (width <= 3) return cleaned.substring(0, width);
      return '${cleaned.substring(0, width - 3)}...';
    }

    for (final item in data.items) {
      final qty = ReceiptText.padRight(fmtQty(item.quantity), qtyW);
      final descInnerW = (descW - 2).clamp(0, descW);
      final descText = truncateDesc(buildItemDesc(item), descInnerW);
      final desc = ReceiptText.padRight('  $descText', descW);
      final unitPrice = ReceiptText.padLeft(fmtMoney(item.unitPrice), priceW);
      final lineTotal = ReceiptText.padLeft(fmtMoney(item.total), totalW);
      addLine('$qty$desc$unitPrice$lineTotal');
    }

    addLine(ReceiptText.line(width: w));

    addSectionGap();

    // 6) Totales (UNA SOLA LÍNEA VISUAL con " --> " y monto al borde derecho)
    // Fallback: si vienen en 0.00 pero hay items, recalcular para impresión.
    final computedSubtotal = data.items.fold<double>(
      0,
      (sum, i) => sum + (i.unitPrice * i.quantity),
    );
    final safeSubtotal = (data.subtotal <= 0 && computedSubtotal > 0)
        ? computedSubtotal
        : data.subtotal;

    final safeItbis = data.itbis;
    final safeDiscount = data.discount;

    final computedTotal = safeSubtotal - safeDiscount + safeItbis;
    final safeTotal = (data.total <= 0 && computedTotal > 0)
        ? computedTotal
        : data.total;

    String arrowTotal(String label, String value) {
      // Totales como bloque alineado a la derecha (visual “pegado” al lado derecho).
      // Mantiene el formato EXACTO: LABEL + " --> " + VALUE, con VALUE al borde derecho.
      final safeLabel = _sanitizeTicketText(label);
      final safeValue = _sanitizeTicketText(value);
      const arrow = ' --> ';

      // Ancho del bloque de totales (más pequeño que el ticket para que se vea “a la derecha”).
      final int blockW = (w >= 48) ? 30 : (w >= 42 ? 26 : w);
      final int effectiveBlockW = blockW.clamp(12, w);

      final int minValueW = 6;
      final int valueW = safeValue.length < minValueW
          ? minValueW
          : safeValue.length.clamp(minValueW, effectiveBlockW);
      final int leftW = (effectiveBlockW - valueW).clamp(0, effectiveBlockW);

      final leftText = '$safeLabel$arrow';
      final leftFit = ReceiptText.padRight(leftText, leftW);
      final valueFit = ReceiptText.padLeft(safeValue, valueW);
      final blockLine = _fitLine('$leftFit$valueFit', effectiveBlockW);

      // Alinear el bloque al borde derecho del ticket.
      return ReceiptText.padLeft(blockLine, w);
    }

    addLine(arrowTotal('SUB-TOTAL', ReceiptText.money(safeSubtotal)));
    if (safeDiscount > 0) {
      addLine(arrowTotal('DESCUENTO', ReceiptText.money(safeDiscount)));
    }
    if (config.showItbis && safeItbis > 0) {
      addLine(arrowTotal('ITBIS', ReceiptText.money(safeItbis)));
    }
    addLine(ReceiptText.line(width: w));
    addLine(arrowTotal('TOTAL', ReceiptText.money(safeTotal)));

    addSectionGap();

    // 7) Pago (según método)
    if (config.showPaymentInfo) {
      final method = _paymentLabel(data.paymentMethod);
      final isCredit = method == 'CREDITO';
      final creditPending = isCredit ? pendingAmount : 0.0;

      if (isLayaway) {
        addLine(arrowTotal('APARTADO', layawayStatus));
        if (data.lastPaymentAmount > 0) {
          addLine(
            arrowTotal('ABONO', ReceiptText.money(data.lastPaymentAmount)),
          );
        }
        addLine(arrowTotal('PAGADO', ReceiptText.money(data.paidAmount)));
        addLine(arrowTotal('PENDIENTE', ReceiptText.money(pendingAmount)));
      } else if (isCredit) {
        addLine(arrowTotal('CREDITO', ReceiptText.money(creditPending)));
        if (data.lastPaymentAmount > 0) {
          addLine(
            arrowTotal('ABONO', ReceiptText.money(data.lastPaymentAmount)),
          );
        }
        if (data.paidAmount > 0) {
          addLine(arrowTotal('PAGADO', ReceiptText.money(data.paidAmount)));
        }
        addLine(arrowTotal('PENDIENTE', ReceiptText.money(creditPending)));
      } else {
        final paidFallback = (data.paidAmount <= 0 && safeTotal > 0)
            ? safeTotal
            : data.paidAmount;
        final changeFallback = (data.paidAmount <= 0) ? 0.0 : data.changeAmount;

        if (method == 'TARJETA') {
          addLine(arrowTotal('TARJETA', ReceiptText.money(paidFallback)));
        } else if (method == 'TRANSFERENCIA') {
          addLine(arrowTotal('TRANSFERENCIA', ReceiptText.money(paidFallback)));
        } else if (method == 'EFECTIVO') {
          addLine(arrowTotal('EFECTIVO', ReceiptText.money(safeTotal)));
          addLine(arrowTotal('PAGADO', ReceiptText.money(paidFallback)));
          if (changeFallback != 0) {
            addLine(arrowTotal('CAMBIO', ReceiptText.money(changeFallback)));
          }
        } else if (method.isNotEmpty) {
          addLine(arrowTotal(method, ReceiptText.money(paidFallback)));
          addLine(arrowTotal('PAGADO', ReceiptText.money(paidFallback)));
          if (changeFallback != 0) {
            addLine(arrowTotal('CAMBIO', ReceiptText.money(changeFallback)));
          }
        }
      }
    }

    // Separador final (antes de política/footer)
    addLine(sepLine(w));
    addLine('');

    // Debug: validar overflow (solo en debug).
    assert(() {
      for (final l in lines) {
        if (l.length > w) {
          throw Exception('Overflow: ${l.length} > $w :: $l');
        }
      }
      return true;
    }());

    // 7) Política de garantía/cambios (configurable)
    final policyText = config.warrantyPolicy.trim();
    if (policyText.isNotEmpty) {
      // Separar visualmente la política del bloque de totales/pago.
      // Ya existe un separador y una línea en blanco justo antes.
      addLine('');
      addAlignedTextLine('POLITICA DE GARANTIA', 'center');
      addLine('');

      final rawLines = policyText.split('\n');
      for (final line in rawLines) {
        final raw = line.trimRight();
        final cleaned = raw
            .trim()
            .replaceFirst(RegExp(r'^[\-\*\u2022]+\s*'), '')
            .trim();
        if (cleaned.isEmpty) continue;
        final wrapped = _wrapTextHard(cleaned, w - 2);
        if (wrapped.isEmpty) continue;
        addLine(_fitLine('- ${_sanitizeTicketText(wrapped.first)}', w));
        for (final extra in wrapped.skip(1)) {
          addLine(_fitLine(' ${_sanitizeTicketText(extra)}', w));
        }
      }

      addLine('');
    }

    if (config.showFooterMessage && config.footerMessage.trim().isNotEmpty) {
      addAlignedTextLine(config.footerMessage.trim(), 'center');
    } else {
      addAlignedTextLine('GRACIAS POR PREFERIRNOS', 'center');
    }

    if (config.autoCut) {
      addLine('');
      addLine('');
      addLine('');
    }

    return lines.map((l) => _fitLine(l, w)).toList(growable: false);
  }

  String _cfTypeLabelFromNcf(String ncf) {
    final upper = ncf.toUpperCase();
    if (upper.startsWith('B01')) return 'FACTURA DE CRÉDITO FISCAL';
    if (upper.startsWith('B02')) return 'FACTURA DE CONSUMO';
    if (upper.startsWith('B14')) return 'FACTURA REG. ESPECIAL';
    if (upper.startsWith('B15')) return 'COMPROBANTE GUBERNAMENTAL';
    return 'FACTURA';
  }
}
