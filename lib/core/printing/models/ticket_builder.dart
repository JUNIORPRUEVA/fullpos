import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../../../features/settings/data/printer_settings_model.dart';
import '../../utils/currency_display.dart';
import 'company_info.dart';
import 'receipt_text_utils.dart';
import 'ticket_layout_config.dart';
import 'ticket_data.dart';
import 'ticket_renderer.dart';

/// Builder centralizado de tickets
/// Genera tanto texto plano para vista previa como PDF para impresión
/// Formato profesional estilo factura (80mm)
class TicketBuilder {
  final TicketLayoutConfig layout;
  final CompanyInfo company;

  TicketBuilder({required this.layout, required this.company});

  // ============================================================
  // HELPERS DE SEGURIDAD PARA ALINEACIÓN Y ANCHO
  // ============================================================

  /// Genera una línea de regla para debugging del ancho real
  /// Muestra: 0123456789012345678901234567890123456789
  /// Útil para verificar que el maxCharsPerLine es correcto
  String buildDebugRuler() {
    final w = layout.maxCharsPerLine;
    final buffer = StringBuffer();
    for (int i = 0; i < w; i++) {
      buffer.write((i % 10).toString());
    }
    return buffer.toString();
  }

  /// Trunca o rellena texto a la derecha sin exceder ancho
  String padRightSafe(String text, int width) {
    if (text.length > width) return text.substring(0, width);
    return text.padRight(width);
  }

  /// Trunca o rellena texto a la izquierda sin exceder ancho
  String padLeftSafe(String text, int width) {
    if (text.length > width) return text.substring(0, width);
    return text.padLeft(width);
  }

  /// Centra texto sin exceder ancho
  String centerSafe(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    final left = ((width - text.length) / 2).floor();
    final right = width - text.length - left;
    return ' ' * left + text + ' ' * right;
  }

  /// Repite un carácter hasta llenar el ancho
  String repeatedChar(String ch, int width) {
    return List.filled(width, ch).join('');
  }

  /// Alinea texto genéricamente respetando maxCharsPerLine
  /// align: 'left' | 'center' | 'right'
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
    return repeatedChar(char, width);
  }

  /// Alinea un total (label: value) respetando alineación configurada
  String totalsLine(String label, String value, int width, String align) {
    final text = '$label: $value';
    return alignText(text, width, align);
  }

  /// Alinea texto a la derecha con etiqueta a la izquierda (método legacy)
  String totalLine(String label, String value, int width) {
    final text = '$label: $value';
    if (text.length >= width) return text.substring(0, width);
    final pad = width - text.length;
    return ' ' * pad + text;
  }

  /// Genera ticket CON REGLA DE DEBUG para verificar el ancho real
  /// Útil para verificar que maxCharsPerLine es correcto
  /// Muestra una línea de números (0123456789...) al inicio
  String buildPlainTextWithDebugRuler(TicketData data) {
    final buffer = StringBuffer();

    // Agregar regla de debug al inicio
    buffer.writeln('DEBUG RULER - Verify width fits:');
    buffer.writeln(buildDebugRuler());
    buffer.writeln();

    // Ahora agregar el ticket normal
    buffer.write(buildPlainText(data));

    return buffer.toString();
  }

  // ============================================================
  // FORMATO PROFESIONAL DE TICKET (TEXTO PLANO)
  // ============================================================

  /// Genera el ticket en texto plano con formato profesional
  /// Estructura:
  /// ================================================
  ///        FULLTECH, SRL
  ///   RNC: 133080206 | Tel: +1(829)531-8442
  ///         Centro Balber 9
  /// ----
  ///
  /// FACTURA                 FECHA: 29/12/2025
  ///                         TICKET: #DEMO-001
  /// ----
  ///
  /// Cajero: Junior
  ///
  /// DATOS DEL CLIENTE:
  /// Nombre: Cliente Demo
  /// Teléfono: (809) 555-1234
  /// ----
  ///
  /// CANT  PRODUCTO                 PRECIO
  /// ----
  /// 2     Producto de Prueba       500.00
  /// 1     Otro producto            200.00
  /// ----
  ///
  ///              SUB-TOTAL: RDS 1,000.00
  ///              ITBIS (18%): RDS   180.00
  ///              -----
  ///              TOTAL: RDS 1,180.00
  ///
  /// Gracias por su compra
  /// No se aceptan devoluciones sin
  /// presentar este ticket.
  ///
  String buildPlainText(TicketData data) {
    // FUENTE ÚNICA DE VERDAD: Usar TicketRenderer
    final renderer = TicketRenderer(config: layout, company: company);
    final lines = renderer.buildLines(data);

    // Convertir líneas a string
    return lines.join('\n');
  }

  // ============================================================
  // GENERACIÓN DE PDF PROFESIONAL (para impresión térmica)
  // ============================================================

  /// Genera el ticket como documento PDF para impresión térmica
  /// Usa TicketRenderer.buildLines() como FUENTE ÚNICA de verdad para el layout
  pw.Document buildPdf(TicketData data) {
    final renderer = TicketRenderer(config: layout, company: company);
    final lines = renderer.buildLines(data);
    return buildPdfFromLines(lines, includeLogo: true, sourceData: data);
  }

  /// Genera un PDF desde una lista de líneas ya alineadas (monoespaciado).
  /// Útil para tickets especiales de prueba (ej. regla de ancho).
  pw.Document buildPdfFromLines(
    List<String> lines, {
    required bool includeLogo,
    TicketData? sourceData,
  }) {
    final doc = pw.Document();
    final bool isCashClosePdf =
        sourceData == null &&
        lines.any(
          (line) =>
              line.toUpperCase().contains('CORTE DE TURNO') ||
              line.toUpperCase().contains('CORTE DE CAJA'),
        );

    // Fuentes monoespaciadas para preservar columnas.
    // Importante: NO forzar negrita en el cuerpo en tamaños normales;
    // pero cuando el tamaño queda muy pequeño (común en 58mm), el normal puede
    // salir “lavado” en algunas impresoras/drivers, así que oscurecemos levemente.
    final pw.Font normalFont = isCashClosePdf
        ? pw.Font.helvetica()
        : pw.Font.courier();
    final pw.Font boldFont = isCashClosePdf
        ? pw.Font.helveticaBold()
        : pw.Font.courierBold();

    // Ancho real imprimible (ver `TicketLayoutConfig.printableWidthMm`).
    final double pageWidth = layout.printableWidthMm * PdfPageFormat.mm;

    // Alto del rollo: usar un valor grande FINITO.
    // En algunos drivers/spoolers (Windows) `double.infinity` puede imprimir en blanco.
    final double pageHeight = 2000 * PdfPageFormat.mm;

    // Márgenes (mm). En térmicas, márgenes grandes destruyen el ancho útil.
    // Por estabilidad (alineación/columnas), limitamos el rango.
    final double marginLeftPts =
        (layout.leftMarginMm.clamp(0, 4)) * PdfPageFormat.mm;
    final double marginRightPts =
        (layout.rightMarginMm.clamp(0, 4)) * PdfPageFormat.mm;
    final double contentWidthPts = (pageWidth - marginLeftPts - marginRightPts)
        .clamp(10.0, pageWidth);

    // Fuente monoespaciada: aproximación Courier => ancho de carácter ~0.60 * fontSize.
    // Usamos un factor conservador para evitar desalineación por wraps.
    const double courierCharWidthFactor = 0.60;
    final double fittedFontSize =
        contentWidthPts / (layout.maxCharsPerLine * courierCharWidthFactor);

    // Tamaño de fuente:
    // - `layout.adjustedFontSize` refleja el ajuste del usuario (niveles 1-10)
    // - `fittedFontSize` es el máximo que cabe sin romper columnas
    // Importante: nunca exceder el fitted; si no, el driver hace wrap y se desalinean columnas.
    const double safety = 0.98;
    // Permitir letra más grande por defecto (siempre limitado por fittedFontSize).
    final double maxReadableFont = 16.0;
    final double desiredFontSize = layout.adjustedFontSize;
    final double fontSize = math
        .min(
          math.min(desiredFontSize, fittedFontSize * safety),
          maxReadableFont,
        )
        .clamp(5.5, maxReadableFont);

    // En muchas impresoras 80mm, el Courier normal puede salir “gris” comparado con el
    // encabezado (que va en bold). Para mantener ducto
    // una base más oscura en 80mm. En 58mm, solo forzamos bold cuando el tamaño es
    // muy pequeño para mejorar contraste sin volverlo pesado.
    final bool preferDarkerBody = layout.paperWidthMm == 80 && !isCashClosePdf;
    final pw.Font bodyFont = preferDarkerBody
        ? boldFont
        : (fontSize < 7.0 ? boldFont : normalFont);

    final content = <pw.Widget>[];

    final bool hasLogo =
        includeLogo && layout.showLogo && company.logoBytes != null;

    if (sourceData != null && sourceData.type == TicketType.sale) {
      return _buildStructuredSalesPdf(
        doc: doc,
        data: sourceData,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        marginLeftPts: marginLeftPts,
        marginRightPts: marginRightPts,
      );
    }

    // Render por líneas para poder resaltar encabezados/totales.
    // Soporta tags al inicio de la línea:
    // - <H1C>, <H2C> (grande, centrado)
    // - <H1R>, <H2R> (grande, derecha)
    // - <BC>, <BR>, <BL> (negrita)
    // - sin tag: texto normal
    pw.Alignment alignmentFromTag(String tag) {
      final t = tag.toUpperCase();
      if (t.contains('R')) return pw.Alignment.centerRight;
      if (t.contains('C')) return pw.Alignment.center;
      return pw.Alignment.centerLeft;
    }

    ({String tag, String text}) parseTag(String raw) {
      final s = raw;
      if (s.startsWith('<')) {
        final end = s.indexOf('>');
        if (end > 1) {
          final tag = s.substring(1, end);
          final text = s.substring(end + 1);
          return (tag: tag, text: text);
        }
      }
      return (tag: '', text: s);
    }

    bool isSeparatorLine(String text) {
      final t = text.trim();
      if (t.isEmpty) return false;
      // Considerar separadores típicos: ---- o ====.
      final first = t.codeUnitAt(0);
      for (final c in t.codeUnits) {
        if (c != first) return false;
      }
      return t.length >= 6 && (t[0] == '-' || t[0] == '=');
    }

    // Detectar bloque de encabezado: desde el inicio hasta el primer separador.
    // Esto nos permite imprimir el header (empresa/dirección/RNC) más grande y elegante,
    // sin romper columnas del cuerpo.
    int firstSeparatorIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (isSeparatorLine(lines[i])) {
        firstSeparatorIndex = i;
        break;
      }
    }

    int secondSeparatorIndex = -1;
    if (firstSeparatorIndex != -1) {
      for (var i = firstSeparatorIndex + 1; i < lines.length; i++) {
        if (isSeparatorLine(lines[i])) {
          secondSeparatorIndex = i;
          break;
        }
      }
    }

    bool isSalesPdf = sourceData != null && sourceData.type == TicketType.sale;

    String resolveDocumentTitle(TicketData data) {
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

    String buildFacCode(String ticketNumber) {
      final trimmed = ticketNumber.trim();
      if (trimmed.isEmpty) return 'FAC-0000';
      final digits = trimmed.replaceAll(RegExp(r'\D'), '');
      if (digits.isNotEmpty) {
        return 'FAC-${digits.substring(math.max(0, digits.length - 4)).padLeft(4, '0')}';
      }
      final cleaned = trimmed.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      return 'FAC-${cleaned.substring(math.max(0, cleaned.length - 4)).padLeft(4, '0')}';
    }

    bool shouldSkipBodyLine(String text) {
      if (!isSalesPdf) return false;
      final trimmed = text.trim();
      if (trimmed.isEmpty) return false;
      if (trimmed == resolveDocumentTitle(sourceData)) return true;
      if (trimmed.startsWith('DOC:')) return true;
      if (trimmed.startsWith('CAJERO:')) return true;
      return false;
    }

    pw.TextStyle styleFromTag(String tag) {
      final t = tag.toUpperCase();
      final bool bold =
          !isCashClosePdf && (t.startsWith('B') || t.startsWith('H'));
      double size = fontSize;
      if (t.startsWith('H1')) {
        size = isCashClosePdf ? fontSize * 1.16 : fontSize * 1.35;
      }
      if (t.startsWith('H2')) {
        size = isCashClosePdf ? fontSize * 1.10 : fontSize * 1.18;
      }

      // Evitar tamaños demasiado grandes en algunos drivers.
      size = size.clamp(fontSize, isCashClosePdf ? 14.0 : 16.0);

      return pw.TextStyle(
        font: bold ? boldFont : bodyFont,
        fontSize: size,
        lineSpacing: 1.0 * layout.lineSpacingFactor,
      );
    }

    ({String left, String right})? parseTwoColumnLine(String text) {
      final trimmed = text.trimRight();
      final match = RegExp(r'^(.*\S)\s{2,}(\S.*)$').firstMatch(trimmed);
      if (match == null) return null;
      final left = match.group(1)?.trimRight() ?? '';
      final right = match.group(2)?.trimLeft() ?? '';
      if (left.isEmpty || right.isEmpty) return null;
      return (left: left, right: right);
    }

    pw.TextStyle styleForLine(String tag, String text, int index) {
      // Si ya hay tag explícito, respetarlo.
      if (tag.isNotEmpty) return styleFromTag(tag);

      final isInHeaderBlock =
          firstSeparatorIndex != -1 && index < firstSeparatorIndex;
      if (!isInHeaderBlock) {
        final trimmed = text.trimLeft();
        if (trimmed.startsWith('SUBTOTAL:') ||
            trimmed.startsWith('DESCUENTO:') ||
            trimmed.startsWith('ITBIS') ||
            trimmed.startsWith('TOTAL:')) {
          if (isCashClosePdf) {
            return pw.TextStyle(
              font: bodyFont,
              fontSize: fontSize,
              lineSpacing: 1.0 * layout.lineSpacingFactor,
            );
          }
          return pw.TextStyle(
            font: boldFont,
            fontSize: math.min(fontSize * 1.12, 16.5),
            lineSpacing: 1.04 * layout.lineSpacingFactor,
          );
        }
        return styleFromTag(tag);
      }

      // Encabezado más grande: primera línea (nombre) más grande; resto ligeramente menor.
      final trimmed = text.trim();
      if (trimmed.isEmpty) return styleFromTag(tag);

      if (isCashClosePdf) {
        final multiplier = index == 0 ? 1.12 : 1.04;
        final maxToFit =
            contentWidthPts /
            (math.max(1, trimmed.length) * courierCharWidthFactor) *
            safety;
        final size = math
            .min(math.min(fontSize * multiplier, maxToFit), 14.0)
            .clamp(fontSize, 14.0);
        return pw.TextStyle(
          font: bodyFont,
          fontSize: size,
          lineSpacing: 1.0 * layout.lineSpacingFactor,
        );
      }

      final multiplier = index == 0 ? 1.35 : 1.15;
      // Intentar agrandar el header, pero sin exceder el tamaño que cabe.
      // (El body usa padding/columnas; el header va sin padding y centrado.)
      final maxToFit =
          contentWidthPts /
          (math.max(1, trimmed.length) * courierCharWidthFactor) *
          safety;
      final size = math
          .min(math.min(fontSize * multiplier, maxToFit), 18.0)
          .clamp(fontSize, 18.0);
      return pw.TextStyle(
        font: boldFont,
        fontSize: size,
        lineSpacing: 1.0 * layout.lineSpacingFactor,
      );
    }

    pw.Widget buildLineWidget(int index) {
      final raw = lines[index];
      final parsed = parseTag(raw);
      final tag = parsed.tag;
      final text = parsed.text;

      // Si la línea es “grande”, no conviene respetar pads/espacios a la derecha.
      final isHeader = tag.toUpperCase().startsWith('H');
      final display = isHeader ? text.trimRight() : text;

      final isHeaderBlock =
          tag.isEmpty &&
          firstSeparatorIndex != -1 &&
          index < firstSeparatorIndex;

      final headerText = display.trim();
      final widget = pw.Text(
        (isHeaderBlock ? headerText : display).isEmpty
            ? ' '
            : (isHeaderBlock ? headerText : display),
        style: styleForLine(tag, display, index),
        textAlign: isHeaderBlock ? pw.TextAlign.center : pw.TextAlign.left,
      );

      if (isCashClosePdf && isSeparatorLine(display)) {
        return pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 2),
          height: 0.55,
          color: PdfColors.grey400,
        );
      }

      final parsedPair = isCashClosePdf && !isHeaderBlock
          ? parseTwoColumnLine(display)
          : null;
      if (parsedPair != null) {
        final pairStyle = styleForLine('', display, index);
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  parsedPair.left,
                  style: pairStyle,
                  textAlign: pw.TextAlign.left,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.SizedBox(
                width: math.min(118.0, contentWidthPts * 0.34),
                child: pw.Text(
                  parsedPair.right,
                  style: pairStyle,
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }

      if (tag.isEmpty) {
        if (isHeaderBlock) {
          return pw.Align(alignment: pw.Alignment.center, child: widget);
        }
        return widget;
      }

      return pw.Align(alignment: alignmentFromTag(tag), child: widget);
    }

    pw.Widget buildSalesHeaderWidget(TicketData data) {
      final headerLines = firstSeparatorIndex > 0
          ? lines
                .take(firstSeparatorIndex)
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty)
                .toList(growable: false)
          : <String>[];
      final image = hasLogo ? pw.MemoryImage(company.logoBytes!) : null;
      final logoSize = layout.logoSizePx.toDouble().clamp(34.0, 54.0);
      final headerName = headerLines.isNotEmpty
          ? headerLines.first
          : company.name.trim().toUpperCase();
      final headerMeta = headerLines.length > 1
          ? headerLines.skip(1).toList(growable: false)
          : const <String>[];
      final title = resolveDocumentTitle(data);
      final cashier = (data.cashierName ?? '').trim().isEmpty
          ? 'N/A'
          : data.cashierName!.trim();
      final facCode = buildFacCode(data.ticketNumber);
      final headerTextStyle = pw.TextStyle(
        font: boldFont,
        fontSize: math.min(fontSize * 1.18, 15.5),
      );
      final metaTextStyle = pw.TextStyle(
        font: bodyFont,
        fontSize: fontSize,
        lineSpacing: 1.05 * layout.lineSpacingFactor,
      );
      final titleStyle = pw.TextStyle(
        font: boldFont,
        fontSize: math.min(fontSize * 1.12, 15.0),
      );
      final infoStyle = pw.TextStyle(
        font: bodyFont,
        fontSize: math.max(fontSize - 0.2, 8.8),
        lineSpacing: 1.0 * layout.lineSpacingFactor,
      );

      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (image != null)
              pw.Container(
                width: logoSize,
                height: logoSize,
                margin: const pw.EdgeInsets.only(top: 2, right: 8),
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(headerName, style: headerTextStyle),
                  for (final meta in headerMeta)
                    pw.Text(meta, style: metaTextStyle),
                  pw.SizedBox(height: 3),
                  pw.Text(title, style: titleStyle),
                  if (data.isCopy) pw.Text('COPIA', style: infoStyle),
                  if ((data.extraLegend ?? '').trim().isNotEmpty)
                    pw.Text(
                      data.extraLegend!.trim().toUpperCase(),
                      style: infoStyle,
                    ),
                  pw.SizedBox(height: 2),
                  pw.Text('CAJERO: $cashier', style: infoStyle),
                  pw.Text(facCode, style: infoStyle),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (isSalesPdf && firstSeparatorIndex > 0) {
      content.add(buildSalesHeaderWidget(sourceData));
      if (firstSeparatorIndex < lines.length) {
        content.add(buildLineWidget(firstSeparatorIndex));
      }
    } else if (hasLogo) {
      final image = pw.MemoryImage(company.logoBytes!);
      content.add(
        pw.Center(
          child: pw.Image(
            image,
            width: layout.logoSizePx.toDouble(),
            height: layout.logoSizePx.toDouble(),
            fit: pw.BoxFit.contain,
          ),
        ),
      );
      content.add(pw.SizedBox(height: 0.2));
    }

    final startIndex = isSalesPdf && secondSeparatorIndex != -1
        ? secondSeparatorIndex + 1
        : 0;
    final bodyWidgets = <pw.Widget>[];
    for (var i = startIndex; i < lines.length; i++) {
      if (isSalesPdf && shouldSkipBodyLine(lines[i])) {
        continue;
      }
      bodyWidgets.add(buildLineWidget(i));
    }

    content.add(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: bodyWidgets,
      ),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          pageWidth,
          pageHeight,
          marginLeft: marginLeftPts,
          marginRight: marginRightPts,
          marginTop:
              (layout.topMarginPx.toDouble().clamp(0.0, 120.0) -
                      (hasLogo && !isSalesPdf ? 6.0 : 0.0))
                  .clamp(0.0, 120.0),
          marginBottom: layout.bottomMarginPx.toDouble().clamp(0.0, 120.0),
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: content,
        ),
      ),
    );

    return doc;
  }

  pw.Document _buildStructuredSalesPdf({
    required pw.Document doc,
    required TicketData data,
    required double pageWidth,
    required double pageHeight,
    required double marginLeftPts,
    required double marginRightPts,
  }) {
    final bodyFont = pw.Font.courier();
    final boldFont = pw.Font.courierBold();
    final is80mm = layout.paperWidthMm == 80;
    final uiBodyFont = bodyFont;

    final double baseFontSize = switch (layout.fontSize) {
      TicketFontSize.small => 9.8,
      TicketFontSize.normal => 10.0,
      TicketFontSize.large => 10.4,
    };
    final headerFontSize = math.min(baseFontSize + 0.3, 10.1);
    final titleFontSize = math.min(baseFontSize + 0.7, 10.7);
    final totalsFontSize = math.min(baseFontSize + 3.8, 14.2);
    final smallFontSize = math.max(baseFontSize - 1.0, 8.7);
    final compactTableFontSize = is80mm
        ? math.max(9.6, baseFontSize - 0.1)
        : math.max(9.6, baseFontSize - 0.1);
    final compactDescriptionFontSize = is80mm
        ? math.max(9.8, compactTableFontSize)
        : math.max(9.7, compactTableFontSize);
    final compactHeaderFontSize = math.max(baseFontSize - 1.0, 8.6);
    final logoSize = layout.logoSizePx.toDouble().clamp(32.0, 42.0);
    final sectionGap = (5.0 * layout.sectionSpacingFactor).clamp(4.0, 7.0);
    final lineGap = math.max(0.9, 0.95 * layout.lineSpacingFactor);
    const sectionPadding = pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3);
    final detailTableInset = is80mm ? 6.0 : 5.0;
    final qtyColumnWidth = is80mm ? 22.0 : 20.0;
    final priceColumnWidth = is80mm ? 32.0 : 30.0;
    final totalColumnWidth = is80mm ? 36.0 : 34.0;
    final detailGapWidth = 2.0;
    final detailNameChars = is80mm
        ? math.max(22, layout.maxCharsPerLine - 20)
        : math.max(14, layout.maxCharsPerLine - 22);

    final headerName = _sanitizePrintText(company.name).toUpperCase();
    final headerMeta = <String>[
      if ((company.rnc ?? '').trim().isNotEmpty)
        'RNC: ${_sanitizePrintText(company.rnc!.trim()).toUpperCase()}',
      if ((company.primaryPhone ?? '').trim().isNotEmpty)
        'TEL: ${_sanitizePrintText(company.primaryPhone!.trim()).toUpperCase()}',
      if ((company.address ?? '').trim().isNotEmpty)
        _sanitizePrintText(
          company.address!,
        ).replaceAll('\n', ' ').toUpperCase(),
    ];

    final title = _resolveSalesDocumentTitle(data).toUpperCase();
    final cashier = (data.cashierName ?? '').trim().isEmpty
        ? 'N/A'
        : _sanitizePrintText(data.cashierName!.trim()).toUpperCase();
    final facCode = _buildFacCode(data.ticketNumber).toUpperCase();
    final clientName = (data.client?.name ?? '').trim().isEmpty
        ? 'GENERAL'
        : _sanitizePrintText(data.client!.name.trim()).toUpperCase();
    final clientPhone = _sanitizePrintText(
      (data.client?.phone ?? '').trim(),
    ).toUpperCase();
    final clientRnc = _sanitizePrintText(
      (data.client?.rnc ?? '').trim(),
    ).toUpperCase();
    final dateText = _formatDate(data.dateTime);
    final timeText = _formatTime(data.dateTime);
    final ecfCode = _sanitizePrintText(
      (data.electronicInvoiceCode ?? '').trim(),
    ).toUpperCase();
    final fiscalReceiptNumber = _sanitizePrintText(
      (data.fiscalReceiptNumber ?? '').trim(),
    ).toUpperCase();
    final fiscalReceiptName = _sanitizePrintText(
      (data.fiscalReceiptName ?? '').trim(),
    ).toUpperCase();
    final fiscalReceiptCode = _sanitizePrintText(
      (data.fiscalReceiptCode ?? '').trim(),
    ).toUpperCase();
    final paymentMethod = _sanitizePrintText(data.paymentMethod).toUpperCase();

    final computedSubtotal = data.items.fold<double>(
      0,
      (sum, item) => sum + item.total,
    );
    final subtotal = (data.subtotal <= 0 && computedSubtotal > 0)
        ? computedSubtotal
        : data.subtotal;
    final computedTotal = subtotal - data.discount + data.itbis;
    final total = (data.total <= 0 && computedTotal > 0)
        ? computedTotal
        : data.total;
    final paidAmount = data.paidAmount <= 0 ? total : data.paidAmount;
    final itemCount = data.items.length;
    final dividerColor = PdfColor.fromHex('#111111');
    final bodyTextColor = PdfColor.fromHex('#000000');
    final mutedTextColor = PdfColor.fromHex('#080808');

    String money(num value) =>
        CurrencyDisplay.formatPlain(value, decimalDigits: 2);
    String compactMoney(num value) =>
        CurrencyDisplay.formatPlain(value, decimalDigits: 0);
    String tableMoney(num value) =>
        CurrencyDisplay.formatPlain(value, decimalDigits: 0);
    final footerFontSize = math.max(baseFontSize - 0.7, 8.8);

    final content = <pw.Widget>[
      pw.Container(
        padding: sectionPadding,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (company.logoBytes != null && layout.showLogo) ...[
              pw.SizedBox(
                width: logoSize,
                height: logoSize,
                child: pw.Image(
                  pw.MemoryImage(company.logoBytes!),
                  fit: pw.BoxFit.contain,
                ),
              ),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  if (headerName.isNotEmpty)
                    pw.Text(
                      headerName,
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: headerFontSize,
                        color: bodyTextColor,
                      ),
                      textAlign: pw.TextAlign.left,
                    ),
                  if (headerMeta.isNotEmpty) pw.SizedBox(height: 2),
                  for (final meta in headerMeta)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 1),
                      child: pw.Text(
                        meta,
                        style: pw.TextStyle(
                          font: uiBodyFont,
                          fontSize: smallFontSize,
                          color: mutedTextColor,
                          lineSpacing: lineGap,
                        ),
                        textAlign: pw.TextAlign.left,
                        maxLines: 1,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: math.max(2.0, sectionGap - 1)),
      pw.Padding(
        padding: sectionPadding,
        child: pw.Text(
          title,
          style: pw.TextStyle(
            font: boldFont,
            fontSize: titleFontSize,
            color: bodyTextColor,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.Padding(
        padding: sectionPadding,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                'DOC: $facCode',
                style: pw.TextStyle(
                  font: uiBodyFont,
                  fontSize: smallFontSize,
                  color: bodyTextColor,
                ),
                maxLines: 1,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                'CAJERO: $cashier',
                style: pw.TextStyle(
                  font: uiBodyFont,
                  fontSize: smallFontSize,
                  color: bodyTextColor,
                ),
                textAlign: pw.TextAlign.right,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
      if (data.isCopy)
        pw.Padding(
          padding: sectionPadding,
          child: pw.Text(
            'COPIA',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: smallFontSize,
              color: bodyTextColor,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
      if ((data.extraLegend ?? '').trim().isNotEmpty)
        pw.Padding(
          padding: sectionPadding,
          child: pw.Text(
            _sanitizePrintText(data.extraLegend!.trim()).toUpperCase(),
            style: pw.TextStyle(
              font: uiBodyFont,
              fontSize: smallFontSize,
              color: bodyTextColor,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
      pw.SizedBox(height: math.max(2.0, sectionGap - 2)),
      pw.Padding(
        padding: sectionPadding,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'CLIENTE: $clientName',
                    style: pw.TextStyle(
                      font: uiBodyFont,
                      fontSize: smallFontSize,
                      color: bodyTextColor,
                    ),
                  ),
                  if (clientPhone.isNotEmpty)
                    pw.Text(
                      'TEL: $clientPhone',
                      style: pw.TextStyle(
                        font: uiBodyFont,
                        fontSize: smallFontSize,
                        lineSpacing: lineGap,
                        color: bodyTextColor,
                      ),
                    ),
                  if (clientRnc.isNotEmpty)
                    pw.Text(
                      'RNC: $clientRnc',
                      style: pw.TextStyle(
                        font: uiBodyFont,
                        fontSize: smallFontSize,
                        lineSpacing: lineGap,
                        color: bodyTextColor,
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'FECHA: $dateText',
                  style: pw.TextStyle(
                    font: uiBodyFont,
                    fontSize: smallFontSize,
                    color: bodyTextColor,
                  ),
                ),
                pw.Text(
                  'HORA: $timeText',
                  style: pw.TextStyle(
                    font: uiBodyFont,
                    fontSize: smallFontSize,
                    color: bodyTextColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (ecfCode.isNotEmpty)
        pw.Padding(
          padding: sectionPadding,
          child: pw.Text(
            'E-CF: $ecfCode',
            style: pw.TextStyle(
              font: uiBodyFont,
              fontSize: smallFontSize,
              color: bodyTextColor,
            ),
          ),
        ),
      if (fiscalReceiptNumber.isNotEmpty)
        pw.Padding(
          padding: sectionPadding,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'COMPROBANTE FISCAL',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: smallFontSize,
                  color: bodyTextColor,
                ),
              ),
              pw.Text(
                'Tipo: ${(fiscalReceiptName.isNotEmpty ? fiscalReceiptName : fiscalReceiptCode)}',
                style: pw.TextStyle(
                  font: uiBodyFont,
                  fontSize: smallFontSize,
                  color: bodyTextColor,
                ),
              ),
              pw.Text(
                'NCF: $fiscalReceiptNumber',
                style: pw.TextStyle(
                  font: uiBodyFont,
                  fontSize: smallFontSize,
                  color: bodyTextColor,
                ),
              ),
              if (data.fiscalReceiptExpirationDate != null)
                pw.Text(
                  'Vence: ${DateFormat('dd/MM/yyyy').format(data.fiscalReceiptExpirationDate!)}',
                  style: pw.TextStyle(
                    font: uiBodyFont,
                    fontSize: smallFontSize,
                    color: bodyTextColor,
                  ),
                ),
            ],
          ),
        ),
      pw.SizedBox(height: math.max(2.0, sectionGap - 2)),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'DETALLE DE VENTA',
              style: pw.TextStyle(
                font: boldFont,
                fontSize: compactHeaderFontSize,
                color: bodyTextColor,
              ),
            ),
            pw.Text(
              '$itemCount ART.',
              style: pw.TextStyle(
                font: bodyFont,
                fontSize: compactHeaderFontSize,
                color: mutedTextColor,
              ),
            ),
          ],
        ),
      ),
      pw.Container(
        margin: pw.EdgeInsets.symmetric(horizontal: detailTableInset),
        padding: const pw.EdgeInsets.only(top: 1, bottom: 2),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: dividerColor, width: 0.6),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.SizedBox(
              width: qtyColumnWidth,
              child: pw.Text(
                'CANT',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: compactHeaderFontSize,
                  color: mutedTextColor,
                ),
                maxLines: 1,
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.SizedBox(width: detailGapWidth),
            pw.Expanded(
              child: pw.Text(
                'PRODUCTO',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: compactHeaderFontSize,
                  color: mutedTextColor,
                ),
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
              ),
            ),
            pw.SizedBox(width: detailGapWidth),
            pw.SizedBox(
              width: priceColumnWidth,
              child: pw.Text(
                'P/U',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: compactHeaderFontSize,
                  color: mutedTextColor,
                ),
                textAlign: pw.TextAlign.right,
                maxLines: 1,
              ),
            ),
            pw.SizedBox(width: detailGapWidth),
            pw.SizedBox(
              width: totalColumnWidth,
              child: pw.Text(
                'TOTAL',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: compactHeaderFontSize,
                  color: mutedTextColor,
                ),
                textAlign: pw.TextAlign.right,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 0.2),
      ...data.items.map(
        (item) => pw.Container(
          margin: pw.EdgeInsets.symmetric(horizontal: detailTableInset),
          padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(
                width: qtyColumnWidth,
                child: pw.Text(
                  _formatTableQty(item.quantity),
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: compactTableFontSize,
                    color: bodyTextColor,
                  ),
                  maxLines: 1,
                  textAlign: pw.TextAlign.right,
                ),
              ),
              pw.SizedBox(width: detailGapWidth),
              pw.Expanded(
                child: pw.Text(
                  ReceiptText.truncateWithEllipsis(
                    _sanitizePrintText(item.name).toUpperCase(),
                    detailNameChars,
                  ),
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: math.max(compactDescriptionFontSize - 0.1, 9.6),
                    lineSpacing: 0.9,
                    color: bodyTextColor,
                  ),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
              pw.SizedBox(width: detailGapWidth),
              pw.SizedBox(
                width: priceColumnWidth,
                child: pw.Text(
                  tableMoney(item.unitPrice),
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: math.max(compactTableFontSize - 0.1, 9.4),
                    color: bodyTextColor,
                  ),
                  maxLines: 1,
                  textAlign: pw.TextAlign.right,
                ),
              ),
              pw.SizedBox(width: detailGapWidth),
              pw.SizedBox(
                width: totalColumnWidth,
                child: pw.Text(
                  tableMoney(item.total),
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: math.max(compactTableFontSize - 0.1, 9.4),
                    color: bodyTextColor,
                  ),
                  maxLines: 1,
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
      pw.SizedBox(height: 4),
      _buildRule(color: dividerColor),
      pw.SizedBox(height: 3),
      if (layout.showTotalsBreakdown) ...[
        _buildAmountRow(
          'SUBT.:',
          compactMoney(subtotal),
          uiBodyFont,
          boldFont,
          baseFontSize,
        ),
        if (data.discount > 0)
          _buildAmountRow(
            'DESC.:',
            compactMoney(data.discount),
            uiBodyFont,
            boldFont,
            baseFontSize,
          ),
        if (layout.showItbis && data.itbis > 0)
          _buildAmountRow(
            'ITBIS (${(data.itbisRate * 100).toStringAsFixed(0)}%):',
            compactMoney(data.itbis),
            uiBodyFont,
            boldFont,
            baseFontSize,
          ),
      ],
      _buildRule(color: dividerColor),
      pw.SizedBox(height: 4),
      _buildAmountRow(
        'TOTAL:',
        money(total),
        uiBodyFont,
        boldFont,
        totalsFontSize,
        emphasize: true,
      ),
      if (layout.showPaymentInfo) ...[
        pw.SizedBox(height: math.max(3.0, sectionGap - 2)),
        _buildPaymentSummary(
          paymentMethod: paymentMethod,
          isLayaway: data.isLayaway,
          isCredit: data.paymentMethod.toUpperCase() == 'CREDITO',
          lastPaymentAmount: data.lastPaymentAmount,
          paidAmount: data.paidAmount,
          effectivePaidAmount: paidAmount,
          pendingAmount: data.pendingAmount < 0 ? 0 : data.pendingAmount,
          changeAmount: data.changeAmount,
          bodyFont: bodyFont,
          boldFont: boldFont,
          fontSize: math.max(baseFontSize - 0.4, 9.0),
          color: bodyTextColor,
          dividerColor: dividerColor,
        ),
      ],
      pw.SizedBox(height: sectionGap),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14),
        child: pw.Text(
          'GRACIAS POR SU COMPRA',
          style: pw.TextStyle(
            font: bodyFont,
            fontSize: footerFontSize,
            color: bodyTextColor,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
      if (layout.warrantyPolicy.trim().isNotEmpty) ...[
        pw.SizedBox(height: math.max(3.0, sectionGap - 1)),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'POLITICA GARANTIA',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: math.max(baseFontSize - 0.6, 8.8),
                  color: bodyTextColor,
                ),
                textAlign: pw.TextAlign.left,
              ),
              pw.SizedBox(height: 2),
              pw.Container(height: 0.6, color: dividerColor),
            ],
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              ...ReceiptText.wrapText(
                layout.warrantyPolicy
                    .trim()
                    .split('\n')
                    .map((rawLine) => _sanitizePrintText(rawLine).trim())
                    .where((line) => line.isNotEmpty)
                    .join('. ')
                    .toUpperCase(),
                math.max(24, layout.maxCharsPerLine - 12),
              ).map(
                (line) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 1),
                  child: pw.Text(
                    line,
                    style: pw.TextStyle(
                      font: bodyFont,
                      fontSize: math.max(smallFontSize - 0.3, 8.3),
                      lineSpacing: 0.88,
                      color: bodyTextColor,
                    ),
                    textAlign: pw.TextAlign.left,
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: sectionGap),
      ],
    ];

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          pageWidth,
          pageHeight,
          marginLeft: marginLeftPts,
          marginRight: marginRightPts,
          marginTop: layout.topMarginPx.toDouble().clamp(0.0, 120.0),
          marginBottom: layout.bottomMarginPx.toDouble().clamp(0.0, 120.0),
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: content,
        ),
      ),
    );

    return doc;
  }

  pw.Widget _buildRule({PdfColor color = PdfColors.black}) {
    return pw.Container(
      height: 0.8,
      color: color,
      margin: const pw.EdgeInsets.symmetric(vertical: 1),
    );
  }

  pw.Widget _buildAmountRow(
    String label,
    String value,
    pw.Font bodyFont,
    pw.Font boldFont,
    double size, {
    bool emphasize = false,
  }) {
    final fontSize = emphasize ? math.min(size, 13.8) : size;
    final labelStyle = pw.TextStyle(
      font: boldFont,
      fontSize: fontSize,
      color: PdfColor.fromHex('#212121'),
    );
    final valueStyle = pw.TextStyle(
      font: emphasize ? boldFont : bodyFont,
      fontSize: fontSize,
      color: PdfColor.fromHex('#212121'),
    );
    const double labelWidth = 76;
    const double valueWidth = 82;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: labelWidth + valueWidth + 6,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: labelWidth,
                child: pw.Text(
                  label,
                  style: labelStyle,
                  textAlign: pw.TextAlign.right,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.SizedBox(
                width: valueWidth,
                child: pw.Text(
                  value,
                  style: valueStyle,
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  pw.Widget _buildPaymentSummary({
    required String paymentMethod,
    required bool isLayaway,
    required bool isCredit,
    required double lastPaymentAmount,
    required double paidAmount,
    required double effectivePaidAmount,
    required double pendingAmount,
    required double changeAmount,
    required pw.Font bodyFont,
    required pw.Font boldFont,
    required double fontSize,
    required PdfColor color,
    required PdfColor dividerColor,
  }) {
    final rows = <MapEntry<String, String>>[];

    if (isLayaway || isCredit) {
      if (lastPaymentAmount > 0) {
        rows.add(
          MapEntry(
            'ABONO',
            CurrencyDisplay.formatPlain(lastPaymentAmount, decimalDigits: 2),
          ),
        );
      }
      if (paidAmount > 0) {
        rows.add(
          MapEntry(
            'PAGADO',
            CurrencyDisplay.formatPlain(paidAmount, decimalDigits: 2),
          ),
        );
      }
      rows.add(
        MapEntry(
          'PENDIENTE',
          CurrencyDisplay.formatPlain(pendingAmount, decimalDigits: 2),
        ),
      );
    } else {
      rows.add(
        MapEntry(
          paymentMethod == 'EFECTIVO' ? 'RECIBIDO' : 'PAGADO',
          CurrencyDisplay.formatPlain(effectivePaidAmount, decimalDigits: 2),
        ),
      );
      if (changeAmount > 0) {
        rows.add(
          MapEntry(
            'CAMBIO',
            CurrencyDisplay.formatPlain(changeAmount, decimalDigits: 2),
          ),
        );
      }
    }

    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 20),
      padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 3),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: dividerColor, width: 0.6),
          bottom: pw.BorderSide(color: dividerColor, width: 0.6),
        ),
      ),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'TIPO DE PAGO',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: math.max(fontSize - 0.3, 8.8),
                    color: color,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                paymentMethod,
                style: pw.TextStyle(
                  font: bodyFont,
                  fontSize: math.max(fontSize - 0.1, 8.9),
                  color: color,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          ...rows.map(
            (row) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      row.key,
                      style: pw.TextStyle(
                        font: bodyFont,
                        fontSize: math.max(fontSize - 0.2, 8.8),
                        color: color,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    row.value,
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: math.max(fontSize - 0.1, 8.9),
                      color: color,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _resolveSalesDocumentTitle(TicketData data) {
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

  String _buildFacCode(String ticketNumber) {
    final trimmed = ticketNumber.trim();
    if (trimmed.isEmpty) return 'FAC-0000';
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) {
      return 'FAC-${digits.substring(math.max(0, digits.length - 4)).padLeft(4, '0')}';
    }
    final cleaned = trimmed.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return 'FAC-${cleaned.substring(math.max(0, cleaned.length - 4)).padLeft(4, '0')}';
  }

  String _sanitizePrintText(String input) {
    return input
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'''[^A-Za-z0-9À-ÿ\s\-_/.:,()#%+*&@'"$<>]+'''), '')
        .trim();
  }

  String _formatTableQty(double quantity) {
    final whole = quantity.truncateToDouble() == quantity;
    return whole
        ? quantity.toStringAsFixed(0)
        : quantity
              .toStringAsFixed(2)
              .replaceAll(RegExp(r'0+$'), '')
              .replaceAll(RegExp(r'\.$'), '');
  }

  String _formatDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString().padLeft(4, '0');
    return '$day/$month/$year';
  }

  String _formatTime(DateTime dateTime) {
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    final normalizedHour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final hour = normalizedHour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  // ============================================================
  // HELPERS: Ahora la mayoría están en TicketRenderer
  // Estos helpers se mantienen solo si se usan en otros métodos
  // ============================================================
}
